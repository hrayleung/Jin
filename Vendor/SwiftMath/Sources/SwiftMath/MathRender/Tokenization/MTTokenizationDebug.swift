import Foundation

/// Opt-in gate for the tokenization typesetter's debug logging. A literal
/// `false` at each call site made the compiler flag every gated `print` as
/// unreachable on release builds; reading the environment once keeps the
/// scaffolding available (`SWIFTMATH_DEBUG_TYPESETTING=1`) without the noise.
enum MTTokenizationDebug {
    static let isEnabled = ProcessInfo.processInfo.environment["SWIFTMATH_DEBUG_TYPESETTING"] != nil
}
