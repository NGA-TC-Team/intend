import AppKit

// MARK: - Token

struct SyntaxTokenResult {
    let range: NSRange
    let color: NSColor
}

// MARK: - Entry point

/// 코드 한 줄(또는 여러 줄)을 받아 언어별 문법 하이라이트 토큰 목록 반환.
/// AttributeRenderer.renderCodeBlock에서 호출.
func syntaxHighlight(code: String, language: String) -> [SyntaxTokenResult] {
    switch language.lowercased() {
    case "swift":                               return highlight(code, rules: swiftRules)
    case "python", "py":                        return highlight(code, rules: pythonRules)
    case "javascript", "js", "typescript", "ts": return highlight(code, rules: jsRules)
    case "go":                                  return highlight(code, rules: goRules)
    case "rust", "rs":                          return highlight(code, rules: rustRules)
    case "kotlin", "kt":                        return highlight(code, rules: kotlinRules)
    case "bash", "sh", "shell", "zsh":         return highlight(code, rules: bashRules)
    case "json":                                return highlight(code, rules: jsonRules)
    case "yaml", "yml":                         return highlight(code, rules: yamlRules)
    case "html", "xml":                         return highlight(code, rules: htmlRules)
    case "css", "scss", "sass":                 return highlight(code, rules: cssRules)
    default:                                    return []
    }
}

// MARK: - Rule

private struct Rule {
    let pattern: String
    let color:   NSColor
    let options: NSRegularExpression.Options
    init(_ pattern: String, _ color: NSColor, _ options: NSRegularExpression.Options = []) {
        self.pattern = pattern
        self.color   = color
        self.options = options
    }
}

// MARK: - Core highlighter

private func highlight(_ code: String, rules: [Rule]) -> [SyntaxTokenResult] {
    var result: [SyntaxTokenResult] = []
    var covered = IndexSet()  // 이미 처리된 UTF-16 인덱스 (중복 방지)
    let ns = code as NSString

    for rule in rules {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
        let fullRange = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
            guard let match else { return }
            // 첫 번째 캡처 그룹 우선, 없으면 전체 매치
            let tokenRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                ? match.range(at: 1)
                : match.range
            guard tokenRange.location != NSNotFound, tokenRange.length > 0 else { return }
            // 이미 다른 규칙이 처리한 범위와 겹치면 스킵
            let idxSet = IndexSet(integersIn: tokenRange.location ..< NSMaxRange(tokenRange))
            guard covered.intersection(idxSet).isEmpty else { return }
            covered.formUnion(idxSet)
            result.append(SyntaxTokenResult(range: tokenRange, color: rule.color))
        }
    }
    return result
}

// MARK: - Colors

private let kKeyword  = NSColor.systemPink
private let kString   = NSColor.systemGreen
private let kComment  = NSColor.systemGray
private let kNumber   = NSColor.systemOrange
private let kType     = NSColor.systemPurple
private let kBuiltin  = NSColor.systemTeal
private let kAttr     = NSColor.systemBlue

// MARK: - Language Rules

