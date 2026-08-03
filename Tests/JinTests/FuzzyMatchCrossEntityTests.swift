import XCTest
@testable import Jin

/// Cross-entity model search: a query may name a provider *and* a model, and each
/// token may be satisfied by a different field of the same row.
///
/// The fixture mirrors real catalog data, including the shapes that used to break
/// search: aggregator IDs that embed a vendor (`openai/gpt-5.6-luna`), routing paths
/// (`accounts/fireworks/models/…`), a renamed provider, and a diacritic name.
final class FuzzyMatchCrossEntityTests: XCTestCase {
    // MARK: - The reported bug

    func testProviderAndModelTokensAreSatisfiedByDifferentFields() {
        let sections = search("opencode luna")

        XCTAssertEqual(sections.map(\.providerID), ["opencode-go"])
        XCTAssertEqual(sections.first?.models.map(\.id), ["gpt-5.6-luna"])
    }

    func testCrossEntityQueryIgnoresTokenOrderCaseAndPadding() {
        for query in ["luna opencode", "OPENCODE LUNA", "  opencode   luna  ", "opencode\nluna"] {
            let sections = search(query)
            XCTAssertEqual(sections.map(\.providerID), ["opencode-go"], "query: \(query)")
            XCTAssertEqual(sections.first?.models.map(\.id), ["gpt-5.6-luna"], "query: \(query)")
        }
    }

    func testProviderNameMayBeSplitAcrossTokens() {
        let sections = search("open code luna")

        XCTAssertEqual(sections.map(\.providerID), ["opencode-go"])
        XCTAssertEqual(sections.first?.models.map(\.id), ["gpt-5.6-luna"])
    }

    func testCrossEntityMatchesReachEveryProviderHostingTheModel() {
        XCTAssertEqual(search("databricks luna").map(\.providerID), ["databricks"])
        XCTAssertEqual(search("fireworks kimi").first?.models.map(\.id), ["accounts/fireworks/models/kimi-k3"])
        XCTAssertEqual(search("cafe llama").first?.models.map(\.id), ["llama-3"])
        // Every provider that ships a Luna model, and only those.
        XCTAssertEqual(
            Set(search("luna").map(\.providerID)),
            ["openai", "opencode-go", "openrouter", "databricks"]
        )
    }

    // MARK: - AND semantics still hold

    func testEveryTokenMustBeSatisfiedBySomeField() {
        // Each of these pairs a real provider with a model that provider does not host.
        for query in [
            "opencode banana",
            "opencode sonnet",
            "fireworks luna",
            "openai claude",
            "luna sol",
            "anthropic codex"
        ] {
            XCTAssertTrue(search(query).isEmpty, "expected no results for: \(query)")
        }
    }

    func testProviderOnlyQueryReturnsThatProvidersModelsInCatalogOrder() {
        XCTAssertEqual(
            search("opencode").first?.models.map(\.id),
            ["glm-5.2", "kimi-k3", "gpt-5.6-luna"]
        )
        // The camelCase enum raw value is searchable too.
        XCTAssertEqual(
            search("opencodego").first?.models.map(\.id),
            ["glm-5.2", "kimi-k3", "gpt-5.6-luna"]
        )
    }

    // MARK: - Ranking

    func testFirstPartyProviderOutranksGatewayClones() {
        XCTAssertEqual(
            search("openai luna").map(\.providerID),
            ["openai", "openrouter"]
        )
    }

    func testSectionsAreRankedByBestMatchWhenSearchingAndAlphabeticalWhenNot() {
        // "Vercel AI Gateway" sorts last alphabetically but wins on relevance.
        XCTAssertEqual(search("vercel").map(\.providerID), ["vercel-ai-gateway"])
        XCTAssertEqual(search("opus").map(\.providerID), ["anthropic"])

        XCTAssertEqual(
            search("").map(\.providerID),
            ["anthropic", "cafe-proxy", "databricks", "fireworks", "openai",
             "opencode-go", "openrouter", "vercel-ai-gateway", "claude-cjk"]
        )
    }

    func testIdentifierTailIsIndexedSeparatelyFromRoutingPrefixes() {
        // "kimi-k3" is an exact hit on the tail of "accounts/fireworks/models/kimi-k3".
        let sections = search("kimi-k3")

        XCTAssertEqual(Set(sections.map(\.providerID)), ["fireworks", "opencode-go"])
    }

