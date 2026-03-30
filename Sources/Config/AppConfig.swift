import AppKit

// MARK: - Font resolution helper

/// AppConfig.Editor.Font.family 에 저장되는 시스템 폰트 sentinel 값.
/// NSFontManager 목록에 없는 ".AppleSystemUIFont"를 저장해 NSFont.systemFont 사용을 지시한다.
let systemFontFamilySentinel = ".AppleSystemUIFont"

/// family 이름에서 NSFont를 생성한다.
/// sentinel 또는 빈 문자열이면 NSFont.systemFont(ofSize:)를 반환한다.
func resolveFont(family: String, size: CGFloat) -> NSFont {
    guard family != systemFontFamilySentinel, !family.isEmpty else {
        return NSFont.systemFont(ofSize: size)
    }
    return NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
}

// MARK: - Root config (완전한 값 타입, 모든 필드 non-optional)

struct AppConfig: Equatable, Sendable {
    var editor:      EditorConfig
    var rendering:   RenderingConfig
    var theme:       ThemeConfig
    var export:      ExportConfig
    var keybindings: KeybindingsConfig

    static let `default` = AppConfig(
        editor:      .default,
        rendering:   .default,
        theme:       .default,
        export:      .default,
        keybindings: .default
    )
}

// MARK: - Editor

struct EditorConfig: Equatable, Sendable {
    var font:           FontConfig
    var lineHeight:     Double
    var tabSize:        Int
    var wordWrap:       Bool
    var spellCheck:     Bool
    var focusMode:      Bool
    var typewriterMode: Bool

    static let `default` = EditorConfig(
        font:           FontConfig(family: "Helvetica Neue", size: 16),
        lineHeight:     1.6,
        tabSize:        4,
        wordWrap:       true,
        spellCheck:     false,
        focusMode:      false,
        typewriterMode: false
    )
}

struct FontConfig: Equatable, Sendable {
    var family: String
    var size:   Double
}

// MARK: - Rendering

struct RenderingConfig: Equatable, Sendable {
    var headings:       HeadingsConfig
    var paragraph:      ParagraphConfig
    var blockquote:     BlockquoteConfig
    var codeBlock:      CodeBlockConfig
    var inlineCode:     InlineCodeConfig
    var link:           LinkConfig
    var list:           ListConfig
    var horizontalRule: HorizontalRuleConfig
    var table:          TableConfig

    static let `default` = RenderingConfig(
        headings:       .default,
        paragraph:      .default,
        blockquote:     .default,
        codeBlock:      .default,
        inlineCode:     .default,
        link:           .default,
        list:           .default,
        horizontalRule: .default,
        table:          .default
    )

    /// 레벨(1~6)에 맞는 HeadingStyle 반환
    func headingStyle(level: Int) -> HeadingStyle {
        switch level {
        case 1: return headings.h1
        case 2: return headings.h2
        case 3: return headings.h3
        case 4: return headings.h4
        case 5: return headings.h5
        default: return headings.h6
        }
    }
}

struct HeadingsConfig: Equatable, Sendable {
    var h1, h2, h3, h4, h5, h6: HeadingStyle

    static let `default` = HeadingsConfig(
        h1: HeadingStyle(scale: 2.0, weight: "bold",     color: nil),
        h2: HeadingStyle(scale: 1.6, weight: "bold",     color: nil),
        h3: HeadingStyle(scale: 1.3, weight: "semibold", color: nil),
        h4: HeadingStyle(scale: 1.1, weight: "semibold", color: nil),
        h5: HeadingStyle(scale: 1.0, weight: "medium",   color: nil),
        h6: HeadingStyle(scale: 1.0, weight: "medium",   color: "#888888")
    )
}

struct HeadingStyle: Equatable, Sendable {
    var scale:  Double   // baseSize 의 배수
    var weight: String   // "bold" | "semibold" | "medium" | "regular"
    var color:  String?  // nil → 시스템 label 색상
}

struct ParagraphConfig: Equatable, Sendable {
    var lineHeight:       Double
    var firstLineIndent:  Double
    var spacing:          Double

    static let `default` = ParagraphConfig(lineHeight: 1.6, firstLineIndent: 0, spacing: 1.0)
}

struct BlockquoteConfig: Equatable, Sendable {
    var borderColor:     String?
    var backgroundColor: String?
    var italic:          Bool

