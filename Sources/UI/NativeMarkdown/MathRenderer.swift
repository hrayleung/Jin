import AppKit
import SwiftUI
import SwiftMath

/// Outcome of preparing a LaTeX string for native rendering.
///
/// The whole point of the no-WebView design: we PARSE FIRST (with SwiftMath's
/// standalone `MTMathListBuilder`, which needs no view), then the caller picks
/// the view. On success we hand back a parsed `MTMathList` for an
/// `MTMathUILabel`; on any parse failure — unknown command, unsupported
/// environment, or mid-stream unbalanced braces — we degrade to the *raw*
/// LaTeX shown as selectable text. There is no WKWebView/KaTeX fallback.
enum MathRenderOutcome {
    case rendered(MTMathList)
    /// The original (un-normalized) source, to show verbatim as selectable text.
    case raw(String)
}

/// Pure, cached front door for native math rendering. Converts a LaTeX block
/// into either a parsed `MTMathList` or a raw-text fallback.
enum MathRenderer {
    // Keyed by the trimmed source. NSCache is thread-safe; in practice this is
    // only touched from the main actor (SwiftUI body evaluation). Bounded so a
    // long conversation full of distinct equations can't grow it without limit.
    private final class Box { let outcome: MathRenderOutcome; init(_ o: MathRenderOutcome) { outcome = o } }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        // Each entry is a parsed MTMathAtom tree (~10-25 KB for a moderate
        // equation); parsing is cheap enough that a miss is invisible.
        c.countLimit = 256
        return c
    }()

    /// Parse-first. Returns `.rendered` when SwiftMath parses the (normalized)
    /// LaTeX cleanly, otherwise `.raw` carrying the original source. Cheap to
    /// call repeatedly (cached); during streaming, incomplete LaTeX simply
    /// fails to parse and degrades to `.raw` until the block is complete.
    static func prepare(_ latex: String) -> MathRenderOutcome {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .raw(latex) }

        let key = trimmed as NSString
        if let cached = cache.object(forKey: key) { return cached.outcome }

        let outcome: MathRenderOutcome
        var error: NSError?
        if let list = MTMathListBuilder.build(fromString: normalize(trimmed), error: &error),
           error == nil {
            outcome = .rendered(list)
        } else {
            // Show what the user actually typed, not the normalized form.
            outcome = .raw(latex)
        }
        cache.setObject(Box(outcome), forKey: key)
        return outcome
    }

    /// Rewrites LaTeX environments that SwiftMath doesn't recognize into the
    /// equivalent ones it does, so common LLM output renders natively instead
    /// of degrading to text. SwiftMath knows `aligned`/`gather`/`cases`/`split`/
    /// `eqnarray` but NOT bare `align`, `gathered`, `dcases`, `equation`, etc.
    /// (verified against MTMathAtomFactory). Delimiters include the closing `}`
    /// so `align` never matches `aligned`/`alignat`.
    static func normalize(_ latex: String) -> String {
        var s = latex

        // env -> equivalent supported env
        let envAliases: [(from: String, to: String)] = [
            ("align*", "aligned"),
            ("align", "aligned"),
            ("aligned*", "aligned"),
            ("gathered", "gather"),
            ("gather*", "gather"),
            ("multline*", "gather"),
            ("multline", "gather"),
            ("dcases", "cases"),
            ("cases*", "cases"),
            ("eqnarray*", "eqnarray"),
            ("split*", "split"),
        ]
        for alias in envAliases {
            s = s.replacingOccurrences(of: "\\begin{\(alias.from)}", with: "\\begin{\(alias.to)}")
            s = s.replacingOccurrences(of: "\\end{\(alias.from)}", with: "\\end{\(alias.to)}")
        }

        // `equation`/`equation*` are just a single display row — drop the wrapper.
        for env in ["equation*", "equation"] {
            s = s.replacingOccurrences(of: "\\begin{\(env)}", with: "")
            s = s.replacingOccurrences(of: "\\end{\(env)}", with: "")
        }

        // `\fbox{…}` → native `\boxed{…}` (the fork renders \boxed as a stroked
        // frame; \boxed itself is handled natively by the parser).
        s = s.replacingOccurrences(of: "\\fbox{", with: "\\boxed{")

        return s
    }
}

/// Resolves a dynamic (appearance-aware) `NSColor` to a concrete value for a
/// given SwiftUI color scheme. SwiftMath bakes the text color into its Core
/// Text draw, so a bare dynamic color can render with the wrong appearance when
/// the display list is cached; resolving up front guarantees correct dark/light
/// color and lets `updateNSView` re-push it on a scheme flip.
enum MathColorResolver {
    static func resolve(_ color: NSColor, for scheme: ColorScheme) -> NSColor {
        guard let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) else {
            return color
        }
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}