    func testRankingIsDeterministicRegardlessOfInputOrder() {
        // Equal-scoring rows are broken by index, never left to `Array.sort`'s
        // unstable introsort — so shuffling the input cannot shuffle the output.
        for query in ["luna", "gpt", "kimi", "opencode"] {
            let forward = search(query).map { ($0.providerID, $0.models.map(\.id)) }
            let reversed = ModelPickerSupport.filteredSections(
                providers: Self.providers.reversed(),
                scope: .all,
                searchText: query,
                managedAgentProviderID: nil,
                isFavorite: { _, _ in false }
            ).map { ($0.providerID, $0.models.map(\.id)) }

            XCTAssertFalse(forward.isEmpty, "query: \(query)")
            XCTAssertEqual(forward.map(\.0), reversed.map(\.0), "query: \(query)")
            XCTAssertEqual(forward.map(\.1), reversed.map(\.1), "query: \(query)")
        }
    }

    // MARK: - False-positive guards

    func testSubsequenceTierRejectsMidWordAlignments() {
        // The canonical garbage: "codex" is a subsequence of
        // "accounts/fireworks/models/minimax-m2" but starts mid-word.
        let codex = search("codex").flatMap { $0.models.map(\.id) }
        XCTAssertEqual(codex, ["gpt-5.3-codex"])

        // "flux" is a subsequence of "Poolside: Laguna XS 2.1 (Free)".
        XCTAssertTrue(search("flux").isEmpty)

        for query in ["zzz", "xyzzy", "q9q9"] {
            XCTAssertTrue(search(query).isEmpty, "expected no results for: \(query)")
        }
    }

    func testSeparatorOnlyQueriesNeverMatchEverything() {
        XCTAssertTrue(FuzzyMatch.match(query: "-", target: "gpt-4o").matched)
        XCTAssertFalse(FuzzyMatch.match(query: "-", target: "gpt4o").matched)
        XCTAssertFalse(FuzzyMatch.match(query: "---", target: "gpt-4o").matched)
        XCTAssertFalse(FuzzyMatch.match(query: "---", target: "g-p-t-4-o").matched)
    }

    func testFieldsAreScoredSeparatelyRatherThanConcatenated() {
        // Joining a candidate's fields into one haystack would let a match straddle
        // the seam: "aigpt" spans the end of "OpenAI" and the start of "GPT".
        let candidate = FuzzyMatchCandidate(strings: ["OpenAI", "openai", "GPT 5", "gpt-5"])

        XCTAssertFalse(FuzzyMatch.score(FuzzyMatchQuery("aigpt"), candidate).matched)
    }

    // MARK: - Typos, acronyms, and glued queries

    func testGuardedSubsequenceTierAbsorbsTyposAndAcronyms() {
        XCTAssertEqual(search("sonet").first?.models.map(\.id), ["claude-sonnet-5"])
        XCTAssertEqual(search("anthrpic").first?.providerID, "anthropic")
        XCTAssertEqual(search("vaig").first?.providerID, "vercel-ai-gateway")
    }

    func testSpeculativeMatchesNeverOutrankLiteralOnes() {
        // "sonet" only matches by subsequence, so it must sit below every literal
        // hit — tier 7 adds rows at the bottom, it never reorders the top.
        let literal = FuzzyMatch.score(
            FuzzyMatchQuery("sonnet"),
            FuzzyMatchCandidate(strings: ["Claude Sonnet 5"])
        )
        let speculative = FuzzyMatch.score(
            FuzzyMatchQuery("sonet"),
            FuzzyMatchCandidate(strings: ["Claude Sonnet 5"])
        )

        XCTAssertTrue(literal.matched)
        XCTAssertTrue(speculative.matched)
        XCTAssertGreaterThan(literal.score, speculative.score)
    }

    func testNumericTokensAreMatchedExactlyRatherThanFuzzily() {
        // A digit run must line up with a whole digit run in the field: sizes are
        // exactly what a user is being precise about. Before this guard "30b"
        // subsequence-matched "Llama 3.3 70B" via the `3` of `3.3` and the `0` of
        // `70`, and "12b" matched "120B".
        let sizes = [
            Self.provider(id: "meta", name: "Meta", typeRaw: "meta", models: [
                Self.model(id: "llama-3.3-70b", name: "Llama 3.3 70B"),
                Self.model(id: "gpt-oss-120b", name: "GPT-OSS 120B"),
                Self.model(id: "gemma-3-12b", name: "Gemma 3 12B")
            ])
        ]
        func hits(_ query: String) -> [String] {
            ModelPickerSupport.filteredSections(
                providers: sizes, scope: .all, searchText: query,
                managedAgentProviderID: nil, isFavorite: { _, _ in false }
            ).flatMap { $0.models.map(\.id) }
        }

        XCTAssertEqual(hits("meta 30b"), [])
        XCTAssertEqual(hits("12b"), ["gemma-3-12b"])
        XCTAssertEqual(hits("70b"), ["llama-3.3-70b"])
        XCTAssertEqual(hits("120b"), ["gpt-oss-120b"])
    }

