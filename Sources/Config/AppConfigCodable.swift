import Foundation

/// JSON Codable 어댑터. AppConfig(값 타입)와 JSON 사이 변환 담당.
/// CodingKeys로 JSON 키 이름을 명시해 구조체 필드명과 독립적으로 유지.
struct AppConfigCodable: Codable {

    struct Editor: Codable {
        struct Font: Codable { var family: String; var size: Double }
        var font:           Font
        var lineHeight:     Double
        var tabSize:        Int
        var wordWrap:       Bool
        var spellCheck:     Bool
        var focusMode:      Bool
        var typewriterMode: Bool
    }

    struct Rendering: Codable {
        struct Heading: Codable { var scale: Double; var weight: String; var color: String? }
        struct Headings: Codable { var h1,h2,h3,h4,h5,h6: Heading }
        struct Paragraph: Codable { var lineHeight: Double; var firstLineIndent: Double; var spacing: Double }
        struct Blockquote: Codable { var borderColor: String?; var backgroundColor: String?; var italic: Bool }
        struct CodeBlock: Codable {
            var font: String; var fontSize: Double; var syntaxTheme: String
            var showLineNumbers: Bool; var backgroundColor: String?
        }
        struct InlineCode: Codable { var font: String; var fontSize: Double; var backgroundColor: String? }
        struct Link: Codable { var color: String?; var underline: Bool }
        struct List: Codable { var bulletStyle: String; var indentWidth: Double }
        struct HorizontalRule: Codable { var style: String; var color: String? }
        struct Table: Codable { var borderColor: String?; var headerBackground: String? }

        var headings:       Headings
        var paragraph:      Paragraph
        var blockquote:     Blockquote
        var codeBlock:      CodeBlock
        var inlineCode:     InlineCode
        var link:           Link
        var list:           List
        var horizontalRule: HorizontalRule
        var table:          Table
    }

    struct Theme: Codable {
        struct Colors: Codable {
            var background, foreground, accent, selection: String?
            var lightBackground, lightForeground: String?
            var darkBackground,  darkForeground:  String?
        }
        var name: String; var appearance: String; var colors: Colors
    }

    struct Export: Codable {
        struct PDF: Codable {
            var paperSize: String
            var marginTop,marginBottom,marginLeft,marginRight: Double
            var includeTableOfContents: Bool
        }
        struct HTML: Codable { var embedCSS: Bool; var syntaxHighlighting: Bool }
        var pdf: PDF; var html: HTML
    }

    struct Keybindings: Codable {
        var togglePreview, focusMode, exportPDF: String
    }

    var editor:      Editor
    var rendering:   Rendering
    var theme:       Theme
    var export:      Export
    var keybindings: Keybindings

    // MARK: - AppConfig → Codable init

    init(_ c: AppConfig) {
        editor = Editor(
            font: Editor.Font(family: c.editor.font.family, size: c.editor.font.size),
            lineHeight: c.editor.lineHeight, tabSize: c.editor.tabSize,
            wordWrap: c.editor.wordWrap, spellCheck: c.editor.spellCheck,
            focusMode: c.editor.focusMode, typewriterMode: c.editor.typewriterMode
        )
        let r = c.rendering
        rendering = Rendering(
            headings: Rendering.Headings(
                h1: .init(scale: r.headings.h1.scale, weight: r.headings.h1.weight, color: r.headings.h1.color),
                h2: .init(scale: r.headings.h2.scale, weight: r.headings.h2.weight, color: r.headings.h2.color),
                h3: .init(scale: r.headings.h3.scale, weight: r.headings.h3.weight, color: r.headings.h3.color),
                h4: .init(scale: r.headings.h4.scale, weight: r.headings.h4.weight, color: r.headings.h4.color),
                h5: .init(scale: r.headings.h5.scale, weight: r.headings.h5.weight, color: r.headings.h5.color),
                h6: .init(scale: r.headings.h6.scale, weight: r.headings.h6.weight, color: r.headings.h6.color)
            ),
            paragraph: .init(lineHeight: r.paragraph.lineHeight,
                             firstLineIndent: r.paragraph.firstLineIndent,
                             spacing: r.paragraph.spacing),
            blockquote: .init(borderColor: r.blockquote.borderColor,
                              backgroundColor: r.blockquote.backgroundColor,
                              italic: r.blockquote.italic),
            codeBlock: .init(font: r.codeBlock.font, fontSize: r.codeBlock.fontSize,
                             syntaxTheme: r.codeBlock.syntaxTheme,
                             showLineNumbers: r.codeBlock.showLineNumbers,
                             backgroundColor: r.codeBlock.backgroundColor),
            inlineCode: .init(font: r.inlineCode.font, fontSize: r.inlineCode.fontSize,
                              backgroundColor: r.inlineCode.backgroundColor),
            link: .init(color: r.link.color, underline: r.link.underline),
            list: .init(bulletStyle: r.list.bulletStyle, indentWidth: r.list.indentWidth),
            horizontalRule: .init(style: r.horizontalRule.style, color: r.horizontalRule.color),
            table: .init(borderColor: r.table.borderColor, headerBackground: r.table.headerBackground)
        )
        theme = Theme(name: c.theme.name, appearance: c.theme.appearance,
                      colors: .init(background: c.theme.colors.background,
                                    foreground: c.theme.colors.foreground,
                                    accent:     c.theme.colors.accent,
                                    selection:  c.theme.colors.selection,
                                    lightBackground: c.theme.colors.lightBackground,
                                    lightForeground: c.theme.colors.lightForeground,
                                    darkBackground:  c.theme.colors.darkBackground,
                                    darkForeground:  c.theme.colors.darkForeground))
        export = Export(
            pdf: .init(paperSize: c.export.pdf.paperSize,
                       marginTop: c.export.pdf.marginTop, marginBottom: c.export.pdf.marginBottom,
                       marginLeft: c.export.pdf.marginLeft, marginRight: c.export.pdf.marginRight,
                       includeTableOfContents: c.export.pdf.includeTableOfContents),
            html: .init(embedCSS: c.export.html.embedCSS,
                        syntaxHighlighting: c.export.html.syntaxHighlighting)
        )
        keybindings = Keybindings(togglePreview: c.keybindings.togglePreview,
                                  focusMode: c.keybindings.focusMode,
                                  exportPDF: c.keybindings.exportPDF)
    }

