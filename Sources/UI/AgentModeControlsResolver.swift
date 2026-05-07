import Foundation

enum AgentModeControlsResolver {
    static func controls(
        active: Bool,
        defaults: UserDefaults = .standard,
        pluginEnabled: (String, UserDefaults) -> Bool = { pluginID, defaults in
            AppPreferences.isPluginEnabled(pluginID, defaults: defaults)
        }
    ) -> AgentModeControls? {
        guard active, pluginEnabled("agent_mode", defaults) else { return nil }

        let workingDirectory = defaults.string(forKey: AppPreferenceKeys.agentModeWorkingDirectory) ?? ""
        let customPrefixesJSON = defaults.string(forKey: AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON) ?? "[]"
        let customPrefixes = AppPreferences.decodeStringArrayJSON(customPrefixesJSON)
        let safePrefixes = AgentCommandAllowlist.resolvedSafePrefixes(defaults: defaults)

        return AgentModeControls(
            enabled: true,
            workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
            allowedCommandPrefixes: safePrefixes + customPrefixes,
            autoApproveFileReads: boolValue(
                forKey: AppPreferenceKeys.agentModeAutoApproveFileReads,
                default: true,
                defaults: defaults
            ),
            bypassPermissions: boolValue(
                forKey: AppPreferenceKeys.agentModeBypassPermissions,
                default: false,
                defaults: defaults
            ),
            enabledTools: AgentEnabledTools(
                shellExecute: boolValue(forKey: AppPreferenceKeys.agentModeToolShell, default: true, defaults: defaults),
                fileRead: boolValue(forKey: AppPreferenceKeys.agentModeToolFileRead, default: true, defaults: defaults),
                fileWrite: boolValue(forKey: AppPreferenceKeys.agentModeToolFileWrite, default: true, defaults: defaults),
                fileEdit: boolValue(forKey: AppPreferenceKeys.agentModeToolFileEdit, default: true, defaults: defaults),
                globSearch: boolValue(forKey: AppPreferenceKeys.agentModeToolGlob, default: true, defaults: defaults),
                grepSearch: boolValue(forKey: AppPreferenceKeys.agentModeToolGrep, default: true, defaults: defaults)
            ),
            commandTimeoutSeconds: defaults.object(forKey: AppPreferenceKeys.agentModeCommandTimeoutSeconds) as? Int ?? 120,
            maxOutputBytes: 102_400
        )
    }

    private static func boolValue(forKey key: String, default defaultValue: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
