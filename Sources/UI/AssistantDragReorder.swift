import SwiftUI
import UniformTypeIdentifiers

/// Drag/drop reorder for assistant tiles. Uses the legacy `.onDrag` /
/// `.onDrop` API with the standard `public.text` UTI and an NSString
/// payload — the modern Transferable + custom-UTType path silently
/// dropped on macOS, and so did `.ownProcess` NSItemProvider visibility
/// + bespoke UTI. See `/Users/hinrayleung/.claude/plans/lucky-skipping-reef.md`
/// for the full diagnosis (List ancestor + Button + visibility + UTI
/// declaration each kill the drop).
struct AssistantDragReorderModifier: ViewModifier {
    let isEnabled: Bool
    let assistantID: String
    let onReorder: (String) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .onDrag {
                    NSItemProvider(object: assistantID as NSString)
                }
                .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    let target = assistantID
                    let handler = onReorder
                    provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let nsString = object as? NSString else { return }
                        let sourceID = nsString as String
                        guard !sourceID.isEmpty, sourceID != target else { return }
                        DispatchQueue.main.async {
                            handler(sourceID)
                        }
                    }
                    return true
                }
        } else {
            content
        }
    }
}

extension View {
    func assistantDragReorder(
        isEnabled: Bool,
        assistantID: String,
        onReorder: @escaping (String) -> Void
    ) -> some View {
        modifier(AssistantDragReorderModifier(
            isEnabled: isEnabled,
            assistantID: assistantID,
            onReorder: onReorder
        ))
    }
}
