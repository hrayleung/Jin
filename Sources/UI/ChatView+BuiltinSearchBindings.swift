import SwiftUI

// MARK: - Built-In Search Bindings

extension ChatView {

    var builtinSearchIncludeRawBinding: Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.builtinSearchIncludeRawValue(controls: controls)
            },
            set: { newValue in
                controls = ChatAuxiliaryControlSupport.setBuiltinSearchIncludeRaw(
                    newValue,
                    controls: controls
                )
                persistControlsToConversation()
            }
        )
    }

    var builtinSearchFetchPageBinding: Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.builtinSearchFetchPageValue(
                    controls: controls,
                    settings: WebSearchPluginSettingsStore.load()
                )
            },
            set: { newValue in
                controls = ChatAuxiliaryControlSupport.setBuiltinSearchFetchPage(
                    newValue,
                    controls: controls
                )
                persistControlsToConversation()
            }
        )
    }

    var builtinSearchFirecrawlExtractBinding: Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.builtinSearchFirecrawlExtractValue(
                    controls: controls,
                    settings: WebSearchPluginSettingsStore.load()
                )
            },
            set: { newValue in
                controls = ChatAuxiliaryControlSupport.setBuiltinSearchFirecrawlExtract(
                    newValue,
                    controls: controls
                )
                persistControlsToConversation()
            }
        )
    }

    func webSearchSourceBinding(_ source: WebSearchSource) -> Binding<Bool> {
        Binding(
            get: {
                ChatAuxiliaryControlSupport.webSearchSourceIsSelected(
                    source,
                    controls: controls
                )
            },
            set: { isOn in
                controls = ChatAuxiliaryControlSupport.setWebSearchSource(
                    source,
                    isOn: isOn,
                    controls: controls
                )
                persistControlsToConversation()
            }
        )
    }

    var xaiImageUnderstandingBinding: Binding<Bool> {
        xaiWebSearchBoolBinding(
            get: { $0.enableImageUnderstanding == true },
            set: { $0.enableImageUnderstanding = $1 ? true : nil }
        )
    }

    var xaiImageSearchBinding: Binding<Bool> {
        xaiWebSearchBoolBinding(
            get: { $0.enableImageSearch == true },
            set: { $0.enableImageSearch = $1 ? true : nil }
        )
    }

    var xaiVideoUnderstandingBinding: Binding<Bool> {
        xaiWebSearchBoolBinding(
            get: { $0.enableVideoUnderstanding == true },
            set: { $0.enableVideoUnderstanding = $1 ? true : nil }
        )
    }

    private func xaiWebSearchBoolBinding(
        get: @escaping (WebSearchControls) -> Bool,
        set: @escaping (inout WebSearchControls, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let webSearch = controls.webSearch else { return false }
                return get(webSearch)
            },
            set: { isOn in
                var webSearch = controls.webSearch
                    ?? ChatControlNormalizationSupport.defaultWebSearchControls(
                        enabled: true,
                        providerType: .xai
                    )
                webSearch.enabled = true
                set(&webSearch, isOn)
                controls.webSearch = webSearch
                persistControlsToConversation()
            }
        )
    }
}
