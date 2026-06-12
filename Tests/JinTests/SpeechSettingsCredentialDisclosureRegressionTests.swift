import XCTest

final class SpeechSettingsCredentialDisclosureRegressionTests: XCTestCase {
    func testSpeechToTextSettingsLoadDoesNotFetchRemoteModels() throws {
        let source = try sourceFile("Sources/UI/SpeechToTextPluginSettingsView+Actions.swift")
        let body = try functionBody(named: "loadExistingKeyAndMaybeModels", in: source)

        XCTAssertFalse(body.contains("loadRemoteSpeechToTextModels"))
        XCTAssertFalse(body.contains("fetchRemoteSpeechToTextModels"))
        XCTAssertFalse(body.contains("listModels()"))
    }

    func testTextToSpeechSettingsLoadDoesNotFetchRemoteResources() throws {
        let source = try sourceFile("Sources/UI/TextToSpeechPluginSettingsView+Actions.swift")
        let body = try functionBody(named: "loadExistingKeyAndMaybeProviderResources", in: source)

        XCTAssertFalse(body.contains("loadRemoteTextToSpeechModels"))
        XCTAssertFalse(body.contains("loadElevenLabsVoicesAndModels"))
        XCTAssertFalse(body.contains("listModels()"))
        XCTAssertFalse(body.contains("listVoices()"))
    }

    func testExplicitConnectionTestsStillRefreshSpeechResources() throws {
        let speechToTextSource = try sourceFile("Sources/UI/SpeechToTextPluginSettingsView+Actions.swift")
        let textToSpeechSource = try sourceFile("Sources/UI/TextToSpeechPluginSettingsView+Connection.swift")

        XCTAssertTrue(speechToTextSource.contains("await loadRemoteSpeechToTextModels(updateStatus: false)"))
        XCTAssertTrue(textToSpeechSource.contains("await loadRemoteTextToSpeechModels(updateStatus: false)"))
        XCTAssertTrue(textToSpeechSource.contains("await loadElevenLabsVoicesAndModels(updateStatus: false)"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOfFile: relativePath, encoding: .utf8)
    }

    private func functionBody(named name: String, in source: String) throws -> Substring {
        guard let declaration = source.range(of: "func \(name)") else {
            throw SourceInspectionError.missingFunction(name)
        }
        guard let openingBrace = source[declaration.lowerBound...].firstIndex(of: "{") else {
            throw SourceInspectionError.missingOpeningBrace(name)
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[openingBrace...index]
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw SourceInspectionError.missingClosingBrace(name)
    }

    private enum SourceInspectionError: Error {
        case missingFunction(String)
        case missingOpeningBrace(String)
        case missingClosingBrace(String)
    }
}
