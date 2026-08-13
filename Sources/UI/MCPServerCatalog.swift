import Foundation

enum MCPServerCatalogCategory: String, CaseIterable, Identifiable {
    case all
    case search
    case browser
    case docs
    case apps
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .search: return "Search"
        case .browser: return "Browser"
        case .docs: return "Docs"
        case .apps: return "Apps"
        case .local: return "Local"
        }
    }
}

enum MCPServerCatalogCredential: Equatable {
    case oauth(help: String)
    case bearerToken(title: String, help: String)
    case header(name: String, title: String, help: String)
    case environment(key: String, title: String, help: String)
    case pathArgument(title: String, help: String, placeholder: String)
}

struct MCPServerCatalogItem: Identifiable, Hashable {
    let preset: AddMCPServerPreset
    let title: String
    let summary: String
    let category: MCPServerCatalogCategory
    let iconID: String
    let symbolName: String?
    let transportBadge: String?
    let credential: MCPServerCatalogCredential?
    let note: String?
    let docsURL: URL?
    let searchTerms: [String]

    var id: AddMCPServerPreset { preset }

    func hash(into hasher: inout Hasher) {
        hasher.combine(preset)
    }

    static func == (lhs: MCPServerCatalogItem, rhs: MCPServerCatalogItem) -> Bool {
        lhs.preset == rhs.preset
    }
}

enum AddMCPServerPreset: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case importJSON = "Import JSON"
    case tinyfish = "TinyFish"
    case exaHTTP = "Exa (Native HTTP)"
    case tavily = "Tavily"
    case firecrawlLocal = "Firecrawl (Local via npx)"
    case exaLocal = "Exa (Local via npx)"
    case context7 = "Context7"
    case playwright = "Playwright"
    case github = "GitHub"
    case notion = "Notion"
    case linear = "Linear"
    case filesystem = "Filesystem"
    case memory = "Memory"
    case sequentialThinking = "Sequential Thinking"
    case fetch = "Fetch"

    var id: String { rawValue }

    var isBlankCanvas: Bool {
        self == .custom || self == .importJSON
    }
}

