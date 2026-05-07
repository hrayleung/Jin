import Foundation

extension ChatAuxiliaryControlSupport {
    static func builtinSearchIncludeRawValue(controls: GenerationControls) -> Bool {
        controls.searchPlugin?.includeRawContent ?? false
    }

    static func builtinSearchFetchPageValue(
        controls: GenerationControls,
        settings: WebSearchPluginSettings
    ) -> Bool {
        controls.searchPlugin?.fetchPageContent ?? settings.jinaReadPages
    }

    static func builtinSearchFirecrawlExtractValue(
        controls: GenerationControls,
        settings: WebSearchPluginSettings
    ) -> Bool {
        controls.searchPlugin?.firecrawlExtractContent ?? settings.firecrawlExtractContent
    }

    static func builtinSearchMaxResultsValue(
        controls: GenerationControls,
        settings: WebSearchPluginSettings
    ) -> Int {
        controls.searchPlugin?.maxResults ?? settings.defaultMaxResults
    }

    static func builtinSearchRecencyDaysValue(controls: GenerationControls) -> Int? {
        controls.searchPlugin?.recencyDays
    }

    static func setBuiltinSearchIncludeRaw(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.includeRawContent = isEnabled ? true : nil
        }
    }

    static func setBuiltinSearchFetchPage(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.fetchPageContent = isEnabled
        }
    }

    static func setBuiltinSearchFirecrawlExtract(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.firecrawlExtractContent = isEnabled
        }
    }

    static func setSearchEnginePreference(
        useJinSearch: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.preferJinSearch = useJinSearch
        }
    }

    static func setSearchPluginProvider(
        _ provider: SearchPluginProvider,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.provider = provider
        }
    }

    static func setSearchPluginMaxResults(
        _ maxResults: Int,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.maxResults = maxResults
        }
    }

    static func setSearchPluginRecencyDays(
        _ recencyDays: Int?,
        controls: GenerationControls
    ) -> GenerationControls {
        updateSearchPluginControls(controls: controls) { searchPlugin in
            searchPlugin.recencyDays = recencyDays
        }
    }
}
