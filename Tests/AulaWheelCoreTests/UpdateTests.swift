import Foundation
import Testing
@testable import AulaWheelCore

@Suite struct UpdateTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func v(_ string: String) -> AppVersion { AppVersion(string)! }

    func release(
        _ tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String]? = nil,
        size: Int = 1000, digest: String? = nil, scheme: String = "https"
    ) -> GitHubRelease {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let names = assets ?? ["AulaWheel-\(version).dmg", "AulaWheel-\(version).zip"]
        return GitHubRelease(
            tagName: tag, draft: draft, prerelease: prerelease,
            htmlURL: URL(string: "https://github.com/o/r/releases/tag/\(tag)"),
            assets: names.map {
                .init(name: $0, size: size, digest: digest,
                      browserDownloadURL: URL(string: "\(scheme)://github.com/o/r/releases/download/\(tag)/\($0)")!)
            })
    }

    func update(_ release: GitHubRelease, current: String = "0.0.2") -> AvailableUpdate? {
        UpdatePolicy.update(from: release, current: v(current))
    }

    @Test func versionMayStartWithVOrSpaces() {
        #expect(AppVersion("v1.2.3") == AppVersion("1.2.3"))
        #expect(AppVersion("V1.2.3") == AppVersion("1.2.3"))
        #expect(AppVersion(" 1.2.3 ") == AppVersion("1.2.3"))
        #expect(AppVersion("v1.2.3")?.description == "1.2.3")
    }

    @Test func trailingZerosDoNotMakeANewVersion() {
        #expect(v("1.0") == v("1.0.0"))
        #expect(!(v("1.0") < v("1.0.0")))
        #expect(Set([v("1.0"), v("1.0.0")]).count == 1)
    }

    @Test func versionWithAnythingButOneToFourNumbersIsRejected() {
        #expect(AppVersion("1.2.3.4") != nil)
        for bad in ["", "v", "1.0-beta", "1..2", "1.2.", "a.b", "1.2.3.4.5", " ", "-1", "1.+2", "１.２", "1234567890"] {
            #expect(AppVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func versionsCompareNumerically() {
        #expect(v("0.0.10") > v("0.0.9"))
        #expect(v("0.1") > v("0.0.99"))
        #expect(v("1.0.1") > v("1.0"))
        #expect(v("2") > v("1.9.9"))
    }

    @Test func newerReleaseOffersItsZip() throws {
        let found = try #require(update(release("v0.0.3")))
        #expect(found.version == v("0.0.3"))
        #expect(found.downloadURL.lastPathComponent == "AulaWheel-0.0.3.zip")
        #expect(found.size == 1000)
        #expect(found.releasePage?.absoluteString == "https://github.com/o/r/releases/tag/v0.0.3")
    }

    @Test func sameOrOlderReleaseIsNotAnUpdate() {
        #expect(update(release("v0.0.2")) == nil)
        #expect(update(release("v0.0.1")) == nil)
        #expect(update(release("v0.0.2.0")) == nil)
    }

    @Test func draftsPrereleasesAndOddTagsAreNotUpdates() {
        #expect(update(release("v0.1.0", draft: true)) == nil)
        #expect(update(release("v0.1.0", prerelease: true)) == nil)
        #expect(update(release("v0.1.0-rc1")) == nil)
    }

    @Test func releaseNeedsANonEmptyZipNamedForItsVersion() {
        #expect(update(release("v0.1.0", assets: ["AulaWheel-0.1.0.dmg"])) == nil)
        #expect(update(release("v0.1.0", assets: ["AulaWheel-0.0.9.zip"])) == nil)
        #expect(update(release("v0.1.0", assets: ["Other-0.1.0.zip"])) == nil)
        #expect(update(release("v0.1.0", size: 0)) == nil)
    }

    @Test func plainHTTPDownloadIsRefused() {
        #expect(update(release("v0.1.0", scheme: "http")) == nil)
    }

    @Test func onlyAWellFormedSHA256DigestIsKept() {
        let hex = String(repeating: "ab", count: 32)
        #expect(update(release("v1", digest: "sha256:\(hex.uppercased())"))?.sha256 == hex)
        #expect(update(release("v1", digest: "sha512:\(hex)"))?.sha256 == nil)
        #expect(update(release("v1", digest: "sha256:abc"))?.sha256 == nil)
        #expect(update(release("v1", digest: "sha256:\(String(repeating: "zz", count: 32))"))?.sha256 == nil)
        #expect(update(release("v1"))?.sha256 == nil)
    }

    @Test func gitHubReleaseJSONDecodes() throws {
        let json = """
        {"tag_name":"v0.0.3","draft":false,"prerelease":false,"name":"AulaWheel 0.0.3",
         "html_url":"https://github.com/o/r/releases/tag/v0.0.3",
         "assets":[{"name":"AulaWheel-0.0.3.zip","size":684696,"digest":null,"content_type":"application/zip",
                    "browser_download_url":"https://github.com/o/r/releases/download/v0.0.3/AulaWheel-0.0.3.zip"}]}
        """
        let decoded = try GitHubRelease.decode(Data(json.utf8))
        #expect(decoded.tagName == "v0.0.3")
        #expect(decoded.assets.first?.digest == nil)
        #expect(update(decoded)?.size == 684696)
    }

    @Test func checkIsDueWhenNeverCheckedOrADayHasPassed() {
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: nil))
        #expect(!UpdatePolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(-3600)))
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(-UpdatePolicy.checkInterval)))
    }

    @Test func failedCheckWaitsAnHourBeforeRetrying() {
        let twoDaysAgo = now.addingTimeInterval(-2 * UpdatePolicy.checkInterval)
        #expect(!UpdatePolicy.isCheckDue(now: now, lastCheck: twoDaysAgo, lastAttempt: now.addingTimeInterval(-60)))
        #expect(!UpdatePolicy.isCheckDue(now: now, lastCheck: nil, lastAttempt: now.addingTimeInterval(-60)))
        #expect(UpdatePolicy.isCheckDue(
            now: now, lastCheck: twoDaysAgo, lastAttempt: now.addingTimeInterval(-UpdatePolicy.retryInterval)))
    }

    @Test func clockGoingBackwardsMakesACheckDue() {
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: now.addingTimeInterval(3600)))
        #expect(UpdatePolicy.isCheckDue(now: now, lastCheck: nil, lastAttempt: now.addingTimeInterval(60)))
    }

    @Test func sameOrOlderStagedVersionIsNeverInstalled() {
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

    @Test func menuShowsEachPhase() {
        let check = UpdateMenuEntry(actionTitle: "Check for Updates", action: .check)
        #expect(UpdatePolicy.menuEntry(for: .idle) == check)
        #expect(UpdatePolicy.menuEntry(for: .upToDate) == check)
        #expect(UpdatePolicy.menuEntry(for: .checking) == UpdateMenuEntry(status: "Checking for updates…"))
        #expect(UpdatePolicy.menuEntry(for: .downloading(v("0.0.3"))) ==
            UpdateMenuEntry(status: "Downloading AulaWheel 0.0.3…"))
        #expect(UpdatePolicy.menuEntry(for: .ready(v("0.0.3"))) ==
            UpdateMenuEntry(actionTitle: "Restart to Update to 0.0.3", action: .restartToUpdate))
        #expect(UpdatePolicy.menuEntry(for: .manualOnly(v("0.0.3"), reason: "Move AulaWheel to Applications")) ==
            UpdateMenuEntry(status: "Move AulaWheel to Applications", actionTitle: "Download AulaWheel 0.0.3…",
                            action: .openReleasePage))
        #expect(UpdatePolicy.menuEntry(for: .failed("offline")) ==
            UpdateMenuEntry(status: "Update failed: offline", actionTitle: "Check for Updates", action: .check))
    }
}
