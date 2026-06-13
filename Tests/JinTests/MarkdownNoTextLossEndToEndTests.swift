import Foundation
import Markdown
import XCTest
@testable import Jin

/// Tier-2 cornerstone: for every corpus document, the repaired + preprocessed
/// document must parse to the same visible content as the raw document —
/// no letters, digits, CJK, or ordinary punctuation may be lost, and no
/// heading may be swallowed into another block kind.
final class MarkdownNoTextLossEndToEndTests: XCTestCase {
    /// Mirrors `NativeMarkdownCache.compute`'s `Document(parsing:options:)`.
    /// Keep in sync with the production parse options.
    private static let productionParseOptions: ParseOptions = [.parseSymbolLinks]

    // MARK: - Assertion core

    private func assertNoLoss(
        _ entry: MarkdownTextLossCorpus.Entry,
        isStreaming: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prepared = MarkdownRenderPreparation.prepareForRender(entry.text, isStreaming: isStreaming).text
        let preprocessed = MarkdownExtensionPreprocessor.preprocess(prepared)

        let referenceDocument = Document(parsing: entry.text)
        let actualDocument = Document(parsing: preprocessed, options: Self.productionParseOptions)

        let reference = MarkdownTextLossAudit.textOnlyWalk(referenceDocument)
        let actual = MarkdownTextLossAudit.textOnlyWalk(actualDocument)

        if let violation = MarkdownTextLossAudit.compareContentSkeletons(reference: reference, actual: actual) {
            XCTFail(
                "[\(entry.name)] streaming=\(isStreaming) content loss:\n\(violation)",
                file: file,
                line: line
            )
        }

        if let violation = MarkdownTextLossAudit.auditHeadingsPreserved(
            referenceDocument: referenceDocument,
            actualDocument: actualDocument
        ) {
            XCTFail(
                "[\(entry.name)] streaming=\(isStreaming) heading swallowed:\n\(violation)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Full-document suites

    func testCorpusPreservesContentSkeletonFinal() {
        for entry in MarkdownTextLossCorpus.documents {
            assertNoLoss(entry, isStreaming: false)
        }
    }

    func testCorpusPreservesContentSkeletonStreaming() {
        for entry in MarkdownTextLossCorpus.documents {
            assertNoLoss(entry, isStreaming: true)
        }
    }

    func testPendingFixCorpusDocumentsStillReproduce() throws {
        // Inverted guard: these documents reproduce KNOWN swallowing bugs.
        // When a fix lands, its entry moves to `documents` and out of here —
        // if an entry stops failing without a corpus move, this test reminds
        // us to graduate it.
        try XCTSkipIf(
            MarkdownTextLossCorpus.pendingFixDocuments.isEmpty,
            "no pending-fix documents — all graduated"
        )
        for entry in MarkdownTextLossCorpus.pendingFixDocuments {
            let prepared = MarkdownRenderPreparation.prepareForRender(entry.text, isStreaming: false).text
            let preprocessed = MarkdownExtensionPreprocessor.preprocess(prepared)
            let referenceDocument = Document(parsing: entry.text)
            let actualDocument = Document(parsing: preprocessed, options: Self.productionParseOptions)
            let contentViolation = MarkdownTextLossAudit.compareContentSkeletons(
                reference: MarkdownTextLossAudit.textOnlyWalk(referenceDocument),
                actual: MarkdownTextLossAudit.textOnlyWalk(actualDocument)
            )
            let headingViolation = MarkdownTextLossAudit.auditHeadingsPreserved(
                referenceDocument: referenceDocument,
                actualDocument: actualDocument
            )
            XCTAssertTrue(
                contentViolation != nil || headingViolation != nil,
                "[\(entry.name)] no longer reproduces its bug — move it into MarkdownTextLossCorpus.documents"
            )
        }
    }

    // MARK: - Streaming prefix property suite

    func testEveryCorpusPrefixIsLossFreeWhileStreaming() {
        for entry in MarkdownTextLossCorpus.documents {
            for length in MarkdownTextLossAudit.prefixSampleLengths(for: entry.text) {
                let prefixEntry = MarkdownTextLossCorpus.Entry(
                    name: "\(entry.name)#prefix\(length)",
                    text: MarkdownTextLossAudit.prefix(entry.text, length: length)
                )
                assertNoLoss(prefixEntry, isStreaming: true)
            }
        }
    }
}
