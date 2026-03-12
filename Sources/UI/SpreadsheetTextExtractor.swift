import Foundation

enum SpreadsheetTextExtractor {
    static func extractText(fromXLSX fileURL: URL, maxCharacters: Int) -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let workbookData = unzipEntry("xl/workbook.xml", from: fileURL)
        let relationshipsData = unzipEntry("xl/_rels/workbook.xml.rels", from: fileURL)
        let sharedStrings = unzipEntry("xl/sharedStrings.xml", from: fileURL)
            .flatMap(SharedStringsParser.parse(from:)) ?? []

        let sheetEntries: [(name: String, path: String)]
        if let workbookData, let relationshipsData {
            let sheets = WorkbookParser.parse(from: workbookData)
            let relationships = RelationshipsParser.parse(from: relationshipsData)

            sheetEntries = sheets.compactMap { sheet in
                guard let target = relationships[sheet.relationshipID] else { return nil }
                return (name: sheet.name, path: normalizeWorksheetPath(target))
            }
        } else {
            sheetEntries = listWorksheetEntries(in: fileURL).enumerated().map { index, entry in
                let fallbackName = "Sheet \(index + 1)"
                return (name: fallbackName, path: entry)
            }
        }

        guard !sheetEntries.isEmpty else { return nil }

        var sections: [String] = []
        sections.reserveCapacity(sheetEntries.count)
        var remaining = maxCharacters

        for sheet in sheetEntries {
            guard remaining > 0,
                  let worksheetData = unzipEntry(sheet.path, from: fileURL),
                  let sheetText = WorksheetParser.parse(
                    from: worksheetData,
                    sharedStrings: sharedStrings,
                    sheetName: sheet.name,
                    maxCharacters: remaining
                  ),
                  !sheetText.isEmpty else {
                continue
            }

            sections.append(sheetText)
            remaining = max(0, maxCharacters - sections.joined(separator: "\n\n").count)
        }

        guard !sections.isEmpty else { return nil }

        var output = sections.joined(separator: "\n\n")
        if output.count > maxCharacters {
            output = String(output.prefix(maxCharacters))
            output.append("\n\n[Truncated]")
        }
        return output
    }

    private static func listWorksheetEntries(in fileURL: URL) -> [String] {
        guard let output = runProcess(
            executablePath: "/usr/bin/unzip",
            arguments: ["-Z1", fileURL.path]
        ) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()
    }

    private static func unzipEntry(_ entryPath: String, from fileURL: URL) -> Data? {
        runProcessData(
            executablePath: "/usr/bin/unzip",
            arguments: ["-p", fileURL.path, entryPath]
        )
    }

    private static func runProcess(executablePath: String, arguments: [String]) -> String? {
        guard let data = runProcessData(executablePath: executablePath, arguments: arguments) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func runProcessData(executablePath: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var stdoutData = Data()
        var stderrData = Data()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutData.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrData.append(handle.availableData)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            return nil
        }

        return stdoutData.isEmpty ? nil : stdoutData
    }

    private static func normalizeWorksheetPath(_ target: String) -> String {
        if target.hasPrefix("xl/") {
            return target
        }
        if target.hasPrefix("/") {
            return String(target.dropFirst())
        }
        return "xl/\(target)"
    }
}

private struct XLSXWorkbookSheet {
    let name: String
    let relationshipID: String
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentString = ""
    private var currentText = ""
    private var inSharedItem = false
    private var inTextNode = false

    static func parse(from data: Data) -> [String] {
        let parser = SharedStringsParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return [] }
        return parser.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si":
            inSharedItem = true
            currentString = ""
        case "t":
            if inSharedItem {
                inTextNode = true
                currentText = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTextNode {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "t":
            if inTextNode {
                currentString += currentText
                currentText = ""
                inTextNode = false
            }
        case "si":
            strings.append(currentString)
            currentString = ""
            inSharedItem = false
        default:
            break
        }
    }
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    private var sheets: [XLSXWorkbookSheet] = []

