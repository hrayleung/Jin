import XCTest
@testable import Jin

final class CloudflareR2ConfigurationSupportTests: XCTestCase {
    func testInitializerTrimsStoredFieldsAndNormalizesPrefix() {
        let configuration = CloudflareR2Configuration(
            accountID: " account ",
            accessKeyID: " access ",
            secretAccessKey: " secret ",
            bucket: " bucket ",
            publicBaseURL: " https://cdn.example.com/base/ ",
            keyPrefix: "/ uploads /"
        )

        XCTAssertEqual(configuration.accountID, "account")
        XCTAssertEqual(configuration.accessKeyID, "access")
        XCTAssertEqual(configuration.secretAccessKey, "secret")
        XCTAssertEqual(configuration.bucket, "bucket")
        XCTAssertEqual(configuration.publicBaseURL, "https://cdn.example.com/base/")
        XCTAssertEqual(configuration.normalizedKeyPrefix, " uploads ")
        XCTAssertEqual(configuration.uploadHost, "account.r2.cloudflarestorage.com")
    }

    func testMissingRequiredFieldsListsEmptyRequiredValues() {
        let configuration = CloudflareR2Configuration(
            accountID: "",
            accessKeyID: "access",
            secretAccessKey: "",
            bucket: "",
            publicBaseURL: "",
            keyPrefix: "optional"
        )

        XCTAssertEqual(
            configuration.missingRequiredFields,
            ["Account ID", "Secret Access Key", "Bucket", "Public Base URL"]
        )
    }

    func testValidatedRejectsPublicBaseURLWithQueryOrFragment() {
        let withQuery = makeConfiguration(publicBaseURL: "https://cdn.example.com/base?token=1")
        XCTAssertThrowsError(try withQuery.validated()) { error in
            guard case CloudflareR2UploaderError.invalidPublicBaseURL("https://cdn.example.com/base?token=1") = error else {
                XCTFail("Expected invalidPublicBaseURL, got \(error)")
                return
            }
        }

        let withFragment = makeConfiguration(publicBaseURL: "https://cdn.example.com/base#frag")
        XCTAssertThrowsError(try withFragment.validated()) { error in
            guard case CloudflareR2UploaderError.invalidPublicBaseURL("https://cdn.example.com/base#frag") = error else {
                XCTFail("Expected invalidPublicBaseURL, got \(error)")
                return
            }
        }
    }

    func testPublicURLEncodesObjectKeyAndPreservesBasePath() throws {
        let configuration = makeConfiguration(publicBaseURL: "https://cdn.example.com/base/path/")

        let publicURL = try configuration.publicURL(for: "docs/hello world+plus.pdf")

        XCTAssertEqual(
            publicURL.absoluteString,
            "https://cdn.example.com/base/path/docs/hello%20world%2Bplus.pdf"
        )
    }

    func testObjectKeyDecodesURLUnderConfiguredBasePath() throws {
        let configuration = makeConfiguration(publicBaseURL: "https://cdn.example.com/base/path")
        let publicURL = try XCTUnwrap(URL(string: "https://cdn.example.com/base/path/docs/hello%20world%2Bplus.pdf"))

        XCTAssertEqual(
            try configuration.objectKey(for: publicURL),
            "docs/hello world+plus.pdf"
        )
    }

    func testObjectKeyRejectsURLOutsideConfiguredBasePath() throws {
        let configuration = makeConfiguration(publicBaseURL: "https://cdn.example.com/base/path")
        let publicURL = try XCTUnwrap(URL(string: "https://cdn.example.com/other/docs/file.pdf"))

        XCTAssertThrowsError(try configuration.objectKey(for: publicURL)) { error in
            guard case CloudflareR2UploaderError.publicURLValidationFailed(let message) = error else {
                XCTFail("Expected publicURLValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("base path"))
        }
    }

    private func makeConfiguration(publicBaseURL: String) -> CloudflareR2Configuration {
        CloudflareR2Configuration(
            accountID: "account",
            accessKeyID: "access",
            secretAccessKey: "secret",
            bucket: "bucket",
            publicBaseURL: publicBaseURL,
            keyPrefix: ""
        )
    }
}
