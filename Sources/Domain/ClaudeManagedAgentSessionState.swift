import Foundation

struct ClaudeManagedAgentSessionState: Sendable {
    let remoteSessionID: String
    let remoteModelID: String?

    init(remoteSessionID: String, remoteModelID: String? = nil) {
        self.remoteSessionID = remoteSessionID
        self.remoteModelID = remoteModelID
    }
}
