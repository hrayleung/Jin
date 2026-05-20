import Foundation

// MARK: - Tokenizers
//
// Pattern application order matters: later patterns overwrite earlier ones.
// So we apply keywords/types first, then function calls, then numbers,
// then strings, and finally comments so string/comment colors always win
// over false keyword matches inside them.

private func mk(_ pattern: String, _ classification: SyntaxClassification, group: Int = 0, options: NSRegularExpression.Options = []) -> SyntaxPattern? {
    SyntaxPattern(pattern, classification: classification, captureGroup: group, options: options)
}

private let stringDoubleQuote = #"\"(?:\\.|[^\"\\\n])*\""#
private let stringSingleQuote = #"'(?:\\.|[^'\\\n])*'"#
private let stringBacktick = #"`(?:\\.|[^`\\])*`"#
private let stringTripleDouble = #"\"\"\"[\s\S]*?\"\"\""#
private let stringTripleSingle = #"'''[\s\S]*?'''"#
private let numberPattern = #"(?<![\w.])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?![\w.])"#
private let functionCallPattern = #"\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#

struct SwiftTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(actor|any|as|associatedtype|async|await|break|case|catch|class|continue|default|defer|deinit|distributed|do|dynamic|else|enum|extension|fallthrough|fileprivate|final|for|func|get|guard|if|import|in|indirect|infix|init|inout|internal|is|lazy|let|mutating|nil|nonmutating|open|operator|optional|override|postfix|precedence|prefix|private|protocol|public|repeat|required|rethrows|return|self|set|some|static|struct|subscript|super|switch|throw|throws|try|typealias|var|weak|where|while|willSet|didSet)\b"#, .keyword),
        mk(#"\b([A-Z][A-Za-z0-9_]*)\b"#, .type),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringTripleDouble, .string),
        mk(stringDoubleQuote, .string),
        mk(#"(?m)//.*$"#, .comment),
        mk(#"/\*[\s\S]*?\*/"#, .comment),
    ].compactMap { $0 }
}

struct PythonTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b"#, .keyword),
        mk(#"\b(self|cls|__init__|__name__|__main__)\b"#, .literal),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringTripleDouble, .string),
        mk(stringTripleSingle, .string),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
        mk(#"(?m)#.*$"#, .comment),
    ].compactMap { $0 }
}

struct JavaScriptTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|false|finally|for|from|function|if|import|in|instanceof|let|new|null|of|return|static|super|switch|this|throw|true|try|typeof|undefined|var|void|while|with|yield)\b"#, .keyword),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringBacktick, .string),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
        mk(#"(?m)//.*$"#, .comment),
        mk(#"/\*[\s\S]*?\*/"#, .comment),
    ].compactMap { $0 }
}

struct TypeScriptTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(any|as|async|await|boolean|break|case|catch|class|const|continue|debugger|declare|default|delete|do|else|enum|export|extends|false|finally|for|from|function|if|implements|import|in|instanceof|interface|is|keyof|let|namespace|never|new|null|number|of|private|protected|public|readonly|return|static|string|super|switch|this|throw|true|try|type|typeof|undefined|unknown|var|void|while|with|yield)\b"#, .keyword),
        mk(#"\b([A-Z][A-Za-z0-9_]*)\b"#, .type),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringBacktick, .string),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
        mk(#"(?m)//.*$"#, .comment),
        mk(#"/\*[\s\S]*?\*/"#, .comment),
    ].compactMap { $0 }
}

struct BashTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(case|do|done|elif|else|esac|export|fi|for|function|if|in|local|return|select|then|time|until|while)\b"#, .keyword),
        mk(#"\$\{[^}]+\}"#, .property),
        mk(#"\$[A-Za-z_][A-Za-z0-9_]*"#, .property),
        mk(#"(?<=^|\s|\||;|&&|\|\|)([\w./-]+)(?=\s+)"#, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
        mk(#"(?m)#.*$"#, .comment),
    ].compactMap { $0 }
}

struct JSONTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\"(?:\\.|[^\"\\])*\"\s*:"#, .property),
        mk(#"\b(true|false|null)\b"#, .literal),
        mk(numberPattern, .number),
        mk(stringDoubleQuote, .string),
    ].compactMap { $0 }
}

struct YAMLTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"(?m)^\s*[#].*$"#, .comment),
        mk(#"(?m)^\s*[-]\s"#, .punctuation),
        mk(#"(?m)^[\s-]*([A-Za-z0-9_.-]+)\s*:"#, .property, group: 1),
        mk(#"\b(true|false|null|yes|no|on|off|~)\b"#, .literal, options: [.caseInsensitive]),
        mk(numberPattern, .number),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
    ].compactMap { $0 }
}

struct HTMLTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"<!--[\s\S]*?-->"#, .comment),
        mk(#"</?([A-Za-z][A-Za-z0-9-]*)"#, .tag, group: 1),
        mk(#"\s([A-Za-z-]+)="#, .attribute, group: 1),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
    ].compactMap { $0 }
}

struct CSSTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"/\*[\s\S]*?\*/"#, .comment),
        mk(#"(?m)^([^{}/]+)\{"#, .selector, group: 1),
        mk(#"([A-Za-z-]+)\s*:"#, .property, group: 1),
        mk(#"#[0-9a-fA-F]{3,8}\b"#, .literal),
        mk(numberPattern, .number),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
    ].compactMap { $0 }
}

struct GoTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b"#, .keyword),
        mk(#"\b(bool|byte|complex64|complex128|error|float32|float64|int|int8|int16|int32|int64|rune|string|uint|uint8|uint16|uint32|uint64|uintptr)\b"#, .type),
        mk(#"\b(true|false|nil|iota)\b"#, .literal),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringBacktick, .string),
        mk(stringDoubleQuote, .string),
        mk(#"(?m)//.*$"#, .comment),
        mk(#"/\*[\s\S]*?\*/"#, .comment),
    ].compactMap { $0 }
}

struct RustTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while)\b"#, .keyword),
        mk(#"\b(bool|char|str|i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|String|Vec|Option|Result|Box)\b"#, .type),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringDoubleQuote, .string),
        mk(#"(?m)//.*$"#, .comment),
        mk(#"/\*[\s\S]*?\*/"#, .comment),
    ].compactMap { $0 }
}

struct SQLTokenizer: LanguageTokenizer {
    let patterns: [SyntaxPattern] = [
        mk(#"\b(SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TABLE|VIEW|INDEX|JOIN|INNER|OUTER|LEFT|RIGHT|FULL|ON|AS|AND|OR|NOT|IN|LIKE|BETWEEN|IS|NULL|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|INTO|VALUES|SET|RETURNING|WITH|CASE|WHEN|THEN|ELSE|END|IF|EXISTS|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CONSTRAINT|DEFAULT|AUTO_INCREMENT|SERIAL|TEXT|VARCHAR|CHAR|INT|INTEGER|BIGINT|SMALLINT|BOOLEAN|FLOAT|REAL|DOUBLE|DECIMAL|NUMERIC|DATE|TIME|TIMESTAMP|JSON|JSONB)\b"#, .keyword, options: [.caseInsensitive]),
        mk(functionCallPattern, .function, group: 1),
        mk(numberPattern, .number),
        mk(stringDoubleQuote, .string),
        mk(stringSingleQuote, .string),
        mk(#"--.*$"#, .comment, options: [.anchorsMatchLines]),
        mk(#"/\*[\s\S]*?\*/"#, .comment),
    ].compactMap { $0 }
}
