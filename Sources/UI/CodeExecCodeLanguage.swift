import Foundation

enum CodeExecCodeLanguage: Equatable {
    case python
    case javascript
    case shell
    case swift
    case generic

    var badgeLabel: String {
        switch self {
        case .python:
            return "Python"
        case .javascript:
            return "JavaScript"
        case .shell:
            return "Shell"
        case .swift:
            return "Swift"
        case .generic:
            return "Code"
        }
    }

    static func infer(from code: String) -> CodeExecCodeLanguage? {
        guard let trimmed = code.trimmedNonEmpty else { return nil }

        let lowercase = trimmed.lowercased()

        if trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/sh") || lowercase.contains("echo ") && lowercase.contains("$") {
            return .shell
        }

        if lowercase.contains("import swiftui") || lowercase.contains("struct ") && lowercase.contains(": view") {
            return .swift
        }

        if lowercase.contains("console.log") || lowercase.contains("const ") || lowercase.contains("let ") || lowercase.contains("=>") {
            return .javascript
        }

        if lowercase.contains("import ") || lowercase.contains("print(") || lowercase.contains("def ") || lowercase.contains("plt.") {
            return .python
        }

        return .generic
    }
}
