import Foundation

/// One to four numbers such as `0.0.2`, optionally after a `v` as in tags. Suffixes (`1.0-beta`) are rejected.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let description: String
    /// Numeric components without trailing zeros, so `1.0` and `1.0.0` compare and hash equal.
    private let key: [Int]

    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        description = String(text)
        while numbers.last == 0 { numbers.removeLast() }
        key = numbers
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.key.count, rhs.key.count) {
            let left = index < lhs.key.count ? lhs.key[index] : 0
            let right = index < rhs.key.count ? rhs.key[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

/// The parts of a GitHub release (`GET /repos/{owner}/{repo}/releases/latest`) the updater uses.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public var name: String
        public var size: Int
        public var digest: String?
        public var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }

        public init(name: String, size: Int, digest: String? = nil, browserDownloadURL: URL) {
            self.name = name
            self.size = size
            self.digest = digest
            self.browserDownloadURL = browserDownloadURL
        }
    }

    public var tagName: String
    public var draft: Bool
    public var prerelease: Bool
    public var htmlURL: URL?
    public var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
        case htmlURL = "html_url"
    }

    public init(tagName: String, draft: Bool = false, prerelease: Bool = false, htmlURL: URL? = nil, assets: [Asset]) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
        self.htmlURL = htmlURL
        self.assets = assets
    }

    public static func decode(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

/// A newer release with a zip of the app that can be downloaded.
public struct AvailableUpdate: Equatable, Sendable {
    public var version: AppVersion
    public var downloadURL: URL
    public var size: Int
    /// Lowercase hex SHA-256 of the zip, when GitHub reports one.
    public var sha256: String?
    public var releasePage: URL?
}

/// When the app may swap in a downloaded update.
public enum InstallMoment: Equatable, Sendable {
    /// The user chose "Restart to Update".
    case userRequested
    /// The app is quitting; it replaces itself without relaunching.
    case quitting
    /// The app just started, before it touches the keyboard. Tried once per version, so a bad
    /// update cannot make the app relaunch itself in a loop.
    case launching(alreadyTriedThisVersion: Bool)
    /// Periodic check while running: `seconds` since the last keyboard or mouse input, and `busy`
    /// for anything the user is in the middle of.
    case idle(seconds: TimeInterval, busy: Bool)
}

/// What the update item in the menu shows.
public enum UpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case downloading(AppVersion)
    case ready(AppVersion)
    /// A newer version exists but this copy cannot replace itself; the user downloads it.
    case manualOnly(AppVersion, reason: String)
    case failed(String)
}

public enum UpdateMenuAction: Equatable, Sendable {
    case check
    case restartToUpdate
    case openReleasePage
}

public struct UpdateMenuEntry: Equatable, Sendable {
    /// A disabled line explaining the state, if any.
    public var status: String?
    public var actionTitle: String?
    public var action: UpdateMenuAction?
}

public enum UpdatePolicy {
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    /// After a failed check (offline, GitHub limiting requests), wait this long before the next one.
    public static let retryInterval: TimeInterval = 60 * 60
    /// No keyboard or mouse input for this long counts as away from the Mac.
    public static let idleBeforeInstall: TimeInterval = 10 * 60
    public static let appName = "AulaWheel"

    /// `lastCheck` is the last successful check; `lastAttempt` the last one that was started.
    public static func isCheckDue(now: Date, lastCheck: Date?, lastAttempt: Date? = nil) -> Bool {
        elapsed(since: lastCheck, now: now, atLeast: checkInterval)
            && elapsed(since: lastAttempt, now: now, atLeast: retryInterval)
    }

    private static func elapsed(since date: Date?, now: Date, atLeast interval: TimeInterval) -> Bool {
        guard let date else { return true }
        // A clock moved backwards would otherwise postpone checks until it catches up.
        if date > now { return true }
        return now.timeIntervalSince(date) >= interval
    }

    /// The release's zip, if it is a published, final release newer than `current` and served over HTTPS.
    public static func update(from release: GitHubRelease, current: AppVersion) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName), version > current else { return nil }
        let expectedName = "\(appName)-\(version.description).zip"
        guard let asset = release.assets.first(where: { $0.name == expectedName }),
              asset.browserDownloadURL.scheme == "https", asset.size > 0 else { return nil }
        return AvailableUpdate(
            version: version,
            downloadURL: asset.browserDownloadURL,
            size: asset.size,
            sha256: sha256(fromDigest: asset.digest),
            releasePage: release.htmlURL)
    }

    /// GitHub reports digests as `sha256:<hex>`.
    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    public static func shouldInstall(staged: AppVersion, current: AppVersion, moment: InstallMoment) -> Bool {
        guard staged > current else { return false }
        switch moment {
        case .userRequested, .quitting:
            return true
        case .launching(let alreadyTried):
            return !alreadyTried
        case .idle(let seconds, let busy):
            return !busy && seconds >= idleBeforeInstall
        }
    }

    public static func menuEntry(for phase: UpdatePhase) -> UpdateMenuEntry {
        switch phase {
        case .idle, .upToDate:
            UpdateMenuEntry(actionTitle: "Check for Updates", action: .check)
        case .checking:
            UpdateMenuEntry(status: "Checking for updates…")
        case .downloading(let version):
            UpdateMenuEntry(status: "Downloading \(appName) \(version)…")
        case .ready(let version):
            UpdateMenuEntry(actionTitle: "Restart to Update to \(version)", action: .restartToUpdate)
        case .manualOnly(let version, let reason):
            UpdateMenuEntry(status: reason, actionTitle: "Download \(appName) \(version)…", action: .openReleasePage)
        case .failed(let message):
            UpdateMenuEntry(status: "Update failed: \(message)", actionTitle: "Check for Updates", action: .check)
        }
    }
}
