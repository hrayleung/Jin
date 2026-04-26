enum MainSidebarVisibility {
    static let defaultIsVisible = true

    static func toggled(_ isVisible: Bool) -> Bool {
        !isVisible
    }
}
