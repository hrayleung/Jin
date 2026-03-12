import Foundation
import XCTest
@testable import Jin

final class SpreadsheetTextExtractorTests: XCTestCase {
    func testExtractTextFromXLSXBuildsTabbedSheetPreview() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xlsxURL = try makeSampleXLSX(at: tempDir)
        let extracted = SpreadsheetTextExtractor.extractText(
            fromXLSX: xlsxURL,
            maxCharacters: AttachmentConstants.maxSpreadsheetExtractedCharacters
        )

        let text = try XCTUnwrap(extracted)
        XCTAssertTrue(text.contains("Sheet: Projects"))
        XCTAssertTrue(text.contains("项目\t学校"))
        XCTAssertTrue(text.contains("Tokyo Exchange\t东京大学"))
        XCTAssertTrue(text.contains("Kyoto Program\t京都大学"))
    }
}

private func makeSampleXLSX(at tempDir: URL) throws -> URL {
    let root = tempDir.appendingPathComponent("xlsx-src", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("xl/worksheets", isDirectory: true), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("xl/_rels", isDirectory: true), withIntermediateDirectories: true)

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Projects" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """.write(
        to: root.appendingPathComponent("xl/workbook.xml"),
        atomically: true,
        encoding: .utf8
    )

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    </Relationships>
    """.write(
        to: root.appendingPathComponent("xl/_rels/workbook.xml.rels"),
        atomically: true,
        encoding: .utf8
    )

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">
      <si><t>项目</t></si>
      <si><t>学校</t></si>
      <si><t>Tokyo Exchange</t></si>
      <si><t>Kyoto Program</t></si>
    </sst>
    """.write(
        to: root.appendingPathComponent("xl/sharedStrings.xml"),
        atomically: true,
        encoding: .utf8
    )

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetData>
        <row r="1">
          <c r="A1" t="s"><v>0</v></c>
          <c r="B1" t="s"><v>1</v></c>
        </row>
        <row r="2">
          <c r="A2" t="s"><v>2</v></c>
          <c r="B2" t="inlineStr"><is><t>东京大学</t></is></c>
        </row>
        <row r="3">
          <c r="A3" t="s"><v>3</v></c>
          <c r="B3" t="inlineStr"><is><t>京都大学</t></is></c>
        </row>
      </sheetData>
    </worksheet>
    """.write(
        to: root.appendingPathComponent("xl/worksheets/sheet1.xml"),
        atomically: true,
        encoding: .utf8
    )

    let xlsxURL = tempDir.appendingPathComponent("sample.xlsx")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = root
    process.arguments = ["-qr", xlsxURL.path, "."]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw NSError(domain: "SpreadsheetTextExtractorTests", code: Int(process.terminationStatus))
    }

    return xlsxURL
}
