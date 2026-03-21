import SwiftUI

struct ChatFocusedActions {
    let canAttach: Bool
    let canStopStreaming: Bool
    let isComposerHidden: Bool
    let focusComposer: () -> Void
    let openModelPicker: () -> Void
    let openAddModelPicker: () -> Void
    let attach: () -> Void
    let stopStreaming: () -> Void
    let toggleExpandedComposer: () -> Void
    let toggleComposerVisibility: () -> Void
}

private struct ChatFocusedActionsKey: FocusedValueKey {
    typealias Value = ChatFocusedActions
}

extension FocusedValues {
    var chatActions: ChatFocusedActions? {
        get { self[ChatFocusedActionsKey.self] }
        set { self[ChatFocusedActionsKey.self] = newValue }
    }
}