    func testRunsOfCapitalsDoNotManufactureAcronymMatches() {
        // Every letter of an all-caps word counts as a boundary, which is what let
        // "video" reach "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B".
        let nvidia = [
            Self.provider(id: "baseten", name: "Baseten", typeRaw: "baseten", models: [
                Self.model(id: "nvidia/NVIDIA-Nemotron-3-Ultra", name: "Nemotron 3 Ultra")
            ])
        ]

        XCTAssertTrue(
            ModelPickerSupport.filteredSections(
                providers: nvidia, scope: .all, searchText: "video",
                managedAgentProviderID: nil, isFavorite: { _, _ in false }
            ).isEmpty
        )
    }

    func testCohesionRewardsWholeQueryInOneFieldNotCoincidingArgmaxFields() {
        // Every model in a section shares the provider's fields. Keying cohesion on
        // the argmax would hand the bonus to exactly the models that matched
        // *nothing* of their own, inverting catalog order.
        let kimi = [
            Self.provider(id: "kimi", name: "Kimi for Coding", typeRaw: "openaiCompatible", models: [
                Self.model(id: "k3", name: "Kimi K3"),
                Self.model(id: "k27-code", name: "Kimi K2.7 Code"),
                Self.model(id: "k27-code-hs", name: "Kimi K2.7 Code HighSpeed")
            ])
        ]

        XCTAssertEqual(
            ModelPickerSupport.filteredSections(
                providers: kimi, scope: .all, searchText: "kimi for coding",
                managedAgentProviderID: nil, isFavorite: { _, _ in false }
            ).first?.models.map(\.id),
            ["k3", "k27-code", "k27-code-hs"]
        )
    }

    func testOverlongQueriesFailClosedRatherThanDroppingTokens() {
        let candidate = FuzzyMatchCandidate(strings: ["Alpha Beta Gamma Delta"])
        let words = ["alpha", "beta", "gamma", "delta"]
        let overlong = (Array(repeating: words, count: 5).flatMap { $0 } + ["zzznotpresent"])
            .joined(separator: " ")

        XCTAssertTrue(FuzzyMatchQuery(overlong).isOverCapacity)
        // Truncating instead would drop the bogus tail and report a match.
        XCTAssertFalse(FuzzyMatch.score(FuzzyMatchQuery(overlong), candidate).matched)
        XCTAssertFalse(
            FuzzyMatch.score(FuzzyMatchQuery("alpha beta zzznotpresent"), candidate).matched
        )
    }

    // MARK: - Normalization

    func testSeparatorCollapsingAndTokenizationReachHyphenatedIdentifiers() {
        XCTAssertEqual(search("gpt4").first?.models.map(\.id), ["gpt-4o"])
        XCTAssertEqual(search("gpt 5").first?.providerID, "openai")
    }

    func testFoldingHandlesFullwidthDiacriticsAndCJKWithoutOverreaching() {
        XCTAssertEqual(search("ＧＰＴ").first?.providerID, "openai")
        XCTAssertEqual(search("café").first?.providerID, "cafe-proxy")
        XCTAssertEqual(search("克劳德").map(\.providerID), ["claude-cjk"])
        // A CJK query that matches nothing must come back empty, not crash.
        XCTAssertTrue(search("中文").isEmpty)
    }

    func testNormalizationIsLengthPreservingForFoldingHazards() {
        for text in ["İstanbul", "ﬁle", "Ⅷ", "ＧＰＴ", "がガ", "가", "👍", "Café"] {
            let field = FuzzyMatchField(text)
            XCTAssertEqual(
                field.scalars.count,
                text.unicodeScalars.count,
                "normalization changed scalar count for: \(text)"
            )
            XCTAssertEqual(field.bonuses.count, field.scalars.count)
            XCTAssertEqual(field.isBoundary.count, field.scalars.count)
        }
    }

    // MARK: - Empty query

    func testEmptyQueryMatchesEverythingWithoutRanking() {
        let candidate = FuzzyMatchCandidate(strings: ["GPT-5.6 Luna"])

        XCTAssertEqual(FuzzyMatch.score(FuzzyMatchQuery(""), candidate), .neutral)
        XCTAssertEqual(FuzzyMatch.score(FuzzyMatchQuery("   \n "), candidate), .neutral)
    }

    // MARK: - Managed agents

    func testManagedAgentTokensSpanAgentIdentityAndItsModel() {
        let agents = [
            Self.agent(id: "build-agent", name: "Build Agent", modelID: "claude-sonnet-4-6", modelDisplayName: "Sonnet 4.6"),
            Self.agent(id: "review-agent", name: "Review Agent", modelID: "claude-opus-4-1", modelDisplayName: "Opus 4.1")
        ]

        XCTAssertEqual(
            ModelPickerSupport.filteredManagedAgents(agents, searchText: "build sonnet").map(\.id),
            ["build-agent"]
        )
        XCTAssertEqual(
            ModelPickerSupport.filteredManagedAgents(agents, searchText: "review opus").map(\.id),
            ["review-agent"]
        )
        XCTAssertTrue(
            ModelPickerSupport.filteredManagedAgents(agents, searchText: "build opus").isEmpty
        )
    }