    // MARK: - Codable → AppConfig

    func toAppConfig() -> AppConfig {
        AppConfig(
            editor: EditorConfig(
                font: FontConfig(family: editor.font.family, size: editor.font.size),
                lineHeight: editor.lineHeight, tabSize: editor.tabSize,
                wordWrap: editor.wordWrap, spellCheck: editor.spellCheck,
                focusMode: editor.focusMode, typewriterMode: editor.typewriterMode
            ),
            rendering: RenderingConfig(
                headings: HeadingsConfig(
                    h1: .init(scale: rendering.headings.h1.scale, weight: rendering.headings.h1.weight, color: rendering.headings.h1.color),
                    h2: .init(scale: rendering.headings.h2.scale, weight: rendering.headings.h2.weight, color: rendering.headings.h2.color),
                    h3: .init(scale: rendering.headings.h3.scale, weight: rendering.headings.h3.weight, color: rendering.headings.h3.color),
                    h4: .init(scale: rendering.headings.h4.scale, weight: rendering.headings.h4.weight, color: rendering.headings.h4.color),
                    h5: .init(scale: rendering.headings.h5.scale, weight: rendering.headings.h5.weight, color: rendering.headings.h5.color),
                    h6: .init(scale: rendering.headings.h6.scale, weight: rendering.headings.h6.weight, color: rendering.headings.h6.color)
                ),
                paragraph: .init(lineHeight: rendering.paragraph.lineHeight,
                                 firstLineIndent: rendering.paragraph.firstLineIndent,
                                 spacing: rendering.paragraph.spacing),
                blockquote: .init(borderColor: rendering.blockquote.borderColor,
                                  backgroundColor: rendering.blockquote.backgroundColor,
                                  italic: rendering.blockquote.italic),
                codeBlock: .init(font: rendering.codeBlock.font, fontSize: rendering.codeBlock.fontSize,
                                 syntaxTheme: rendering.codeBlock.syntaxTheme,
                                 showLineNumbers: rendering.codeBlock.showLineNumbers,
                                 backgroundColor: rendering.codeBlock.backgroundColor),
                inlineCode: .init(font: rendering.inlineCode.font, fontSize: rendering.inlineCode.fontSize,
                                  backgroundColor: rendering.inlineCode.backgroundColor),
                link: .init(color: rendering.link.color, underline: rendering.link.underline),
                list: .init(bulletStyle: rendering.list.bulletStyle, indentWidth: rendering.list.indentWidth),
                horizontalRule: .init(style: rendering.horizontalRule.style, color: rendering.horizontalRule.color),
                table: .init(borderColor: rendering.table.borderColor,
                             headerBackground: rendering.table.headerBackground)
            ),
            theme: ThemeConfig(
                name: theme.name, appearance: theme.appearance,
                colors: ThemeColors(background: theme.colors.background,
                                    foreground: theme.colors.foreground,
                                    accent:     theme.colors.accent,
                                    selection:  theme.colors.selection,
                                    lightBackground: theme.colors.lightBackground,
                                    lightForeground: theme.colors.lightForeground,
                                    darkBackground:  theme.colors.darkBackground,
                                    darkForeground:  theme.colors.darkForeground)
            ),
            export: ExportConfig(
                pdf: PDFExportConfig(paperSize: export.pdf.paperSize,
                                     marginTop: export.pdf.marginTop, marginBottom: export.pdf.marginBottom,
                                     marginLeft: export.pdf.marginLeft, marginRight: export.pdf.marginRight,
                                     includeTableOfContents: export.pdf.includeTableOfContents),
                html: HTMLExportConfig(embedCSS: export.html.embedCSS,
                                       syntaxHighlighting: export.html.syntaxHighlighting)
            ),
            keybindings: KeybindingsConfig(
                togglePreview: keybindings.togglePreview,
                focusMode: keybindings.focusMode,
                exportPDF: keybindings.exportPDF
            )
        )
    }
}
