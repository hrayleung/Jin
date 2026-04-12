import Foundation

enum ClaudeManagedAgentResolutionSupport {
    static func canonicalManagedThreadModelID(
        providerID: String,
        requestedModelID: String,
        fallbackControls: GenerationControls,
        storedThreadControls: GenerationControls?,
        applyProviderDefaults: (inout GenerationControls) -> Void
    ) -> String {
        if let storedThreadControls {
            return managedThreadModelID(
                providerID: providerID,
                controls: storedThreadControls,
                applyProviderDefaults: applyProviderDefaults
            )
        }

        let trimmedRequestedModelID = requestedModelID.trimmingCharacters(in: .whitespacesAndNewlines)

        if let descriptor = ClaudeManagedAgentRuntime.syntheticThreadDescriptor(
            modelID: trimmedRequestedModelID,
            providerID: providerID
        ) {
            var controls = GenerationControls()
            controls.claudeManagedAgentID = descriptor.agentID
            controls.claudeManagedEnvironmentID = descriptor.environmentID
            return managedThreadModelID(
                providerID: providerID,
                controls: controls,
                applyProviderDefaults: applyProviderDefaults
            )
        }

        guard trimmedRequestedModelID.isEmpty else {
            return trimmedRequestedModelID
        }

        return managedThreadModelID(
            providerID: providerID,
            controls: fallbackControls,
            applyProviderDefaults: applyProviderDefaults
        )
    }

    static func resolvedConversationDisplayName(
        threadModelID: String,
        storedControls: GenerationControls?,
        applyProviderDefaults: (inout GenerationControls) -> Void
    ) -> String {
        var controls = storedControls ?? GenerationControls()
        applyProviderDefaults(&controls)
        return ClaudeManagedAgentRuntime.resolvedDisplayName(
            threadModelID: threadModelID,
            controls: controls
        )
    }

    private static func managedThreadModelID(
        providerID: String,
        controls initialControls: GenerationControls,
        applyProviderDefaults: (inout GenerationControls) -> Void
    ) -> String {
        var controls = initialControls
        applyProviderDefaults(&controls)
        return ClaudeManagedAgentRuntime.syntheticThreadModelID(
            providerID: providerID,
            agentID: controls.claudeManagedAgentID,
            environmentID: controls.claudeManagedEnvironmentID
        )
    }
}
