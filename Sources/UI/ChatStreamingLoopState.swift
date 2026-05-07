import Foundation

extension ChatStreamingOrchestrator {
    struct StreamingLoopDiagnosticState {
        private(set) var didObserveFirstStreamEvent = false
        private(set) var didObserveFirstContentDelta = false
        private(set) var didObserveFirstThinkingDelta = false

        mutating func firstStreamEventName(_ event: StreamEvent) -> String? {
            guard !didObserveFirstStreamEvent else { return nil }
            didObserveFirstStreamEvent = true
            return event.diagnosticName
        }

        mutating func firstContentDeltaCount(_ delta: String) -> Int? {
            guard !didObserveFirstContentDelta else { return nil }
            didObserveFirstContentDelta = true
            return delta.count
        }

        mutating func firstThinkingDeltaCount(_ delta: String) -> Int? {
            guard !delta.isEmpty, !didObserveFirstThinkingDelta else { return nil }
            didObserveFirstThinkingDelta = true
            return delta.count
        }
    }

    struct StreamEventHandlingState {
        var accumulator: StreamingResponseAccumulator
        var uiFlushBuffer: StreamingUIFlushBuffer
        var diagnostics = StreamingLoopDiagnosticState()

        init(providerType: ProviderType) {
            accumulator = StreamingResponseAccumulator(providerType: providerType)
            uiFlushBuffer = StreamingUIFlushBuffer()
        }
    }
}
