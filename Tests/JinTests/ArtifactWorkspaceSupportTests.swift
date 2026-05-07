import XCTest
@testable import Jin

final class ArtifactWorkspaceSupportTests: XCTestCase {
    func testDisplayModeTitlesMatchWorkspaceSegments() {
        XCTAssertEqual(ArtifactWorkspaceSupport.DisplayMode.preview.title, "Preview")
        XCTAssertEqual(ArtifactWorkspaceSupport.DisplayMode.code.title, "Code")
    }

    func testResolvedArtifactIDPrefersValidSelectionAndFallsBackToLatest() {
        let catalog = makeCatalog([
            artifact(id: "first", version: 1),
            artifact(id: "second", version: 1)
        ])

        XCTAssertEqual(
            ArtifactWorkspaceSupport.resolvedArtifactID(
                in: catalog,
                selectedArtifactID: "first"
            ),
            "first"
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.resolvedArtifactID(
                in: catalog,
                selectedArtifactID: "missing"
            ),
            "second"
        )
        XCTAssertNil(
            ArtifactWorkspaceSupport.resolvedArtifactID(
                in: .empty,
                selectedArtifactID: "missing"
            )
        )
    }

    func testSelectedArtifactUsesResolvedIDAndVersionFallback() {
        let catalog = makeCatalog([
            artifact(id: "demo", version: 1, content: "one"),
            artifact(id: "demo", version: 2, content: "two")
        ])

        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectedArtifact(
                in: catalog,
                selectedArtifactID: "demo",
                selectedArtifactVersion: 1
            )?.content,
            "one"
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectedArtifact(
                in: catalog,
                selectedArtifactID: "demo",
                selectedArtifactVersion: 99
            )?.content,
            "two"
        )
    }

    func testSelectionAfterArtifactChangeSelectsLatestVersionForNewArtifact() {
        let catalog = makeCatalog([
            artifact(id: "demo", version: 1),
            artifact(id: "demo", version: 2)
        ])

        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectionAfterArtifactChange(
                "demo",
                in: catalog
            ),
            .init(artifactID: "demo", version: 2)
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectionAfterArtifactChange(
                nil,
                in: catalog
            ),
            .init(artifactID: nil, version: nil)
        )
    }

    func testSelectionAfterSyncPreservesValidSelectionAndFallsBackToLatest() {
        let catalog = makeCatalog([
            artifact(id: "first", version: 1),
            artifact(id: "second", version: 1),
            artifact(id: "second", version: 2)
        ])

        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectionAfterSync(
                in: catalog,
                selectedArtifactID: "second",
                selectedArtifactVersion: 1
            ),
            .init(artifactID: "second", version: 1)
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectionAfterSync(
                in: catalog,
                selectedArtifactID: "missing",
                selectedArtifactVersion: 1
            ),
            .init(artifactID: "second", version: 2)
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.selectionAfterSync(
                in: .empty,
                selectedArtifactID: "missing",
                selectedArtifactVersion: 1
            ),
            .init(artifactID: nil, version: nil)
        )
    }

    func testLatestArtifactSelectionUsesLatestMessageArtifactAndCatalogVersion() {
        let catalog = makeCatalog([
            artifact(id: "first", version: 1),
            artifact(id: "demo", version: 1),
            artifact(id: "demo", version: 2)
        ])
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text("""
                <jinArtifact artifact_id="first" title="First" contentType="text/html">
                <p>First</p>
                </jinArtifact>
                """),
                .text("""
                <jinArtifact artifact_id="demo" title="Demo" contentType="text/html">
                <p>Demo</p>
                </jinArtifact>
                """)
            ],
            timestamp: Date()
        )

        XCTAssertEqual(
            ArtifactWorkspaceSupport.latestArtifactSelection(
                from: message,
                in: catalog
            ),
            .init(artifactID: "demo", version: 2)
        )
    }

    func testLatestArtifactSelectionPreservesUncatalogedArtifactID() {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [
                .text("""
                <jinArtifact artifact_id="draft" title="Draft" contentType="text/html">
                <p>Draft</p>
                </jinArtifact>
                """)
            ],
            timestamp: Date()
        )

        XCTAssertEqual(
            ArtifactWorkspaceSupport.latestArtifactSelection(
                from: message,
                in: .empty
            ),
            .init(artifactID: "draft", version: nil)
        )
    }

    func testLatestArtifactSelectionIgnoresMessagesWithoutArtifacts() {
        let message = Message(
            id: UUID(),
            role: .assistant,
            content: [.text("No artifact here")],
            timestamp: Date()
        )

        XCTAssertNil(
            ArtifactWorkspaceSupport.latestArtifactSelection(
                from: message,
                in: .empty
            )
        )
    }

    func testPickerVisibilityFollowsArtifactAndVersionCounts() {
        let singleArtifactCatalog = makeCatalog([
            artifact(id: "demo", version: 1),
            artifact(id: "demo", version: 2)
        ])
        let multiArtifactCatalog = makeCatalog([
            artifact(id: "first", version: 1),
            artifact(id: "second", version: 1)
        ])

        XCTAssertFalse(ArtifactWorkspaceSupport.showsArtifactPicker(in: singleArtifactCatalog))
        XCTAssertTrue(ArtifactWorkspaceSupport.showsArtifactPicker(in: multiArtifactCatalog))
        XCTAssertTrue(
            ArtifactWorkspaceSupport.showsVersionPicker(
                for: ArtifactWorkspaceSupport.availableVersions(
                    in: singleArtifactCatalog,
                    selectedArtifactID: "demo"
                )
            )
        )
        XCTAssertFalse(
            ArtifactWorkspaceSupport.showsVersionPicker(
                for: ArtifactWorkspaceSupport.availableVersions(
                    in: multiArtifactCatalog,
                    selectedArtifactID: "first"
                )
            )
        )
    }

    func testFilenameStemSanitizesInvalidCharactersAndIncludesVersionWhenVisible() {
        let named = artifact(id: "demo", version: 3, title: " Report/Final:Q1? ")
        let unnamed = artifact(id: "", version: 1, title: "   ")
        let fallbackNamed = artifact(id: "demo-id", version: 2, title: "   \n\t")
        let paddedIDFallback = artifact(id: " demo/id ", version: 4, title: "   \n\t")

        XCTAssertEqual(
            ArtifactWorkspaceSupport.filenameStem(
                for: named,
                showsVersionPicker: true
            ),
            "Report-Final-Q1--v3"
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.filenameStem(
                for: unnamed,
                showsVersionPicker: false
            ),
            "artifact"
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.filenameStem(
                for: fallbackNamed,
                showsVersionPicker: true
            ),
            "demo-id-v2"
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.filenameStem(
                for: paddedIDFallback,
                showsVersionPicker: true
            ),
            "demo-id-v4"
        )
    }

    func testHighlightedCodeMarkdownUsesLongerFenceThanContentBackticks() {
        let artifact = artifact(
            id: "demo",
            version: 1,
            contentType: .react,
            content: "const demo = ```value```"
        )

        XCTAssertEqual(
            ArtifactWorkspaceSupport.maximumBacktickRunLength(in: artifact.content),
            3
        )
        XCTAssertEqual(
            ArtifactWorkspaceSupport.highlightedCodeMarkdown(for: artifact),
            """
            ````tsx
            const demo = ```value```
            ````
            """
        )
    }

    private func makeCatalog(_ artifacts: [RenderedArtifactVersion]) -> ArtifactCatalog {
        var orderedIDs: [String] = []
        var versionsByID: [String: [RenderedArtifactVersion]] = [:]

        for artifact in artifacts {
            if versionsByID[artifact.artifactID] == nil {
                orderedIDs.append(artifact.artifactID)
            }
            versionsByID[artifact.artifactID, default: []].append(artifact)
        }

        return ArtifactCatalog(
            orderedArtifactIDs: orderedIDs,
            versionsByArtifactID: versionsByID
        )
    }

    private func artifact(
        id: String,
        version: Int,
        title: String = "Demo",
        contentType: ArtifactContentType = .html,
        content: String = "<div>Hello</div>"
    ) -> RenderedArtifactVersion {
        RenderedArtifactVersion(
            artifactID: id,
            version: version,
            title: title,
            contentType: contentType,
            content: content,
            sourceMessageID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceTimestamp: Date(timeIntervalSince1970: TimeInterval(version))
        )
    }
}