enum MCPServerCatalog {
    static let items: [MCPServerCatalogItem] = [
        item(
            .tinyfish,
            title: "TinyFish",
            summary: "Search, fetch, and automate the live web.",
            category: .browser,
            iconID: "tinyfish",
            badge: "HTTP",
            credential: .oauth(
                help: "TinyFish’s hosted MCP uses OAuth 2.1. Sign in with your TinyFish account."
            ),
            docs: "https://docs.tinyfish.ai/mcp-integration",
            terms: ["tinyfish", "agentql", "search", "fetch", "browser", "web"]
        ),
        item(
            .exaHTTP,
            title: "Exa",
            summary: "Neural search over the live internet.",
            category: .search,
            iconID: "exa",
            badge: "HTTP",
            docs: "https://docs.exa.ai",
            terms: ["exa", "search", "web"]
        ),
        item(
            .tavily,
            title: "Tavily",
            summary: "Agent-oriented web search and extraction.",
            category: .search,
            iconID: "tavily",
            badge: "HTTP",
            credential: .oauth(
                help: "Tavily’s hosted MCP supports browser sign-in. You can also switch to a Bearer API key."
            ),
            docs: "https://docs.tavily.com/documentation/mcp",
            terms: ["tavily", "search", "extract"]
        ),
        item(
            .context7,
            title: "Context7",
            summary: "Up-to-date library docs in the prompt.",
            category: .docs,
            iconID: "context7",
            badge: "HTTP",
            credential: .header(
                name: "CONTEXT7_API_KEY",
                title: "API key",
                help: "Sent as the CONTEXT7_API_KEY header. Get a key at context7.com/dashboard."
            ),
            docs: "https://github.com/upstash/context7",
            terms: ["context7", "upstash", "docs", "library"]
        ),
        item(
            .playwright,
            title: "Playwright",
            summary: "Drive a real browser from the conversation.",
            category: .browser,
            iconID: "playwright",
            badge: "Local",
            docs: "https://playwright.dev/docs/getting-started-mcp",
            terms: ["playwright", "browser", "automation"]
        ),
        item(
            .github,
            title: "GitHub",
            summary: "Repos, issues, pull requests, and GitHub APIs.",
            category: .apps,
            iconID: "github",
            badge: "HTTP",
            credential: .bearerToken(
                title: "Personal access token",
                help: "GitHub’s remote MCP for third-party apps uses a personal access token (Authorization: Bearer). Create one at github.com/settings/tokens. Browser OAuth only works for hosts that registered their own GitHub OAuth App."
            ),
            docs: "https://github.com/github/github-mcp-server",
            terms: ["github", "git", "repo", "pull request"]
        ),
        item(
            .notion,
            title: "Notion",
            summary: "Search and update your Notion workspace.",
            category: .apps,
            iconID: "notion",
            badge: "HTTP",
            credential: .oauth(
                help: "Notion MCP prefers browser sign-in. A Notion API token still works as Bearer."
            ),
            docs: "https://developers.notion.com/guides/mcp/get-started-with-mcp",
            terms: ["notion", "notes", "wiki"]
        ),
        item(
            .linear,
            title: "Linear",
            summary: "Find and update issues, projects, and comments.",
            category: .apps,
            iconID: "linear",
            badge: "HTTP",
            credential: .oauth(
                help: "Linear MCP prefers browser sign-in. A Linear API key still works as Bearer."
            ),
            docs: "https://linear.app/docs/mcp",
            terms: ["linear", "issues", "tickets"]
        ),
        item(
            .firecrawlLocal,
            title: "Firecrawl",
            summary: "Crawl and extract sites through a local server.",
            category: .browser,
            iconID: "firecrawl",
            badge: "Local",
            credential: .environment(
                key: "FIRECRAWL_API_KEY",
                title: "API key",
                help: "Required for Firecrawl to initialize. Stored as FIRECRAWL_API_KEY."
            ),
            terms: ["firecrawl", "crawl", "scrape"]
        ),
        item(
            .exaLocal,
            title: "Exa (Local)",
            summary: "Run Exa search locally via npx.",
            category: .search,
            iconID: "exa",
            badge: "Local",
            credential: .environment(
                key: "EXA_API_KEY",
                title: "API key",
                help: "Stored as EXA_API_KEY for the local Exa server."
            ),
            terms: ["exa", "local", "npx"]
        ),
        item(
            .filesystem,
            title: "Filesystem",
            summary: "Read and write files in a folder you choose.",
            category: .local,
            iconID: "mcp",
            symbolName: "folder",
            badge: "Local",
            credential: .pathArgument(
                title: "Allowed folder",
                help: "The MCP filesystem server can only access this folder.",
                placeholder: "/path/to/allowed/files"
            ),
            terms: ["filesystem", "files", "folder", "disk"]
        ),
        item(
            .memory,
            title: "Memory",
            summary: "Persistent knowledge-graph memory.",
            category: .local,
            iconID: "mcp",
            symbolName: "brain",
            badge: "Local",
            terms: ["memory", "knowledge graph"]
        ),
        item(
            .sequentialThinking,
            title: "Sequential Thinking",
            summary: "Step through a reasoning chain as a tool.",
            category: .local,
            iconID: "mcp",
            symbolName: "list.number",
            badge: "Local",
            terms: ["thinking", "reasoning", "sequential"]
        ),
        item(
            .fetch,
            title: "Fetch",
            summary: "Fetch web pages as LLM-friendly text.",
            category: .local,
            iconID: "mcp",
            symbolName: "arrow.down.circle",
            badge: "Local",
            terms: ["fetch", "http", "url"]
        )
    ]

    static func item(for preset: AddMCPServerPreset) -> MCPServerCatalogItem? {
        items.first { $0.preset == preset }
    }

    static func filtered(
        query: String,
        category: MCPServerCatalogCategory,
        from items: [MCPServerCatalogItem] = items
    ) -> [MCPServerCatalogItem] {
        let scoped = category == .all ? items : items.filter { $0.category == category }
        guard let needle = query.trimmedNonEmpty?.lowercased() else { return scoped }

        return scoped.filter { item in
            let haystack = ([item.title, item.summary, item.iconID] + item.searchTerms)
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(needle)
        }
    }

    private static func item(
        _ preset: AddMCPServerPreset,
        title: String,
        summary: String,
        category: MCPServerCatalogCategory,
        iconID: String,
        symbolName: String? = nil,
        badge: String?,
        credential: MCPServerCatalogCredential? = nil,
        note: String? = nil,
        docs: String? = nil,
        terms: [String]
    ) -> MCPServerCatalogItem {
        MCPServerCatalogItem(
            preset: preset,
            title: title,
            summary: summary,
            category: category,
            iconID: iconID,
            symbolName: symbolName,
            transportBadge: badge,
            credential: credential,
            note: note,
            docsURL: docs.flatMap(URL.init(string:)),
            searchTerms: terms
        )
    }
}