    // MARK: - Provider settings model list

    func testProviderFormModelListFiltersFuzzilyWithoutReordering() {
        let models = [
            Self.model(id: "gpt-5-mini", name: "GPT 5 Mini"),
            Self.model(id: "claude-sonnet", name: "Claude Sonnet"),
            Self.model(id: "gemini-pro", name: "Gemini Pro")
        ]

        XCTAssertEqual(
            ProviderFormSupport.filteredModels(models, searchText: " \n ").map(\.id),
            ["gpt-5-mini", "claude-sonnet", "gemini-pro"]
        )
        XCTAssertEqual(ProviderFormSupport.filteredModels(models, searchText: "SONNET").map(\.id), ["claude-sonnet"])
        // Neither of these matched under the old raw `contains` filter.
        XCTAssertEqual(ProviderFormSupport.filteredModels(models, searchText: "gpt 5").map(\.id), ["gpt-5-mini"])
        XCTAssertEqual(ProviderFormSupport.filteredModels(models, searchText: "gpt5").map(\.id), ["gpt-5-mini"])
    }

    // MARK: - Fixture

    private func search(_ query: String) -> [ModelPickerSupport.ProviderSection] {
        ModelPickerSupport.filteredSections(
            providers: Self.providers,
            scope: .all,
            searchText: query,
            managedAgentProviderID: nil,
            isFavorite: { _, _ in false }
        )
    }

    private static let providers: [ModelPickerSupport.ProviderSnapshot] = [
        provider(id: "anthropic", name: "Anthropic", typeRaw: "anthropic", models: [
            model(id: "claude-opus-5", name: "Claude Opus 5"),
            model(id: "claude-sonnet-5", name: "Claude Sonnet 5")
        ]),
        provider(id: "cafe-proxy", name: "Café Proxy", typeRaw: "openaiCompatible", models: [
            model(id: "llama-3", name: "Llama 3")
        ]),
        provider(id: "databricks", name: "Databricks", typeRaw: "databricks", models: [
            model(id: "databricks-gpt-5-6-luna", name: "GPT-5.6 Luna")
        ]),
        provider(id: "fireworks", name: "Fireworks", typeRaw: "fireworks", models: [
            model(id: "accounts/fireworks/models/kimi-k3", name: "Kimi K3"),
            model(id: "accounts/fireworks/models/minimax-m2", name: "MiniMax M2")
        ]),
        provider(id: "openai", name: "OpenAI", typeRaw: "openai", models: [
            model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna"),
            model(id: "gpt-5.3-codex", name: "GPT-5.3 Codex"),
            model(id: "gpt-4o", name: "GPT-4o"),
            model(id: "gpt-5", name: "GPT-5")
        ]),
        provider(id: "opencode-go", name: "OpenCode Go", typeRaw: "opencodeGo", models: [
            model(id: "glm-5.2", name: "GLM-5.2"),
            model(id: "kimi-k3", name: "Kimi K3"),
            model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna")
        ]),
        provider(id: "openrouter", name: "OpenRouter", typeRaw: "openrouter", models: [
            model(id: "openai/gpt-5.6-luna", name: "OpenAI: GPT-5.6 Luna"),
            model(id: "poolside/laguna-xs-2.1:free", name: "Poolside: Laguna XS 2.1 (Free)")
        ]),
        provider(id: "vercel-ai-gateway", name: "Vercel AI Gateway", typeRaw: "vercelAIGateway", models: [
            model(id: "openai/gpt-5.6-sol", name: "GPT-5.6 Sol")
        ]),
        provider(id: "claude-cjk", name: "克劳德", typeRaw: "anthropic", models: [
            model(id: "claude-haiku-5", name: "Claude Haiku 5")
        ])
    ]

    private static func provider(
        id: String,
        name: String,
        typeRaw: String,
        models: [ModelInfo]
    ) -> ModelPickerSupport.ProviderSnapshot {
        ModelPickerSupport.ProviderSnapshot(
            id: id,
            name: name,
            typeRaw: typeRaw,
            isEnabled: true,
            selectableModels: models
        )
    }

    private static func model(id: String, name: String) -> ModelInfo {
        ModelInfo(id: id, name: name, contextWindow: 128_000)
    }

    private static func agent(
        id: String,
        name: String,
        modelID: String?,
        modelDisplayName: String?
    ) -> ClaudeManagedAgentDescriptor {
        ClaudeManagedAgentDescriptor(
            id: id,
            name: name,
            modelID: modelID,
            modelDisplayName: modelDisplayName
        )
    }
}
