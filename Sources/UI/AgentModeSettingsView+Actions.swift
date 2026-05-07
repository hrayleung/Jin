import Foundation

#if os(macOS)
import AppKit
#endif

extension AgentModeSettingsView {
    func selectDirectory() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a working directory for agent mode"

        let normalizedWorkingDirectory = AgentWorkingDirectorySupport.normalizedPath(from: workingDirectoryDraft)
        if !normalizedWorkingDirectory.isEmpty {
            let currentDir = URL(fileURLWithPath: normalizedWorkingDirectory, isDirectory: true)
            if FileManager.default.fileExists(atPath: currentDir.path) {
                panel.directoryURL = currentDir
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            applyWorkingDirectory(url.path)
            workingDirectoryDraft = url.path
        }
        #endif
    }

    func syncWorkingDirectoryDraft() {
        if workingDirectoryDraft != storedWorkingDirectory {
            workingDirectoryDraft = storedWorkingDirectory
        }
    }

    func applyWorkingDirectory(_ value: String) {
        let normalized = AgentWorkingDirectorySupport.normalizedPath(from: value)
        if storedWorkingDirectory != normalized {
            storedWorkingDirectory = normalized
        }
    }

    func addPrefix() {
        let prefixes = AgentModeCommandPrefixSupport.addingPrefix(newPrefix, to: allowedPrefixes)
        guard prefixes != allowedPrefixes else {
            if AgentModeCommandPrefixSupport.canAddPrefix(newPrefix) {
                newPrefix = ""
            }
            return
        }

        allowedPrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
        newPrefix = ""
    }

    func removePrefix(_ prefix: String) {
        let prefixes = AgentModeCommandPrefixSupport.removingPrefix(prefix, from: allowedPrefixes)
        allowedPrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
    }

    func addSafePrefix() {
        let prefixes = AgentModeCommandPrefixSupport.addingPrefix(newSafePrefix, to: safePrefixes)
        guard prefixes != safePrefixes else {
            if AgentModeCommandPrefixSupport.canAddPrefix(newSafePrefix) {
                newSafePrefix = ""
            }
            return
        }

        safePrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
        newSafePrefix = ""
    }

    func removeSafePrefix(_ prefix: String) {
        let prefixes = AgentModeCommandPrefixSupport.removingPrefix(prefix, from: safePrefixes)
        safePrefixesJSON = AppPreferences.encodeStringArrayJSON(prefixes)
    }

    @MainActor
    func refreshRTKStatus() async {
        guard !isRefreshingRTKStatus else { return }
        isRefreshingRTKStatus = true
        defer { isRefreshingRTKStatus = false }
        let status = await RTKRuntimeSupport.status()
        rtkStatus = status
    }
}
