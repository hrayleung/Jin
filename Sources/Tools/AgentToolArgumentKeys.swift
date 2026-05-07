import Foundation

enum AgentToolArgumentKeys {
    static let command = ["command", "cmd"]
    static let workingDirectory = ["working_directory", "workingDirectory", "cwd"]

    static let filePath = ["path", "file", "file_path", "filePath"]
    static let fileReadOffset = ["offset", "line_offset", "start_line"]
    static let fileReadLimit = ["limit", "line_count", "max_lines"]
    static let fileContent = ["content", "text", "data"]
    static let fileEditOldText = ["old_text", "oldText", "old_string", "search"]
    static let fileEditNewText = ["new_text", "newText", "new_string", "replace"]

    static let globPattern = ["pattern", "glob"]
    static let grepPattern = ["pattern", "regex", "query"]
    static let searchDirectory = ["path", "directory", "dir"]
    static let includePattern = ["include", "glob", "file_pattern"]
}
