import AppKit
import AulaWheelCore
import CryptoKit
import Foundation

/// Finds new releases on GitHub, downloads and stages them, and installs them when it won't get in
/// the user's way: when they ask, when the app quits or starts, or after they've been away a while.
///
/// None of this runs on the input path. Checks, downloads and idle installs work off the main
/// thread; launch and quit installs block it, but only while the app isn't handling the keyboard.
/// The new version only runs after this process quits, which hands the keyboard back to macOS first.
@MainActor
final class Updater {
    static let repository = "sonla58/aula-wheel-macos"

    private enum Key {
        static let automatic = "automaticUpdates"
        static let lastCheck = "updateLastCheck"
        static let launchAttempt = "updateLaunchAttemptVersion"
        static let rejected = "updateRejectedVersion"
    }

    /// Called whenever `phase` changes.
    var onChange: (() -> Void)?
    /// Shows a short HUD message; only used for checks the user started.
    var announce: ((_ symbol: String, _ title: String, _ subtitle: String?) -> Void)?
    /// True while the user is in the middle of something an idle restart would interrupt.
    var isBusy: () -> Bool = { false }

    private(set) var phase: UpdatePhase = .idle {
        didSet { if phase != oldValue { onChange?() } }
    }

    let current: AppVersion?
    private let defaults = UserDefaults.standard
    private let target = Bundle.main.bundleURL
    private let bundleID = Bundle.main.bundleIdentifier
    private let blocker: String?
    private var staged: AppVersion?
    private var releasePage: URL?
    private var work: Task<Void, Never>?
    /// Identifies the current `work`, so a cancelled check finishing late can't clear or overwrite a newer state.
    private var workID = 0
    private var installing = false
    /// The last automatic check that was started, successful or not; kept in memory only.
    private var lastAttempt: Date?
    /// Set when an install fails, so the app never retries on its own in a loop; a new download clears it.
    private var autoInstallPaused = false
    private var timer: Timer?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    init() {
        current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)
        blocker = UpdateInstaller.blocker()
        releasePage = URL(string: "https://github.com/\(Self.repository)/releases/latest")
    }

    var automatic: Bool {
        get { defaults.object(forKey: Key.automatic) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Key.automatic)
            if newValue { checkIfDue() }
        }
    }

    // MARK: - Lifecycle

    /// Cleans up and finds a staged update. Call first thing at launch.
    func prepareAtLaunch() {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: UpdateInstaller.updatesDirectory.path) {
            for name in names where name.hasPrefix("work-") {
                try? fm.removeItem(at: UpdateInstaller.updatesDirectory.appendingPathComponent(name))
            }
        }
        if blocker == nil { UpdateInstaller.removeLeftovers(nextTo: target) }

        let stagedApp = UpdateInstaller.stagedApp
        guard fm.fileExists(atPath: stagedApp.path) else { return }
        if let version = UpdateInstaller.version(of: stagedApp), let current, version > current, blocker == nil {
            staged = version
            phase = .ready(version)
        } else {
            discardStaged()
        }
    }

    /// Installs a staged update before the app touches the keyboard. Returns true when the app is
    /// quitting to relaunch the new version, in which case the caller should do nothing more.
    func installAtLaunchIfNeeded() -> Bool {
        guard stagedStillThere(), let staged, let current else { return false }
        let tried = defaults.string(forKey: Key.launchAttempt) == staged.description
        guard UpdatePolicy.shouldInstall(
            staged: staged, current: current, moment: .launching(alreadyTriedThisVersion: tried)) else { return false }
        // Recorded before trying, so a failed or interrupted install still uses up the one attempt.
        defaults.set(staged.description, forKey: Key.launchAttempt)
        Log.update.notice("installing \(staged.description, privacy: .public) at launch")
        return installNowAndRelaunch(version: staged)
    }

    /// Starts periodic checks. Nothing goes over the network until a short while after launch.
    func start() {
        let first = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(first, forMode: .common)
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Installs a staged update while quitting, without relaunching. Call after the keyboard has
    /// been handed back to macOS.
    func installOnQuit() {
        guard !installing, stagedStillThere(), let staged, let current,
              UpdatePolicy.shouldInstall(staged: staged, current: current, moment: .quitting) else { return }
        work?.cancel()
        work = nil
        do {
            let prepared = try UpdateInstaller.prepare(
                staged: UpdateInstaller.stagedApp, nextTo: target, expected: staged, bundleID: bundleID,
                requirement: UpdateInstaller.selfRequirement())
            try UpdateInstaller.swap(prepared, into: target)
            discardStaged()
            Log.update.notice("installed \(staged.description, privacy: .public) on quit")
        } catch {
            Log.update.error("install on quit failed: \(String(describing: error), privacy: .public)")
            handleInstallFailure(error, version: staged)
        }
    }

    private func tick() {
        checkIfDue()
        guard automatic, !autoInstallPaused, let staged, let current, !installing else { return }
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard UpdatePolicy.shouldInstall(
            staged: staged, current: current, moment: .idle(seconds: idle, busy: isBusy())) else { return }
        Log.update.notice("installing \(staged.description, privacy: .public) after \(Int(idle), privacy: .public)s idle")
        restartToUpdate(userInitiated: false)
    }

    private func checkIfDue() {
        let now = Date()
        guard automatic, current != nil, work == nil, !installing,
              UpdatePolicy.isCheckDue(
                now: now, lastCheck: defaults.object(forKey: Key.lastCheck) as? Date, lastAttempt: lastAttempt)
        else { return }
        lastAttempt = now
        check(userInitiated: false)
    }

    // MARK: - Checking and downloading

    func check(userInitiated: Bool) {
        guard let current else {
            phase = .failed("this build has no version")
            return
        }
        guard work == nil, !installing else { return }
        let previous = phase
        phase = .checking
        workID += 1
        let id = workID
        work = Task { [weak self] in
            guard let self else { return }
            defer { if self.workID == id { self.work = nil } }
            do {
                let release = try await self.fetchLatestRelease()
                try Task.checkCancellation()
                switch UpdatePolicy.check(release, current: current) {
                case .upToDate:
                    self.defaults.set(Date(), forKey: Key.lastCheck)
                    if let staged = self.staged {
                        self.phase = .ready(staged)
                    } else {
                        self.phase = .upToDate
                        if userInitiated {
                            self.announce?("checkmark.circle.fill", "\(UpdateInstaller.appName) is up to date",
                                           "Version \(current)")
                        }
                    }
                case .noDownload(let version, let page):
                    // Not recorded as a successful check, so it is tried again within the hour.
                    self.releasePage = page ?? self.releasePage
                    self.phase = .manualOnly(
                        version, reason: "\(UpdateInstaller.appName) \(version) has no automatic download yet")
                    if userInitiated { self.announceAvailable(version) }
                case .update(let update):
                    self.defaults.set(Date(), forKey: Key.lastCheck)
                    self.releasePage = update.releasePage ?? self.releasePage
                    try await self.handle(update, userInitiated: userInitiated)
                }
            } catch is CancellationError {
                // Only undo what this check showed; an install may have set something newer meanwhile.
                switch self.phase {
                case .checking, .downloading: self.phase = self.staged.map { .ready($0) } ?? previous
                default: break
                }
            } catch {
                Log.update.error("update check failed: \(String(describing: error), privacy: .public)")
                // An update already downloaded stays installable; the next check tries again.
                self.phase = self.staged.map { .ready($0) } ?? .failed(String(describing: error))
                if userInitiated {
                    self.announce?("exclamationmark.triangle.fill", "Update failed", String(describing: error))
                }
            }
        }
    }

    private func handle(_ update: AvailableUpdate, userInitiated: Bool) async throws {
        if staged == update.version {
            phase = .ready(update.version)
            if userInitiated { announceReady(update.version) }
            return
        }
        if let blocker {
            phase = .manualOnly(update.version, reason: blocker)
        } else if defaults.string(forKey: Key.rejected) == rejectionKey(update.version) {
            phase = .manualOnly(update.version, reason: "\(update.version) can't be installed automatically")
        } else {
            phase = .downloading(update.version)
            do {
                try await download(update)
            } catch let failure as UpdateInstaller.Failure where failure.rejectsVersion {
                defaults.set(rejectionKey(update.version), forKey: Key.rejected)
                phase = .manualOnly(update.version, reason: failure.description)
                if userInitiated {
                    announce?("exclamationmark.triangle.fill", "Update can't be installed", failure.description)
                }
                return
            }
            staged = update.version
            autoInstallPaused = false
            phase = .ready(update.version)
            if userInitiated { announceReady(update.version) }
            return
        }
        if userInitiated { announceAvailable(update.version) }
    }

    private func announceAvailable(_ version: AppVersion) {
        announce?("arrow.down.circle.fill", "\(UpdateInstaller.appName) \(version) is available",
                  "Download it from the menu")
    }

    private func rejectionKey(_ version: AppVersion) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") ?? AppVersion("0")!
        return UpdatePolicy.rejectionKey(version: version, current: current ?? AppVersion("0")!, os: osVersion)
    }

    private func announceReady(_ version: AppVersion) {
        announce?("arrow.down.circle.fill", "\(UpdateInstaller.appName) \(version) is ready",
                  "Choose Restart to Update in the menu")
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("\(UpdateInstaller.appName)/\(current?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch { try await self.session.data(for: request) }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            do { return try GitHubRelease.decode(data) } catch {
                throw UpdateInstaller.Failure("GitHub sent a release it couldn't read")
            }
        case 404:
            throw UpdateInstaller.Failure("no releases found on GitHub")
        case 403, 429:
            throw UpdateInstaller.Failure("GitHub is limiting requests; will try again later")
        case let code:
            throw UpdateInstaller.Failure("GitHub returned error \(code)")
        }
    }

    private func download(_ update: AvailableUpdate) async throws {
        let fm = FileManager.default
        let workDir = UpdateInstaller.updatesDirectory.appendingPathComponent("work-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        var request = URLRequest(url: update.downloadURL)
        request.setValue("\(UpdateInstaller.appName)/\(current?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await fetch { try await self.session.download(for: request) }
        let zip = workDir.appendingPathComponent("update.zip")
        try fm.moveItem(at: temp, to: zip)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateInstaller.Failure("download failed (error \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        try Task.checkCancellation()

        let expected = update.version
        let bundleID = bundleID
        let unpacked = workDir.appendingPathComponent("unpacked", isDirectory: true)
        let app = unpacked.appendingPathComponent("\(UpdateInstaller.appName).app", isDirectory: true)
        try await Task.detached(priority: .utility) {
            let size = (try? fm.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? -1
            guard size == update.size else { throw UpdateInstaller.Failure("the download was incomplete") }
            if let sha256 = update.sha256 {
                let digest = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe))
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                guard hex == sha256 else { throw UpdateInstaller.Failure("the download was corrupted") }
            }
            try Self.unzip(zip, to: unpacked)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: app.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw UpdateInstaller.Failure("the download has no \(UpdateInstaller.appName).app", rejectsVersion: true)
            }
            try UpdateInstaller.verify(
                app, expected: expected, bundleID: bundleID, requirement: UpdateInstaller.selfRequirement())
        }.value
        try Task.checkCancellation()

        let stagedApp = UpdateInstaller.stagedApp
        try? fm.removeItem(at: stagedApp.deletingLastPathComponent())
        try fm.createDirectory(at: stagedApp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: app, to: stagedApp)
        Log.update.notice("staged \(expected.description, privacy: .public)")
    }

    private nonisolated static func unzip(_ zip: URL, to folder: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", zip.path, folder.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateInstaller.Failure("couldn't unpack the download") }
    }

    /// Network errors read as one plain sentence in the menu.
    private func fetch<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            Log.update.error("network: \(error.localizedDescription, privacy: .public)")
            throw UpdateInstaller.Failure(error.code == .timedOut ? "GitHub didn't respond" : "can't reach GitHub")
        }
    }

    // MARK: - Installing

    /// "Restart to Update", or an idle install. The slow copy and verify run off the main thread.
    func restartToUpdate(userInitiated: Bool = true) {
        guard !installing else { return }
        guard stagedStillThere(), let staged else {
            // macOS may clear Caches; fetch the update again.
            if userInitiated { check(userInitiated: true) }
            return
        }
        work?.cancel()
        work = nil
        installing = true
        let stagedApp = UpdateInstaller.stagedApp
        let target = target
        let bundleID = bundleID
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try UpdateInstaller.prepare(
                        staged: stagedApp, nextTo: target, expected: staged, bundleID: bundleID,
                        requirement: UpdateInstaller.selfRequirement())
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let prepared):
                self.finishInstall(prepared, version: staged, userInitiated: userInitiated)
            case .failure(let error):
                self.installing = false
                self.handleInstallFailure(error, version: staged)
                if userInitiated {
                    self.announce?("exclamationmark.triangle.fill", "Update failed", String(describing: error))
                }
            }
        }
    }

    private func finishInstall(_ prepared: URL, version: AppVersion, userInitiated: Bool) {
        // The user may have come back while the copy was made.
        if !userInitiated, let current {
            let idle = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            guard UpdatePolicy.shouldInstall(
                staged: version, current: current, moment: .idle(seconds: idle, busy: isBusy())) else {
                try? FileManager.default.removeItem(at: prepared)
                installing = false
                return
            }
        }
        do {
            try UpdateInstaller.swap(prepared, into: target)
        } catch {
            installing = false
            handleInstallFailure(error, version: version)
            if userInitiated { announce?("exclamationmark.triangle.fill", "Update failed", String(describing: error)) }
            return
        }
        discardStaged()
        relaunchAndQuit(version: version)
    }

    /// Synchronous install for launch, before anything else is running.
    private func installNowAndRelaunch(version: AppVersion) -> Bool {
        installing = true
        do {
            let prepared = try UpdateInstaller.prepare(
                staged: UpdateInstaller.stagedApp, nextTo: target, expected: version, bundleID: bundleID,
                requirement: UpdateInstaller.selfRequirement())
            try UpdateInstaller.swap(prepared, into: target)
        } catch {
            installing = false
            Log.update.error("install at launch failed: \(String(describing: error), privacy: .public)")
            handleInstallFailure(error, version: version)
            return false
        }
        discardStaged()
        relaunchAndQuit(version: version)
        return true
    }

    private func relaunchAndQuit(version: AppVersion) {
        Log.update.notice("installed \(version.description, privacy: .public), relaunching")
        do {
            try UpdateInstaller.relaunch(target)
        } catch {
            // The new version is in place; it just won't open by itself.
            Log.update.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    private func handleInstallFailure(_ error: Error, version: AppVersion) {
        autoInstallPaused = true
        if let failure = error as? UpdateInstaller.Failure, failure.rejectsVersion {
            defaults.set(rejectionKey(version), forKey: Key.rejected)
            discardStaged()
            phase = .manualOnly(version, reason: failure.description)
        } else {
            // Keep the staged copy for a later attempt, but stop installing it on our own.
            phase = .failed(String(describing: error))
        }
    }

    /// False (and the staged state forgotten) when the staged copy has gone from disk.
    private func stagedStillThere() -> Bool {
        guard staged != nil else { return false }
        if FileManager.default.fileExists(atPath: UpdateInstaller.stagedApp.path) { return true }
        Log.update.notice("staged update is gone from disk")
        staged = nil
        phase = .idle
        return false
    }

    private func discardStaged() {
        staged = nil
        try? FileManager.default.removeItem(at: UpdateInstaller.stagedApp.deletingLastPathComponent())
    }

    func openReleasePage() {
        if let releasePage { NSWorkspace.shared.open(releasePage) }
    }
}
