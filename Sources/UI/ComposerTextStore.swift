import Foundation
import Observation

/// Lives outside ChatView's `@State` so that mutating the composer text does
/// not invalidate ChatView's body. Views that need to react to keystrokes
/// (binding to the editor, computing `canSendDraft`, watching for slash
/// commands) observe this store directly; ChatView itself only passes the
/// reference down and reads `text` from non-body contexts.
@Observable
@MainActor
final class ComposerTextStore {
    var text: String = ""
}
