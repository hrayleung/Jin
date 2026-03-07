import Foundation

enum CodexSandboxMode: String, Codable, CaseIterable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"

    static let `default`: CodexSandboxMode = .workspaceWrite

    var displayName: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .workspaceWrite:
            return "Workspace Write"
        case .dangerFullAccess:
            return "Full Access"
        }
    }

    var badgeText: String {
        switch self {
        case .readOnly:
            return "RO"
        case .workspaceWrite:
            return "RW"
        case .dangerFullAccess:
            return "FA"
        }
    }

    var systemImage: String {
        switch self {
        case .readOnly:
            return "lock"
        case .workspaceWrite:
            return "pencil.and.list.clipboard"
        case .dangerFullAccess:
            return "exclamationmark.shield"
        }
    }

    var summary: String {
        switch self {
        case .readOnly:
            return "Inspect code without writing files or running mutating commands."
        case .workspaceWrite:
            return "Allow edits inside the selected workspace while keeping sandbox protection."
        case .dangerFullAccess:
            return "Remove sandbox restrictions. Use only when you trust the workspace and prompt."
        }
    }

    var threadStartValue: String { rawValue }

    var turnStartValue: [String: Any] {
        switch self {
        case .readOnly:
            return ["type": "readOnly"]
        case .workspaceWrite:
            return ["type": "workspaceWrite"]
        case .dangerFullAccess:
            return ["type": "dangerFullAccess"]
        }
    }
}

enum CodexPersonality: String, Codable, CaseIterable {
    case none
    case friendly
    case pragmatic

    var displayName: String {
        switch self {
        case .none:
            return "Minimal"
        case .friendly:
            return "Friendly"
        case .pragmatic:
            return "Pragmatic"
        }
    }

    var summary: String {
        switch self {
        case .none:
            return "Keep the assistant neutral and terse."
        case .friendly:
            return "Lean collaborative with softer progress updates."
        case .pragmatic:
            return "Stay concise, direct, and execution-focused."
        }
    }
}

private enum CodexProviderSpecificKey {
    static let workingDirectory = "codex_cwd"
    static let legacyWorkingDirectory = "cwd"
    static let sandboxMode = "codex_sandbox_mode"
    static let legacyApprovalPolicy = "codex_approval_policy"
    static let legacySandboxPolicy = "codex_sandbox_policy"
    static let personality = "codex_personality"
    static let internalResumeThreadID = "codex_internal_resume_thread_id"
    static let internalPendingRollbackTurns = "codex_internal_pending_rollback_turns"
}

extension GenerationControls {
    var codexWorkingDirectory: String? {
        get {
            normalizedCodexStringValue(for: CodexProviderSpecificKey.workingDirectory)
                ?? normalizedCodexStringValue(for: CodexProviderSpecificKey.legacyWorkingDirectory)
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                providerSpecific[CodexProviderSpecificKey.workingDirectory] = AnyCodable(trimmed)
            } else {
                providerSpecific.removeValue(forKey: CodexProviderSpecificKey.workingDirectory)
            }
            providerSpecific.removeValue(forKey: CodexProviderSpecificKey.legacyWorkingDirectory)
        }
    }

    var codexSandboxMode: CodexSandboxMode {
        get {
            guard let raw = normalizedCodexStringValue(for: CodexProviderSpecificKey.sandboxMode),
                  let mode = CodexSandboxMode(rawValue: raw) else {
                return .default
            }
            return mode
        }
        set {
            if newValue == .default {
                providerSpecific.removeValue(forKey: CodexProviderSpecificKey.sandboxMode)
            } else {
                providerSpecific[CodexProviderSpecificKey.sandboxMode] = AnyCodable(newValue.rawValue)
            }
        }
    }

    var codexPersonality: CodexPersonality? {
        get {
            guard let raw = normalizedCodexStringValue(for: CodexProviderSpecificKey.personality) else {
                return nil
            }
            return CodexPersonality(rawValue: raw)
        }
        set {
            if let newValue {
                providerSpecific[CodexProviderSpecificKey.personality] = AnyCodable(newValue.rawValue)
            } else {
                providerSpecific.removeValue(forKey: CodexProviderSpecificKey.personality)
            }
        }
    }

    var codexResumeThreadID: String? {
        get {
            normalizedCodexStringValue(for: CodexProviderSpecificKey.internalResumeThreadID)
        }
        set {
            if let newValue {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    providerSpecific.removeValue(forKey: CodexProviderSpecificKey.internalResumeThreadID)
                } else {
                    providerSpecific[CodexProviderSpecificKey.internalResumeThreadID] = AnyCodable(trimmed)
                }
            } else {
                providerSpecific.removeValue(forKey: CodexProviderSpecificKey.internalResumeThreadID)
            }
        }
    }

    var codexPendingRollbackTurns: Int {
        get {
            if let intValue = providerSpecific[CodexProviderSpecificKey.internalPendingRollbackTurns]?.value as? Int {
                return max(0, intValue)
            }
            if let doubleValue = providerSpecific[CodexProviderSpecificKey.internalPendingRollbackTurns]?.value as? Double {
                return max(0, Int(doubleValue))
            }
            return 0
        }
        set {
            if newValue > 0 {
                providerSpecific[CodexProviderSpecificKey.internalPendingRollbackTurns] = AnyCodable(newValue)
            } else {
                providerSpecific.removeValue(forKey: CodexProviderSpecificKey.internalPendingRollbackTurns)
            }
        }
    }

    var codexActiveOverrideCount: Int {
        var count = 0
        if codexWorkingDirectory != nil {
            count += 1
        }
        if codexSandboxMode != .default {
            count += 1
        }
        if codexPersonality != nil {
            count += 1
        }
        return count
    }

    mutating func normalizeCodexProviderSpecific(for providerType: ProviderType?) {
        guard providerType == .codexAppServer else {
            removeCodexProviderSpecificKeys()
            return
        }

        codexWorkingDirectory = codexWorkingDirectory
        codexSandboxMode = codexSandboxMode
        codexPersonality = codexPersonality
        providerSpecific.removeValue(forKey: CodexProviderSpecificKey.legacyApprovalPolicy)
        providerSpecific.removeValue(forKey: CodexProviderSpecificKey.legacySandboxPolicy)
    }

    mutating func removeCodexProviderSpecificKeys() {
        let codexKeys = providerSpecific.keys.filter { key in
            key == CodexProviderSpecificKey.legacyWorkingDirectory || key.hasPrefix("codex_")
        }
        for key in codexKeys {
            providerSpecific.removeValue(forKey: key)
        }
    }

    private func normalizedCodexStringValue(for key: String) -> String? {
        guard let raw = providerSpecific[key]?.value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
