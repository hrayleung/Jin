enum AssistantSidebarLayout: String {
    case list
    case grid
    case dropdown
}

enum AssistantSidebarSort: String, CaseIterable {
    case custom
    case name
    case recent

    var label: String {
        switch self {
        case .custom: return "Custom"
        case .name: return "Name"
        case .recent: return "Recent"
        }
    }
}
