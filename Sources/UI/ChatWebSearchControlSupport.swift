import Foundation

extension ChatAuxiliaryControlSupport {
    static func updateSearchPluginControls(
        controls: GenerationControls,
        mutate: (inout SearchPluginControls) -> Void
    ) -> GenerationControls {
        var controls = controls
        var searchPlugin = controls.searchPlugin ?? SearchPluginControls()
        mutate(&searchPlugin)
        controls.searchPlugin = searchPlugin
        return controls
    }
}
