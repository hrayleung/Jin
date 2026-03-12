import XCTest
@testable import Jin

final class AgentFileOperationsTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        let dir = NSTemporaryDirectory() + "AgentFileOpsTests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        tempDir = dir
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeTempFile(_ name: String, content: String) throws -> String {
        let path = (tempDir as NSString).appendingPathComponent(name)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - readFile

    func testReadFile() throws {
        let path = try writeTempFile("hello.txt", content: "line1\nline2\nline3\n")

        let output = try AgentFileOperations.readFile(
            path: path,
            offset: nil,
            limit: nil,
            workingDirectory: nil
        )

        XCTAssertTrue(output.contains("line1"))
        XCTAssertTrue(output.contains("line2"))
        XCTAssertTrue(output.contains("line3"))
    }

    func testReadFileContainsLineNumbers() throws {
        let path = try writeTempFile("numbered.txt", content: "alpha\nbeta\ngamma\n")

        let output = try AgentFileOperations.readFile(
            path: path,
            offset: nil,
            limit: nil,
            workingDirectory: nil
        )

        // Output should include line numbers (e.g., "1:" or "  1")
        XCTAssertTrue(output.contains("1"))
        XCTAssertTrue(output.contains("alpha"))
    }

    func testReadFileWithOffsetLimit() throws {
        let lines = (1...10).map { "line\($0)" }.joined(separator: "\n")
        let path = try writeTempFile("lines.txt", content: lines)

        let output = try AgentFileOperations.readFile(
            path: path,
            offset: 3,
            limit: 2,
            workingDirectory: nil
        )

        XCTAssertTrue(output.contains("line3"))
        XCTAssertTrue(output.contains("line4"))
        XCTAssertFalse(output.contains("line1"))
        XCTAssertFalse(output.contains("line5"))
    }

    func testReadFileNotFound() {
        XCTAssertThrowsError(
            try AgentFileOperations.readFile(
                path: tempDir + "/nonexistent.txt",
                offset: nil,
                limit: nil,
                workingDirectory: nil
            )
        )
    }

    // MARK: - writeFile

    func testWriteFile() throws {
        let path = (tempDir as NSString).appendingPathComponent("output.txt")

        let result = try AgentFileOperations.writeFile(
            path: path,
            content: "hello world",
            workingDirectory: nil
        )

        XCTAssertFalse(result.isEmpty)
        let written = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(written, "hello world")
    }

    func testWriteFileCreatesDirectories() throws {
        let path = (tempDir as NSString)
            .appendingPathComponent("nested/deep/dir/file.txt")

        let result = try AgentFileOperations.writeFile(
            path: path,
            content: "nested content",
            workingDirectory: nil
        )

        XCTAssertFalse(result.isEmpty)
        let written = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(written, "nested content")
    }

    // MARK: - editFile

    func testEditFile() throws {
        let path = try writeTempFile("editable.txt", content: "foo bar baz")

        let result = try AgentFileOperations.editFile(
            path: path,
            oldText: "bar",
            newText: "qux",
            workingDirectory: nil
        )

        XCTAssertFalse(result.isEmpty)
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(contents, "foo qux baz")
    }

    func testEditFileNotFound() throws {
        XCTAssertThrowsError(
            try AgentFileOperations.editFile(
                path: tempDir + "/missing.txt",
                oldText: "a",
                newText: "b",
                workingDirectory: nil
            )
        )
    }

    func testEditFileOldTextNotFound() throws {
        let path = try writeTempFile("noreplace.txt", content: "hello world")

        XCTAssertThrowsError(
            try AgentFileOperations.editFile(
                path: path,
                oldText: "nonexistent",
                newText: "replacement",
                workingDirectory: nil
            )
        )
    }

    func testEditFileAmbiguous() throws {
        let path = try writeTempFile("ambiguous.txt", content: "aaa bbb aaa ccc aaa")

        XCTAssertThrowsError(
            try AgentFileOperations.editFile(
                path: path,
                oldText: "aaa",
                newText: "xxx",
                workingDirectory: nil
            )
        )
    }

    // MARK: - globSearch

    func testGlobSearch() throws {
        _ = try writeTempFile("one.swift", content: "")
        _ = try writeTempFile("two.swift", content: "")
        _ = try writeTempFile("three.txt", content: "")

        let result = try AgentFileOperations.globSearch(
            pattern: "*.swift",
            directory: tempDir,
            workingDirectory: nil
        )

        XCTAssertTrue(result.contains("one.swift"))
        XCTAssertTrue(result.contains("two.swift"))
        XCTAssertFalse(result.contains("three.txt"))
    }

    func testGlobSearchNoMatches() throws {
        let result = try AgentFileOperations.globSearch(
            pattern: "*.nonexistent",
            directory: tempDir,
            workingDirectory: nil
        )

        // Should return empty or "no matches" message, not throw
        XCTAssertNotNil(result)
    }

    // MARK: - grepSearch

    func testGrepSearch() throws {
        _ = try writeTempFile("searchable.txt", content: "hello world\nfoo bar\nhello again")

        let result = try AgentFileOperations.grepSearch(
            pattern: "hello",
            path: tempDir,
            include: nil,
            workingDirectory: nil
        )

        XCTAssertTrue(result.contains("hello"))
    }

    func testGrepSearchWithIncludeFilter() throws {
        _ = try writeTempFile("match.swift", content: "let x = 42")
        _ = try writeTempFile("skip.txt", content: "let y = 99")

        let result = try AgentFileOperations.grepSearch(
            pattern: "let",
            path: tempDir,
            include: "*.swift",
            workingDirectory: nil
        )

        XCTAssertTrue(result.contains("match.swift"))
        XCTAssertFalse(result.contains("skip.txt"))
    }

    // MARK: - Relative path resolution

    func testRelativePathResolution() throws {
        _ = try writeTempFile("relative.txt", content: "resolved")

        let output = try AgentFileOperations.readFile(
            path: "relative.txt",
            offset: nil,
            limit: nil,
            workingDirectory: tempDir
        )

        XCTAssertTrue(output.contains("resolved"))
    }

    func testRelativePathWriteResolution() throws {
        let result = try AgentFileOperations.writeFile(
            path: "relative_out.txt",
            content: "written via relative",
            workingDirectory: tempDir
        )

        XCTAssertFalse(result.isEmpty)
        let fullPath = (tempDir as NSString).appendingPathComponent("relative_out.txt")
        let contents = try String(contentsOfFile: fullPath, encoding: .utf8)
        XCTAssertEqual(contents, "written via relative")
    }
}
