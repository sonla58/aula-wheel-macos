import AulaWheelCore
import Foundation
import Security

/// File work for updates: checking a downloaded app, and swapping it in place of the running one.
///
/// The swap is a single atomic rename, so whatever interrupts it (crash, power loss, a killed
/// process), the app at the original path is either the old version or the new one. Only volumes
/// without `RENAME_SWAP` fall back to two renames, with a brief moment where no app is there.
enum UpdateInstaller {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        /// The download itself is not acceptable (not ours, wrong version, needs a newer macOS),
        /// so downloading it again would not help.
        var rejectsVersion = false
        init(_ description: String, rejectsVersion: Bool = false) {
            self.description = description
            self.rejectsVersion = rejectsVersion
        }
    }

    static let appName = UpdatePolicy.appName
    private static let tempPrefix = ".\(appName)-update-"

    /// `~/Library/Caches/<bundle id>/Updates`: downloads and the staged app, never anything the user sees.
    static var updatesDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.aulawheel.AulaWheel", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static var stagedApp: URL {
        updatesDirectory.appendingPathComponent("ready", isDirectory: true).appendingPathComponent("\(appName).app")
    }

    // MARK: - Can this copy update itself?

    /// Why the running copy can't replace itself, or nil when it can.
    static func blocker(bundle: URL = Bundle.main.bundleURL) -> String? {
        guard bundle.pathExtension == "app", Bundle.main.bundleIdentifier != nil else {
            return "Updates need the app bundle"
        }
        let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        if readOnly || bundle.path.contains("/AppTranslocation/") {
            return "Move \(appName) to Applications to get updates"
        }
        let folder = bundle.deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: folder.path), fm.isWritableFile(atPath: bundle.path) else {
            return "No permission to replace \(appName) in \(folder.lastPathComponent)"
        }
        guard let info = signingInfo(of: bundle),
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty else {
            // An ad-hoc signature only matches itself, so no release could ever pass verification.
            return "This copy isn't signed for automatic updates"
        }
        return nil
    }

    // MARK: - Verifying

    /// The running app's designated requirement. A release must satisfy it, which is also what
    /// keeps the Accessibility and Input Monitoring grants valid after the update.
    static func selfRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }

    static func requirement(of bundle: URL) -> SecRequirement? {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }

    private static func signingInfo(of bundle: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess
        else { return nil }
        return info as? [String: Any]
    }

    static func version(of bundle: URL) -> AppVersion? {
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let string = info["CFBundleShortVersionString"] as? String else { return nil }
        return AppVersion(string)
    }

    /// Checks that `bundle` is this app, at `expected`, runs on this Mac, and is signed so that it
    /// satisfies `requirement` (normally `selfRequirement()`).
    static func verify(
        _ bundle: URL, expected: AppVersion, bundleID: String?, requirement: SecRequirement?
    ) throws {
        guard let bundleID, let requirement else {
            throw Failure("This copy isn't signed for automatic updates")
        }
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else {
            throw Failure("The download is not an app", rejectsVersion: true)
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else {
            throw Failure("The download is a different app", rejectsVersion: true)
        }
        guard version(of: bundle) == expected else {
            throw Failure("The download is not version \(expected)", rejectsVersion: true)
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if let minimum = (info["LSMinimumSystemVersion"] as? String).flatMap(AppVersion.init),
           let current = AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
           minimum > current {
            throw Failure("\(appName) \(expected) needs macOS \(minimum)", rejectsVersion: true)
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw Failure("The download is not a signed app", rejectsVersion: true)
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        var error: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &error)
        guard status == errSecSuccess else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "status \(status)"
            Log.update.error("signature check failed: \(reason, privacy: .public)")
            throw Failure(
                status == errSecCSReqFailed
                    ? "The update is not signed by the same developer as this copy"
                    : "The update's signature is invalid",
                rejectsVersion: true)
        }
    }

    // MARK: - Installing

    /// Copies the staged app next to `target` (so the swap is a rename on one volume) and verifies
    /// the copy, which is exactly what will be installed. Slow enough to keep off the main thread.
    static func prepare(staged: URL, nextTo target: URL, expected: AppVersion, bundleID: String?,
                        requirement: SecRequirement?) throws -> URL {
        let prepared = target.deletingLastPathComponent()
            .appendingPathComponent("\(tempPrefix)\(UUID().uuidString).app", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: staged, to: prepared)
        } catch {
            throw Failure(describe(error, folder: target.deletingLastPathComponent()))
        }
        do {
            try verify(prepared, expected: expected, bundleID: bundleID, requirement: requirement)
        } catch {
            try? FileManager.default.removeItem(at: prepared)
            throw error
        }
        return prepared
    }

    /// Exchanges `prepared` and `target`, then deletes the old app. `prepared` is removed either way.
    static func swap(_ prepared: URL, into target: URL) throws {
        defer { try? FileManager.default.removeItem(at: prepared) }
        if renamex_np(prepared.path, target.path, UInt32(RENAME_SWAP)) == 0 { return }
        let swapError = errno
        guard swapError == ENOTSUP || swapError == EINVAL else {
            throw Failure(describe(errno: swapError, folder: target.deletingLastPathComponent()))
        }
        // Volumes without RENAME_SWAP: two renames, undoing the first if the second fails.
        let old = target.deletingLastPathComponent()
            .appendingPathComponent("\(tempPrefix)\(UUID().uuidString)-old.app", isDirectory: true)
        guard rename(target.path, old.path) == 0 else {
            throw Failure(describe(errno: errno, folder: target.deletingLastPathComponent()))
        }
        guard rename(prepared.path, target.path) == 0 else {
            let moveError = errno
            _ = rename(old.path, target.path)
            throw Failure(describe(errno: moveError, folder: target.deletingLastPathComponent()))
        }
        try? FileManager.default.removeItem(at: old)
    }

    /// Opens `app` once this process has exited (or after 10 s), so the new copy starts fresh.
    static func relaunch(_ app: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; /usr/bin/open \"$2\"",
            "sh", String(getpid()), app.path,
        ]
        try task.run()
    }

    /// Removes half-finished copies left next to the app by an install that was interrupted.
    static func removeLeftovers(nextTo target: URL) {
        let folder = target.deletingLastPathComponent()
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(tempPrefix) && name.hasSuffix(".app") {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func describe(_ error: Error, folder: URL) -> String {
        let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
        if let posix = underlying, posix.domain == NSPOSIXErrorDomain {
            return describe(errno: Int32(posix.code), folder: folder)
        }
        if (error as NSError).code == NSFileWriteNoPermissionError {
            return describe(errno: EPERM, folder: folder)
        }
        return error.localizedDescription
    }

    private static func describe(errno code: Int32, folder: URL) -> String {
        switch code {
        case EPERM, EACCES:
            // macOS's App Management protection reports a refused write as EPERM.
            "macOS blocked it; allow \(appName) in Privacy & Security → App Management"
        case ENOSPC:
            "Not enough disk space"
        default:
            String(cString: strerror(code))
        }
    }
}
