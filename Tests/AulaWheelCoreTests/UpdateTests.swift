import Foundation
import Testing
@testable import AulaWheelCore

@Suite struct UpdateTests {
    func v(_ string: String) -> AppVersion { AppVersion(string)! }

    func release(
        _ tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String]? = nil, digest: String? = nil
    ) -> GitHubRelease {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let names = assets ?? ["AulaWheel-\(version).dmg", "AulaWheel-\(version).zip"]
        return GitHubRelease(
            tagName: tag, draft: draft, prerelease: prerelease,
            htmlURL: URL(string: "https://github.com/o/r/releases/tag/\(tag)"),
            assets: names.map {
                .init(name: $0, size: 1000, digest: digest,
                      browserDownloadURL: URL(string: "https://github.com/o/r/releases/download/\(tag)/\($0)")!)
            })
    }

    // MARK: - Versions

    @Test func parsesVersionsWithOrWithoutV() {
        #expect(AppVersion("0.0.2") == AppVersion("v0.0.2"))
        #expect(AppVersion("v1.2.3")?.description == "1.2.3")
        #expect(AppVersion("1.0") == AppVersion("1.0.0"))
        #expect(Set([v("1.0"), v("1.0.0")]).count == 1)
    }

    @Test func rejectsAnythingButPlainNumbers() {
        for bad in ["", "v", "1.0-beta", "1..2", "1.2.", "a.b", "1.2.3.4.5", " ", "-1", "1.+2", "１.２"] {
            #expect(AppVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func comparesNumericallyNotAlphabetically() {
        #expect(v("0.0.10") > v("0.0.9"))
        #expect(v("0.1") > v("0.0.99"))
        #expect(v("1.0.1") > v("1.0"))
        #expect(!(v("1.0") < v("1.0.0")))
        #expect(v("2") > v("1.9.9"))
    }

    // MARK: - Choosing a release

    @Test func picksTheZipOfANewerRelease() throws {
        let update = try #require(UpdatePolicy.update(from: release("v0.0.3"), current: v("0.0.2")))
        #expect(update.version == v("0.0.3"))
        #expect(update.downloadURL.lastPathComponent == "AulaWheel-0.0.3.zip")
        #expect(update.releasePage?.absoluteString == "https://github.com/o/r/releases/tag/v0.0.3")
    }

    @Test func ignoresSameOrOlderReleases() {
        #expect(UpdatePolicy.update(from: release("v0.0.2"), current: v("0.0.2")) == nil)
        #expect(UpdatePolicy.update(from: release("v0.0.1"), current: v("0.0.2")) == nil)
        #expect(UpdatePolicy.update(from: release("v0.0.2.0"), current: v("0.0.2")) == nil)
    }

    @Test func ignoresDraftsPrereleasesAndOddTags() {
        #expect(UpdatePolicy.update(from: release("v0.1.0", draft: true), current: v("0.0.2")) == nil)
        #expect(UpdatePolicy.update(from: release("v0.1.0", prerelease: true), current: v("0.0.2")) == nil)
        #expect(UpdatePolicy.update(from: release("v0.1.0-rc1"), current: v("0.0.2")) == nil)
    }

    @Test func needsAZipNamedForTheVersion() {
        #expect(UpdatePolicy.update(from: release("v0.1.0", assets: ["AulaWheel-0.1.0.dmg"]), current: v("0.0.2")) == nil)
        #expect(UpdatePolicy.update(from: release("v0.1.0", assets: ["AulaWheel-0.0.9.zip"]), current: v("0.0.2")) == nil)
        #expect(UpdatePolicy.update(from: release("v0.1.0", assets: ["Other-0.1.0.zip"]), current: v("0.0.2")) == nil)
    }

    @Test func refusesPlainHTTPDownloads() {
        var insecure = release("v0.1.0")
        insecure.assets = insecure.assets.map {
            var asset = $0
            asset.browserDownloadURL = URL(string: "http://example.com/\($0.name)")!
            return asset
        }
        #expect(UpdatePolicy.update(from: insecure, current: v("0.0.2")) == nil)
    }

    @Test func keepsAValidSHA256Digest() {
        let hex = String(repeating: "ab", count: 32)
        #expect(UpdatePolicy.update(from: release("v1", digest: "sha256:\(hex.uppercased())"), current: v("0"))?.sha256 == hex)
        #expect(UpdatePolicy.update(from: release("v1", digest: "sha512:\(hex)"), current: v("0"))?.sha256 == nil)
        #expect(UpdatePolicy.update(from: release("v1", digest: "sha256:abc"), current: v("0"))?.sha256 == nil)
        #expect(UpdatePolicy.update(from: release("v1"), current: v("0"))?.sha256 == nil)
    }

    @Test func decodesGitHubsReleaseJSON() throws {
        let json = """
        {"tag_name":"v0.0.3","draft":false,"prerelease":false,"name":"AulaWheel 0.0.3",
         "html_url":"https://github.com/o/r/releases/tag/v0.0.3",
         "assets":[{"name":"AulaWheel-0.0.3.zip","size":684696,"digest":null,"content_type":"application/zip",
                    "browser_download_url":"https://github.com/o/r/releases/download/v0.0.3/AulaWheel-0.0.3.zip"}]}
        """
        let decoded = try GitHubRelease.decode(Data(json.utf8))
        #expect(decoded.tagName == "v0.0.3")
        #expect(decoded.assets.first?.size == 684696)
        #expect(decoded.assets.first?.digest == nil)
        #expect(UpdatePolicy.update(from: decoded, current: v("0.0.2"))?.size == 684696)
    }

    // MARK: - Schedule

    @Test func checksWhenNeverCheckedOrADayHasPassed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: nil))
        #expect(!UpdatePolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(-3600)))
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(-UpdatePolicy.checkInterval)))
    }

    @Test func waitsAnHourAfterAFailedCheck() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let dayAgo = now.addingTimeInterval(-2 * UpdatePolicy.checkInterval)
        #expect(!UpdatePolicy.isCheckDue(now: now, lastCheck: dayAgo, lastAttempt: now.addingTimeInterval(-60)))
        #expect(!UpdatePolicy.isCheckDue(now: now, lastCheck: nil, lastAttempt: now.addingTimeInterval(-60)))
        #expect(UpdatePolicy.isCheckDue(
            now: now, lastCheck: dayAgo, lastAttempt: now.addingTimeInterval(-UpdatePolicy.retryInterval)))
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: dayAgo, lastAttempt: now.addingTimeInterval(60)))
    }

    @Test func checksWhenTheClockWentBackwards() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(3600)))
    }

    // MARK: - When to install

    @Test func neverInstallsSameOrOlder() {
        for moment: InstallMoment in [.userRequested, .quitting, .launching(alreadyTriedThisVersion: false),
                                      .idle(seconds: 3600, busy: false)] {
            #expect(!UpdatePolicy.shouldInstall(staged: v("0.0.2"), current: v("0.0.2"), moment: moment))
            #expect(!UpdatePolicy.shouldInstall(staged: v("0.0.1"), current: v("0.0.2"), moment: moment))
        }
    }

    @Test func installsWhenAskedOrQuitting() {
        #expect(UpdatePolicy.shouldInstall(staged: v("0.0.3"), current: v("0.0.2"), moment: .userRequested))
        #expect(UpdatePolicy.shouldInstall(staged: v("0.0.3"), current: v("0.0.2"), moment: .quitting))
    }

    @Test func installsAtLaunchOnlyOncePerVersion() {
        #expect(UpdatePolicy.shouldInstall(
            staged: v("0.0.3"), current: v("0.0.2"), moment: .launching(alreadyTriedThisVersion: false)))
        #expect(!UpdatePolicy.shouldInstall(
            staged: v("0.0.3"), current: v("0.0.2"), moment: .launching(alreadyTriedThisVersion: true)))
    }

    @Test func installsWhileRunningOnlyWhenTheUserIsAway() {
        let idle = UpdatePolicy.idleBeforeInstall
        #expect(!UpdatePolicy.shouldInstall(staged: v("0.0.3"), current: v("0.0.2"), moment: .idle(seconds: idle - 1, busy: false)))
        #expect(UpdatePolicy.shouldInstall(staged: v("0.0.3"), current: v("0.0.2"), moment: .idle(seconds: idle, busy: false)))
        #expect(!UpdatePolicy.shouldInstall(staged: v("0.0.3"), current: v("0.0.2"), moment: .idle(seconds: idle * 10, busy: true)))
    }

    // MARK: - Menu

    @Test func menuOffersTheRightAction() {
        #expect(UpdatePolicy.menuEntry(for: .idle).action == .check)
        #expect(UpdatePolicy.menuEntry(for: .upToDate).action == .check)
        #expect(UpdatePolicy.menuEntry(for: .checking).action == nil)
        #expect(UpdatePolicy.menuEntry(for: .downloading(v("0.0.3"))) ==
            UpdateMenuEntry(status: "Downloading AulaWheel 0.0.3…"))
        #expect(UpdatePolicy.menuEntry(for: .ready(v("0.0.3"))) ==
            UpdateMenuEntry(actionTitle: "Restart to Update to 0.0.3", action: .restartToUpdate))
        let manual = UpdatePolicy.menuEntry(for: .manualOnly(v("0.0.3"), reason: "Move AulaWheel to Applications"))
        #expect(manual.status == "Move AulaWheel to Applications")
        #expect(manual.action == .openReleasePage)
        let failed = UpdatePolicy.menuEntry(for: .failed("offline"))
        #expect(failed.status == "Update failed: offline")
        #expect(failed.action == .check)
    }
}
