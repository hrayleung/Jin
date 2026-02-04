import XCTest
@testable import Jin

final class NPMRCUtilsTests: XCTestCase {
    func testParseAssignmentsLastValueWins() {
        let contents = """
        # comment
        registry=https://one.example
        registry=https://two.example
        """

        let assignments = NPMRCUtils.parseAssignments(from: contents)
        XCTAssertEqual(assignments["registry"], "https://two.example")
    }

    func testSafeEntriesToInheritSkipsCredentialsAndManagedKeys() {
        let contents = """
        registry=https://registry.npmmirror.com
        //registry.npmjs.org/:_authToken=SECRET
        _auth=SECRET
        token=SECRET
        username=me
        password=SECRET
        prefix=/tmp/npm-prefix
        cache=/tmp/npm-cache
        """

        let safe = NPMRCUtils.safeEntriesToInherit(from: contents)
        XCTAssertEqual(safe["registry"], "https://registry.npmmirror.com")
        XCTAssertNil(safe["//registry.npmjs.org/:_authToken"])
        XCTAssertNil(safe["_auth"])
        XCTAssertNil(safe["token"])
        XCTAssertNil(safe["username"])
        XCTAssertNil(safe["password"])
        XCTAssertNil(safe["prefix"])
        XCTAssertNil(safe["cache"])
    }

    func testSafeEntriesToInheritAllowsScopedRegistryAndProxySettings() {
        let contents = """
        @my-scope:registry=https://packages.example
        https-proxy=http://proxy.local:8080
        strict-ssl=false
        always-auth=true
        """

        let safe = NPMRCUtils.safeEntriesToInherit(from: contents)
        XCTAssertEqual(safe["@my-scope:registry"], "https://packages.example")
        XCTAssertEqual(safe["https-proxy"], "http://proxy.local:8080")
        XCTAssertEqual(safe["strict-ssl"], "false")
        XCTAssertNil(safe["always-auth"])
    }
}