    static func parse(from data: Data) -> [XLSXWorkbookSheet] {
        let parser = WorkbookParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return [] }
        return parser.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "sheet",
              let name = attributeDict["name"],
              let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] else {
            return
        }

        sheets.append(XLSXWorkbookSheet(name: name, relationshipID: relationshipID))
    }
}

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var relationships: [String: String] = [:]

    static func parse(from data: Data) -> [String: String] {
        let parser = RelationshipsParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return [:] }
        return parser.relationships
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship",
              let id = attributeDict["Id"],
              let target = attributeDict["Target"] else {
            return
        }

        relationships[id] = target
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let sheetName: String
    private let maxCharacters: Int

    private var rows: [String] = []
    private var currentRow: [Int: String] = [:]
    private var currentMaxColumn = -1

    private var currentCellColumn = -1
    private var currentCellType: String?
    private var currentValue = ""
    private var currentInlineText = ""
    private var inValueNode = false
    private var inInlineTextNode = false
    private var reachedLimit = false

    static func parse(from data: Data, sharedStrings: [String], sheetName: String, maxCharacters: Int) -> String? {
        let parser = WorksheetParser(sharedStrings: sharedStrings, sheetName: sheetName, maxCharacters: maxCharacters)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        let parsed = xmlParser.parse()
        guard (parsed || parser.reachedLimit), !parser.rows.isEmpty else { return nil }

        var output = "Sheet: \(sheetName)\n" + parser.rows.joined(separator: "\n")
        if output.count > maxCharacters {
            output = String(output.prefix(maxCharacters))
            output.append("\n[Truncated]")
        }
        return output
    }

    init(sharedStrings: [String], sheetName: String, maxCharacters: Int) {
        self.sharedStrings = sharedStrings
        self.sheetName = sheetName
        self.maxCharacters = maxCharacters
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = [:]
            currentMaxColumn = -1
        case "c":
            currentCellColumn = columnIndex(from: attributeDict["r"])
            currentCellType = attributeDict["t"]
            currentValue = ""
            currentInlineText = ""
        case "v":
            inValueNode = true
            currentValue = ""
        case "t":
            inInlineTextNode = true
            currentInlineText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValueNode {
            currentValue += string
        }
        if inInlineTextNode {
            currentInlineText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v":
            inValueNode = false
        case "t":
            inInlineTextNode = false
        case "c":
            let resolved = resolveCurrentCellValue()
            if !resolved.isEmpty, currentCellColumn >= 0 {
                currentRow[currentCellColumn] = resolved
                currentMaxColumn = max(currentMaxColumn, currentCellColumn)
            }
            currentCellColumn = -1
            currentCellType = nil
        case "row":
            guard currentMaxColumn >= 0 else { return }

            let line = (0...currentMaxColumn)
                .map { currentRow[$0] ?? "" }
                .joined(separator: "\t")

            guard line.contains(where: { !$0.isWhitespace }) else { return }

            rows.append(line)

            let currentLength = rows.joined(separator: "\n").count + sheetName.count + 8
            if currentLength >= maxCharacters {
                reachedLimit = true
                parser.abortParsing()
            }
        default:
            break
        }
    }

    private func resolveCurrentCellValue() -> String {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let inline = currentInlineText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch currentCellType {
        case "s":
            guard let index = Int(value), sharedStrings.indices.contains(index) else {
                return value
            }
            return sharedStrings[index]
        case "inlineStr":
            return inline
        case "b":
            return value == "1" ? "TRUE" : "FALSE"
        default:
            return !inline.isEmpty ? inline : value
        }
    }

    private func columnIndex(from cellReference: String?) -> Int {
        guard let cellReference else { return -1 }
        let letters = cellReference.prefix { $0.isLetter }.uppercased()
        guard !letters.isEmpty else { return -1 }

        var index = 0
        for scalar in letters.unicodeScalars {
            let value = scalar.value
            guard value >= 65, value <= 90 else { continue }
            index = index * 26 + Int(value - 64)
        }
        return max(0, index - 1)
    }
}
