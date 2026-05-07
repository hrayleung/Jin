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
}
