import XCTest
import Foundation
@testable import Jin

final class GitHubUpdateCheckerTests: XCTestCase {
    func testUpdateVersionComparison() {
        XCTAssertNil(GitHubReleaseChecker.parseVersion(""))
        XCTAssertNil(GitHubReleaseChecker.parseVersion("abc"))
        XCTAssertNil(GitHubReleaseChecker.parseVersion("v-1.2.3"))

        let version12 = GitHubReleaseChecker.parseVersion("1.2")
        let version123 = GitHubReleaseChecker.parseVersion("1.2.3")
        let version130 = GitHubReleaseChecker.parseVersion("1.3.0")
        let version200 = GitHubReleaseChecker.parseVersion("2.0")
        let versionPrerelease = GitHubReleaseChecker.parseVersion("1.2.3-rc.1")
        let versionComplexPrerelease = GitHubReleaseChecker.parseVersion("1.2.3-rc-1-extra")
        let versionWithBuildMetadata = GitHubReleaseChecker.parseVersion("1.2.3+abc.5")

        XCTAssertNotNil(version12)
        XCTAssertNotNil(version123)
        XCTAssertNotNil(version130)
        XCTAssertNotNil(version200)
        XCTAssertNotNil(versionPrerelease)
        XCTAssertNotNil(versionComplexPrerelease)
        XCTAssertNotNil(versionWithBuildMetadata)

        XCTAssertTrue(version12! < version123!)
        XCTAssertTrue(version123! < version130!)
        XCTAssertTrue(version130! < version200!)
        XCTAssertTrue(versionPrerelease! < version123!)
        XCTAssertTrue(versionComplexPrerelease! < version200!)
        XCTAssertFalse(versionWithBuildMetadata! < version123!)
        XCTAssertFalse(version123! < versionWithBuildMetadata!)
    }

    func testUpdateVersionParsingPreservesSemVerStyleInput() {
        let version = GitHubReleaseChecker.parseVersion("v1.2.3")
        XCTAssertEqual(version?.original, "v1.2.3")

        let upperV = GitHubReleaseChecker.parseVersion("V2.0.1")
        XCTAssertNotNil(upperV)
        XCTAssertEqual(upperV?.original, "V2.0.1")
    }

    func testPickingZipAssetPrefersApplicationZipOverSourceCodeArchive() {
        let assets: [GitHubReleaseChecker.ReleasePayload.AssetPayload] = [
            .init(name: "Source code (zip)", browserDownloadURL: "https://example.com/Source-code.zip"),
            .init(name: "Jin-0.2.0.zip", browserDownloadURL: "https://example.com/Jin-0.2.0.zip"),
            .init(name: "notes.txt", browserDownloadURL: "https://example.com/notes.txt")
        ]

        let selected = GitHubReleaseChecker.pickZipAsset(from: assets, appNameHint: "Jin")
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.name, "Jin-0.2.0.zip")
    }

    func testPickingZipAssetFallsBackToFirstZipWhenNoAppSpecificMatch() {
        let assets: [GitHubReleaseChecker.ReleasePayload.AssetPayload] = [
            .init(name: "release-bundle.zip", browserDownloadURL: "https://example.com/release-bundle.zip"),
            .init(name: "readme.txt", browserDownloadURL: "https://example.com/readme.txt")
        ]

        let selected = GitHubReleaseChecker.pickZipAsset(from: assets, appNameHint: "Jin")
        XCTAssertEqual(selected?.name, "release-bundle.zip")
    }

    func testPickingZipAssetSkipsSourceCodeArchiveWhenOnlySourceZipExists() {
        let assets: [GitHubReleaseChecker.ReleasePayload.AssetPayload] = [
            .init(name: "Source code (zip)", browserDownloadURL: "https://example.com/Source-code.zip"),
            .init(name: "Jin-source-code.zip", browserDownloadURL: "https://example.com/Jin-source-code.zip")
        ]

        XCTAssertNil(GitHubReleaseChecker.pickZipAsset(from: assets, appNameHint: "Jin"))
    }

    func testSourceZipDetectionUsesAssetNameOnly() {
        let asset = GitHubReleaseChecker.ReleasePayload.AssetPayload(
            name: "Jin-0.2.0.zip",
            browserDownloadURL: "https://github.com/sourcecode-team/Jin/releases/download/v0.2.0/Jin-0.2.0.zip"
        )

        XCTAssertFalse(GitHubReleaseChecker.isSourceZip(asset))
    }

    func testResolveCurrentVersionPrefersBundleVersion() {
        let resolved = GitHubReleaseChecker.resolveCurrentVersion(
            bundleVersion: "0.1.0",
            currentInstalledVersion: "1.2.3"
        )

        XCTAssertEqual(resolved, "0.1.0")
    }

    func testResolveCurrentVersionFallsBackToStoredInstalledVersionWhenBundleMissing() {
        let resolved = GitHubReleaseChecker.resolveCurrentVersion(
            bundleVersion: nil,
            currentInstalledVersion: "1.2.3"
        )

        XCTAssertEqual(resolved, "1.2.3")
    }

    func testResolveCurrentVersionNormalizesLeadingVPrefix() {
        let resolved = GitHubReleaseChecker.resolveCurrentVersion(
            bundleVersion: "v1.0",
            currentInstalledVersion: nil
        )

        XCTAssertEqual(resolved, "1.0")
    }

    func testBuildResultReportsNoDownloadableAssetWhenNoAssets() {
        let payload = GitHubReleaseChecker.ReleasePayload(
            tagName: "1.0.0",
            name: "Jin 1.0.0",
            body: nil,
            htmlURL: nil,
            publishedAt: nil,
            prerelease: false,
            assets: []
        )

        XCTAssertThrowsError(try GitHubReleaseChecker.buildResult(from: payload, bundle: .main)) { error in
            guard let updateError = error as? GitHubUpdateCheckError,
                  case .noDownloadableZipAsset = updateError else {
                return XCTFail("Expected .noDownloadableZipAsset, got \(error)")
            }
        }
    }
}