    static let `default` = BlockquoteConfig(borderColor: nil, backgroundColor: nil, italic: true)
}

struct CodeBlockConfig: Equatable, Sendable {
    var font:            String
    var fontSize:        Double
    var syntaxTheme:     String
    var showLineNumbers: Bool
    var backgroundColor: String?

    static let `default` = CodeBlockConfig(
        font: "Menlo", fontSize: 14,
        syntaxTheme: "github-dark",
        showLineNumbers: false,
        backgroundColor: nil
    )
}

struct InlineCodeConfig: Equatable, Sendable {
    var font:            String
    var fontSize:        Double
    var backgroundColor: String?

    static let `default` = InlineCodeConfig(font: "Menlo", fontSize: 14, backgroundColor: nil)
}

struct LinkConfig: Equatable, Sendable {
    var color:     String?
    var underline: Bool

    static let `default` = LinkConfig(color: nil, underline: true)
}

struct ListConfig: Equatable, Sendable {
    var bulletStyle:  String  // "disc" | "circle" | "square"
    var indentWidth:  Double

    static let `default` = ListConfig(bulletStyle: "disc", indentWidth: 24)
}

struct HorizontalRuleConfig: Equatable, Sendable {
    var style: String   // "line" | "dashed"
    var color: String?

    static let `default` = HorizontalRuleConfig(style: "line", color: nil)
}

struct TableConfig: Equatable, Sendable {
    var borderColor:      String?
    var headerBackground: String?

    static let `default` = TableConfig(borderColor: nil, headerBackground: nil)
}

// MARK: - Theme

struct ThemeConfig: Equatable, Sendable {
    var name:       String   // "default" | "solarized" | "nord" | ...
    var appearance: String   // "auto" | "light" | "dark"
    var colors:     ThemeColors

    static let `default` = ThemeConfig(
        name: "default",
        appearance: "auto",
        colors: .default
    )
}

struct ThemeColors: Equatable, Sendable {
    /// 라이트/다크 공통 또는 appearance 무관 색상 (nil → 시스템 시맨틱 색상)
    var background: String?
    var foreground: String?
    var accent:     String?
    var selection:  String?

    /// 라이트 모드 전용 색상 override (nil → background/foreground 공통값 사용)
    var lightBackground: String?
    var lightForeground: String?

    /// 다크 모드 전용 색상 override (nil → background/foreground 공통값 사용)
    var darkBackground: String?
    var darkForeground: String?

    static let `default` = ThemeColors(
        background: nil, foreground: nil, accent: nil, selection: nil,
        lightBackground: nil, lightForeground: nil,
        darkBackground: nil, darkForeground: nil
    )

    /// 현재 appearance에 맞는 배경색 hex 반환.
    func resolvedBackground(isDark: Bool) -> String? {
        isDark ? (darkBackground ?? background) : (lightBackground ?? background)
    }

    /// 현재 appearance에 맞는 전경색 hex 반환.
    func resolvedForeground(isDark: Bool) -> String? {
        isDark ? (darkForeground ?? foreground) : (lightForeground ?? foreground)
    }
}

// MARK: - Export

struct ExportConfig: Equatable, Sendable {
    var pdf:  PDFExportConfig
    var html: HTMLExportConfig

    static let `default` = ExportConfig(pdf: .default, html: .default)
}

struct PDFExportConfig: Equatable, Sendable {
    var paperSize:              String  // "A4" | "Letter"
    var marginTop:              Double
    var marginBottom:           Double
    var marginLeft:             Double
    var marginRight:            Double
    var includeTableOfContents: Bool

    static let `default` = PDFExportConfig(
        paperSize: "A4",
        marginTop: 20, marginBottom: 20, marginLeft: 25, marginRight: 25,
        includeTableOfContents: false
    )
}

struct HTMLExportConfig: Equatable, Sendable {
    var embedCSS:           Bool
    var syntaxHighlighting: Bool

    static let `default` = HTMLExportConfig(embedCSS: true, syntaxHighlighting: true)
}

// MARK: - Keybindings

struct KeybindingsConfig: Equatable, Sendable {
    var togglePreview: String
    var focusMode:     String
    var exportPDF:     String

    static let `default` = KeybindingsConfig(
        togglePreview: "Cmd+Shift+P",
        focusMode:     "Cmd+Shift+F",
        exportPDF:     "Cmd+Shift+E"
    )
}

