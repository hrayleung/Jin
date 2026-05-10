import Foundation

extension Notification.Name {
    static let pluginCredentialsDidChange = Notification.Name("jin.pluginCredentialsDidChange")
    static let codexWorkingDirectoryPresetsDidChange = Notification.Name("jin.codexWorkingDirectoryPresetsDidChange")
    static let settingsNavigateToPlugin = Notification.Name("jin.settingsNavigateToPlugin")
}

enum SettingsNavigationUserInfoKey {
    static let pluginID = "pluginID"
}