// Swift
private let swiftRules: [Rule] = [
    Rule(#"//[^\n]*"#,       kComment),
    Rule(#"/\*[\s\S]*?\*/"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#""(?:[^"\\]|\\.)*""#, kString),
    Rule(#"\b(let|var|func|class|struct|enum|protocol|extension|import|return|if|else|guard|switch|case|default|for|in|while|break|continue|throw|throws|try|catch|do|init|deinit|self|super|true|false|nil|override|static|final|private|fileprivate|internal|public|open|mutating|nonmutating|lazy|weak|unowned|inout|async|await|some|any|where|associatedtype|typealias)\b"#, kKeyword),
    Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, kType),
    Rule(#"@\w+"#, kAttr),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// Python
private let pythonRules: [Rule] = [
    Rule(#"#[^\n]*"#,           kComment),
    Rule(#"("""[\s\S]*?"""|'''[\s\S]*?''')"#, kString, [.dotMatchesLineSeparators]),
    Rule(#"("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#, kString),
    Rule(#"\b(def|class|import|from|return|if|elif|else|for|in|while|break|continue|try|except|finally|with|as|pass|raise|yield|lambda|and|or|not|is|True|False|None|async|await|global|nonlocal)\b"#, kKeyword),
    Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, kType),
    Rule(#"@\w+"#, kAttr),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// JavaScript / TypeScript
private let jsRules: [Rule] = [
    Rule(#"//[^\n]*"#,       kComment),
    Rule(#"/\*[\s\S]*?\*/"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#"(`(?:[^`\\]|\\.)*`|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#, kString),
    Rule(#"\b(const|let|var|function|class|extends|return|if|else|for|of|in|while|break|continue|try|catch|finally|throw|new|this|super|import|export|from|default|async|await|typeof|instanceof|void|delete|switch|case|yield|type|interface|enum|implements|abstract)\b"#, kKeyword),
    Rule(#"\b(true|false|null|undefined|NaN|Infinity)\b"#, kBuiltin),
    Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, kType),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// Go
private let goRules: [Rule] = [
    Rule(#"//[^\n]*"#,       kComment),
    Rule(#"/\*[\s\S]*?\*/"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#""(?:[^"\\]|\\.)*"|`[^`]*`"#, kString),
    Rule(#"\b(package|import|func|var|const|type|struct|interface|map|chan|go|defer|return|if|else|for|range|switch|case|default|break|continue|fallthrough|select|nil|true|false|make|new|len|cap|append|copy|delete|panic|recover)\b"#, kKeyword),
    Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, kType),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// Rust
private let rustRules: [Rule] = [
    Rule(#"//[^\n]*"#,       kComment),
    Rule(#"/\*[\s\S]*?\*/"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#""(?:[^"\\]|\\.)*""#, kString),
    Rule(#"\b(fn|let|mut|const|static|struct|enum|impl|trait|use|mod|pub|return|if|else|match|for|in|while|loop|break|continue|true|false|self|Self|super|crate|type|where|async|await|move|unsafe|extern|dyn|ref|as)\b"#, kKeyword),
    Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, kType),
    Rule(#"#\[.*?\]"#, kAttr),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// Kotlin
private let kotlinRules: [Rule] = [
    Rule(#"//[^\n]*"#,       kComment),
    Rule(#"/\*[\s\S]*?\*/"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#""(?:[^"\\]|\\.)*""#, kString),
    Rule(#"\b(fun|val|var|class|object|interface|return|if|else|when|for|in|while|break|continue|try|catch|finally|throw|new|this|super|import|package|companion|data|sealed|open|override|abstract|private|protected|public|internal|null|true|false|is|as|by|typealias|init|constructor)\b"#, kKeyword),
    Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, kType),
    Rule(#"@\w+"#, kAttr),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// Bash / Shell
private let bashRules: [Rule] = [
    Rule(#"#[^\n]*"#, kComment),
    Rule(#"("(?:[^"\\]|\\.)*"|'[^']*')"#, kString),
    Rule(#"\b(if|then|else|elif|fi|for|in|do|done|while|until|case|esac|function|return|export|local|readonly|declare|source|echo|printf|exit|set|unset|shift|eval)\b"#, kKeyword),
    Rule(#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, kBuiltin),
    Rule(#"\b\d+\b"#, kNumber),
]

// JSON
private let jsonRules: [Rule] = [
    Rule(#""(?:[^"\\]|\\.)*"\s*:"#,  kAttr),    // キー
    Rule(#":\s*("(?:[^"\\]|\\.)*")"#, kString), // 문자열 값
    Rule(#"\b(true|false|null)\b"#,   kKeyword),
    Rule(#"\b\d+\.?\d*\b"#,           kNumber),
]

// YAML
private let yamlRules: [Rule] = [
    Rule(#"#[^\n]*"#,       kComment),
    Rule(#"("(?:[^"\\]|\\.)*"|'[^']*')"#, kString),
    Rule(#"^(\s*\w[\w\s-]*):"#, kAttr, [.anchorsMatchLines]),  // 키
    Rule(#"\b(true|false|null|yes|no)\b"#, kKeyword),
    Rule(#"\b\d+\.?\d*\b"#, kNumber),
]

// HTML / XML
private let htmlRules: [Rule] = [
    Rule(#"<!--[\s\S]*?-->"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#"</?[A-Za-z][A-Za-z0-9-]*"#, kKeyword),
    Rule(#"\b[A-Za-z-]+=(?=")"#, kAttr),
    Rule(#""[^"]*""#, kString),
    Rule(#"&[A-Za-z]+;|&#\d+;"#, kBuiltin),
]

// CSS / SCSS
private let cssRules: [Rule] = [
    Rule(#"/\*[\s\S]*?\*/"#, kComment, [.dotMatchesLineSeparators]),
    Rule(#"//[^\n]*"#,       kComment),
    Rule(#"("(?:[^"\\]|\\.)*"|'[^']*')"#, kString),
    Rule(#"[.#]?[A-Za-z][A-Za-z0-9_-]*\s*\{"#, kKeyword),
    Rule(#"[A-Za-z-]+(?=\s*:)"#, kAttr),
    Rule(#":\s*([A-Za-z-]+)"#, kBuiltin),
    Rule(#"#[0-9A-Fa-f]{3,8}\b"#, kNumber),
    Rule(#"\b\d+\.?\d*(px|em|rem|vh|vw|%|pt|cm|mm|s|ms)?\b"#, kNumber),
    Rule(#"@[A-Za-z-]+"#, kAttr),
]
