import Foundation
import Observation

/// Lives outside ChatView's `@State` so mutating thinking / search / MCP
/// controls does not invalidate ChatView's body (timeline, toolbar, text
/// editor). The composer chrome observes this store through
/// `ChatComposerControlsAccess`; ChatView action handlers may read
/// `controls`, but view bodies must not.
@Observable
@MainActor
final class ComposerControlsStore {
    var controls: GenerationControls

    init(controls: GenerationControls = GenerationControls()) {
        self.controls = controls
    }
}
