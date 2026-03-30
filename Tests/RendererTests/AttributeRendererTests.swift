import XCTest
import AppKit
@testable import Intend

@MainActor
final class AttributeRendererTests: XCTestCase {

    func test_renderAttributes_headingAppliesHeadingFontWithoutFollowingParagraph() {
        let markdown = "# Heading"
        let rendered = renderedString(for: markdown)
        let titleIndex = (markdown as NSString).range(of: "H").location

        let font = rendered.attribute(.font, at: titleIndex, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertGreaterThan(font?.pointSize ?? 0, AppConfig.default.editor.font.size)
    }

    func test_renderAttributes_punctuationOnlyParagraphStaysVisible() {
        let markdown = ".?! ..."
        let rendered = renderedString(for: markdown)

        for token in [".", "?", "!"] {
            let index = (markdown as NSString).range(of: token).location
            let color = rendered.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            XCTAssertNotNil(color)
            XCTAssertNotEqual(color, NSColor.clear)
        }
    }

    func test_renderAttributes_codeFenceHidesOnlyFenceTokens() {
        let markdown = "```swift\nlet x = 1\n```"
        let rendered = renderedString(for: markdown)

        let firstFenceIndex = 0
        let codeIndex = (markdown as NSString).range(of: "let").location

        let fenceColor = rendered.attribute(.foregroundColor, at: firstFenceIndex, effectiveRange: nil) as? NSColor
        let codeColor = rendered.attribute(.foregroundColor, at: codeIndex, effectiveRange: nil) as? NSColor

        XCTAssertEqual(fenceColor, NSColor.clear)
        XCTAssertNotNil(codeColor)
        XCTAssertNotEqual(codeColor, NSColor.clear)
    }

    func test_renderAttributes_tableSeparatorRowRemainsVisible() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let rendered = renderedString(for: markdown)
        let separatorIndex = (markdown as NSString).range(of: "---").location

        let color = rendered.attribute(.foregroundColor, at: separatorIndex, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color)
        XCTAssertNotEqual(color, NSColor.clear)
    }

    func test_activeHeadingBlockStaysInSourceStyle() throws {
        let textView = makeTextView(markdown: "# 제목\n\n본문")
        let storage = try XCTUnwrap(textView.textStorage as? MarkdownTextStorage)

        let headingSelection = NSRange(location: 0, length: 0)
        textView.setSelectedRange(headingSelection)
        storage.refreshRenderedRanges(after: headingSelection)

        let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let color = textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        XCTAssertEqual(Double(font?.pointSize ?? 0), AppConfig.default.editor.font.size)
        XCTAssertEqual(color, ThemeManager.shared.foregroundColor)
    }

    func test_inactiveHeadingBlockRendersAfterSelectionLeavesBlock() throws {
        let textView = makeTextView(markdown: "# 제목\n\n본문")
        let storage = try XCTUnwrap(textView.textStorage as? MarkdownTextStorage)

        let paragraphSelection = NSRange(location: 6, length: 0)
        textView.setSelectedRange(paragraphSelection)
        storage.refreshRenderedRanges(after: paragraphSelection)

        let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let color = textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        XCTAssertGreaterThan(font?.pointSize ?? 0, AppConfig.default.editor.font.size)
        XCTAssertEqual(color, ThemeManager.shared.syntaxTokenColor)
    }

    func test_typingAttributesStayAtBodyStyleWhenCursorMovesInsideHeading() throws {
        let textView = makeTextView(markdown: "# 제목")
        let storage = try XCTUnwrap(textView.textStorage as? MarkdownTextStorage)

        let selection = NSRange(location: 0, length: 0)
        textView.setSelectedRange(selection)
        storage.refreshRenderedRanges(after: selection)

        let font = textView.typingAttributes[.font] as? NSFont
        let color = textView.typingAttributes[.foregroundColor] as? NSColor

        XCTAssertEqual(Double(font?.pointSize ?? 0), AppConfig.default.editor.font.size)
        XCTAssertEqual(color, ThemeManager.shared.foregroundColor)
    }

    private func renderedString(for markdown: String) -> NSAttributedString {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = nil }

        let config = AppConfig.default
        let theme = ThemeManager.shared
        let result = parse(markdown: markdown)
        let patches = renderAttributes(from: result, config: config, theme: theme)

        let bodyFont = NSFont(name: config.editor.font.family, size: config.editor.font.size)
            ?? NSFont.systemFont(ofSize: config.editor.font.size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = config.rendering.paragraph.lineHeight

        let rendered = NSMutableAttributedString(string: markdown, attributes: [
            .font: bodyFont,
            .foregroundColor: theme.foregroundColor,
            .paragraphStyle: paragraph
        ])

        for patch in patches {
            rendered.addAttributes(patch.attrs, range: patch.range)
        }
        return rendered
    }

    private func makeTextView(markdown: String) -> MarkdownTextView {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        addTeardownBlock { NSApp.appearance = nil }

        let textView = MarkdownTextView()
        textView.applyConfig(.default)
        textView.string = markdown
        return textView
    }
}
