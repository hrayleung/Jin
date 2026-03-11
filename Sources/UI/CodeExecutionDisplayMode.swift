enum CodeExecutionDisplayMode: String, CaseIterable, Identifiable {
    case expanded
    case collapseOnComplete
    case alwaysCollapsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expanded: return "Always Expanded"
        case .collapseOnComplete: return "Collapse After Response"
        case .alwaysCollapsed: return "Always Collapsed"
        }
    }

    var description: String {
        switch self {
        case .expanded:
            return "Code execution activities stay expanded at all times. You can still collapse them manually."
        case .collapseOnComplete:
            return "Activities are expanded during streaming and automatically collapsed once the response finishes."
        case .alwaysCollapsed:
            return "Activities are always collapsed. The header still shows status. Click to expand at any time."
        }
    }

    var startsExpandedOnComplete: Bool {
        self == .expanded
    }

    var startsExpandedDuringStreaming: Bool {
        self != .alwaysCollapsed
    }
}
