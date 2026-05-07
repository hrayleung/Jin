import XCTest
@testable import Jin

final class CloudflareR2SigningSupportTests: XCTestCase {
    func testCanonicalURIEncodesBucketAndObjectKeyPathSegments() {
        XCTAssertEqual(
            R2Signing.canonicalURI(bucket: "test bucket", objectKey: "docs/hello world+plus.pdf"),
            "/test%20bucket/docs/hello%20world%2Bplus.pdf"
        )
    }

    func testSignedRequestBuildsDeterministicAWSV4Headers() throws {
        let configuration = CloudflareR2Configuration(
            accountID: "test-account",
            accessKeyID: "AKIDEXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            bucket: "test-bucket",
            publicBaseURL: "https://pub.example.com",
            keyPrefix: ""
        )

        let request = try CloudflareR2SignedRequestFactory.makeRequest(
            method: "put",
            configuration: configuration,
            objectKey: "docs/hello world.pdf",
            payloadData: Data("hello".utf8),
            contentType: "application/pdf",
            date: fixedUTCDate()
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://test-account.r2.cloudflarestorage.com/test-bucket/docs/hello%20world.pdf"
        )
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.httpBody, Data("hello".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/pdf")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-date"), "20240101T000000Z")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-amz-content-sha256"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20240101/auto/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=b3f8e9691bf43a2ee14cd54a5211f557f3854a6494cf6611270b4dd4cc284b88"
        )
    }

    func testSignedDeleteRequestOmitsEmptyBodyAndContentTypeHeader() throws {
        let configuration = CloudflareR2Configuration(
            accountID: "test-account",
            accessKeyID: "AKIDEXAMPLE",
            secretAccessKey: "secret",
            bucket: "test-bucket",
            publicBaseURL: "https://pub.example.com",
            keyPrefix: ""
        )

        let request = try CloudflareR2SignedRequestFactory.makeRequest(
            method: "DELETE",
            configuration: configuration,
            objectKey: "docs/remove.pdf",
            payloadData: Data(),
            contentType: nil,
            date: fixedUTCDate()
        )

        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "content-type"))
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Authorization")?.contains(
                "SignedHeaders=host;x-amz-content-sha256;x-amz-date"
            ) == true
        )
    }

    private func fixedUTCDate() -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return components.date!
    }
}
