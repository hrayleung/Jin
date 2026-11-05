import SwiftUI

struct OpenAIImage26ControlsMenuView: View {
    let controls: OpenAIImageGenerationControls
    let onUpdate: ((inout OpenAIImageGenerationControls) -> Void) -> Void
    let onEditAnimation: () -> Void

    var body: some View {
        Menu(ChatAuxiliaryControlSupport.nestedMenuTitle("Mode", current: controls.inputMode?.displayName)) {
            JinMenuSelectionItem("Automatic", isSelected: controls.inputMode == nil) {
                onUpdate {
                    $0.inputMode = nil
                    $0.editGuidance = nil
                    if $0.outputFormat?.isGenerationOnly == true { $0.outputFormat = .png }
                }
            }
            ForEach(OpenAIImageInputMode.allCases, id: \.self) { mode in
                JinMenuSelectionItem(mode.displayName, isSelected: controls.inputMode == mode) {
                    onUpdate {
                        $0.inputMode = mode
                        $0.editGuidance = nil
                        if mode == .edit, $0.outputFormat?.isGenerationOnly == true { $0.outputFormat = .png }
                    }
                }
            }
            Divider()
            Text("Uses attachments, otherwise the previous image.")
        }
        Menu(ChatAuxiliaryControlSupport.nestedMenuTitle("Complexity", current: controls.complexity?.displayName)) {
            JinMenuSelectionItem("Default (High)", isSelected: controls.complexity == nil) {
                onUpdate { $0.complexity = nil }
            }
            ForEach(OpenAIImageComplexity.allCases, id: \.self) { complexity in
                JinMenuSelectionItem(complexity.displayName, isSelected: controls.complexity == complexity) {
                    onUpdate { $0.complexity = complexity }
                }
            }
        }
        Menu(ChatAuxiliaryControlSupport.nestedMenuTitle("Edit Guidance", current: controls.editGuidance?.displayName)) {
            JinMenuSelectionItem("None", isSelected: controls.editGuidance == nil) {
                onUpdate { $0.editGuidance = nil }
            }
            ForEach(OpenAIImageEditGuidance.allCases, id: \.self) { guidance in
                JinMenuSelectionItem(guidance.displayName, isSelected: controls.editGuidance == guidance) {
                    onUpdate {
                        $0.editGuidance = guidance
                        $0.inputMode = .edit
                        if $0.outputFormat?.isGenerationOnly == true { $0.outputFormat = .png }
                    }
                }
                .help(guidance.helpText)
            }
            Divider()
            Text("Original first; transparent PNG guide last.")
            Text("Guide and original must have matching dimensions.")
        }
        if controls.outputFormat == .gif {
            Button("Animation (\(controls.frameCount ?? 9) frames, \(controls.frameDurationMilliseconds ?? 200) ms)…", action: onEditAnimation)
        }
        if controls.outputFormat?.isGenerationOnly == true {
            Text("SVG/GIF: text prompts only.")
                .foregroundStyle(.secondary)
        }
    }
}
