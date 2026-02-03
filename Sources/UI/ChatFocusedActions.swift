import SwiftUI

struct ChatFocusedActions {
    let canAttach: Bool
    let canStopStreaming: Bool
    let focusComposer: () -> Void
    let attach: () -> Void
    let stopStreaming: () -> Void
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
