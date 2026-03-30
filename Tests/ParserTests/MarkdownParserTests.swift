import XCTest
@testable import Intend

final class MarkdownParserTests: XCTestCase {

    // MARK: - Headings

    func test_heading_level1() {
        let result = parse(markdown: "# Hello World")
        XCTAssertEqual(result.nodes.count, 1)
        guard case .heading(let level, let children, _) = result.nodes[0] else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(children, [.text("Hello World")])
    }

    func test_heading_allLevels() {
        let md = (1...6).map { String(repeating: "#", count: $0) + " H\($0)" }.joined(separator: "\n")
        let result = parse(markdown: md)
        XCTAssertEqual(result.nodes.count, 6)
        for (index, node) in result.nodes.enumerated() {
            guard case .heading(let level, _, _) = node else {
                return XCTFail("Node \(index) is not a heading")
            }
            XCTAssertEqual(level, index + 1)
        }
    }

    // MARK: - Paragraph & inline

    func test_paragraph_plainText() {
        let result = parse(markdown: "Hello, world.")
        guard case .paragraph(let children, _) = result.nodes.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(children, [.text("Hello, world.")])
    }

    func test_paragraph_bold() {
        let result = parse(markdown: "**bold**")
        guard case .paragraph(let children, _) = result.nodes.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(children, [.strong(children: [.text("bold")])])
    }

    func test_paragraph_italic() {
        let result = parse(markdown: "_italic_")
        guard case .paragraph(let children, _) = result.nodes.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(children, [.emphasis(children: [.text("italic")])])
    }

    func test_paragraph_inlineCode() {
        let result = parse(markdown: "`code`")
        guard case .paragraph(let children, _) = result.nodes.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(children, [.inlineCode("code")])
    }

    func test_paragraph_mixedInlines() {
        let result = parse(markdown: "Hello **bold** and _em_")
        guard case .paragraph(let children, _) = result.nodes.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(children.contains(.text("Hello ")))
        XCTAssertTrue(children.contains(.strong(children: [.text("bold")])))
        XCTAssertTrue(children.contains(.emphasis(children: [.text("em")])))
    }

    // MARK: - Block elements

    func test_codeBlock_withLanguage() {
        let md = "```swift\nlet x = 1\n```"
        let result = parse(markdown: md)
        guard case .codeBlock(let language, let code, _) = result.nodes.first else {
            return XCTFail("Expected codeBlock")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1\n")
    }

    func test_codeBlock_noLanguage() {
        let md = "```\nraw code\n```"
        let result = parse(markdown: md)
        guard case .codeBlock(let language, _, _) = result.nodes.first else {
            return XCTFail("Expected codeBlock")
        }
        XCTAssertNil(language)
    }

    func test_blockquote() {
        let result = parse(markdown: "> This is a quote")
        guard case .blockquote(let children, _) = result.nodes.first else {
            return XCTFail("Expected blockquote")
        }
        XCTAssertFalse(children.isEmpty)
    }

    func test_horizontalRule() {
        let result = parse(markdown: "---")
        guard case .horizontalRule = result.nodes.first else {
            return XCTFail("Expected horizontalRule")
        }
    }

    // MARK: - Lists

    func test_unorderedList() {
        let md = "- item 1\n- item 2\n- item 3"
        let result = parse(markdown: md)
        guard case .unorderedList(let items, _, _) = result.nodes.first else {
            return XCTFail("Expected unorderedList")
        }
        XCTAssertEqual(items.count, 3)
    }

    func test_orderedList_defaultStart() {
        let md = "1. First\n2. Second"
        let result = parse(markdown: md)
        guard case .orderedList(let start, let items, _, _) = result.nodes.first else {
            return XCTFail("Expected orderedList")
        }
        XCTAssertEqual(start, 1)
        XCTAssertEqual(items.count, 2)
    }

    // MARK: - Link & image

    func test_link() {
        let result = parse(markdown: "[label](https://example.com)")
        guard case .paragraph(let children, _) = result.nodes.first,
              case .link(let url, _, let linkChildren) = children.first else {
            return XCTFail("Expected link")
        }
        XCTAssertEqual(url, "https://example.com")
        XCTAssertEqual(linkChildren, [.text("label")])
    }

    func test_image() {
        let result = parse(markdown: "![alt text](image.png)")
        guard case .paragraph(let children, _) = result.nodes.first,
              case .image(let url, let alt) = children.first else {
            return XCTFail("Expected image")
        }
        XCTAssertEqual(url, "image.png")
        XCTAssertEqual(alt, "alt text")
    }

    // MARK: - Multi-block document

    func test_multiBlock_preservesOrder() {
        let md = """
        # Title

        A paragraph.

        - item
        """
        let result = parse(markdown: md)
        XCTAssertEqual(result.nodes.count, 3)
        guard case .heading  = result.nodes[0] else { return XCTFail("Expected heading at [0]") }
        guard case .paragraph = result.nodes[1] else { return XCTFail("Expected paragraph at [1]") }
        guard case .unorderedList = result.nodes[2] else { return XCTFail("Expected list at [2]") }
    }

    // MARK: - Source span

    func test_sourceSpan_heading() {
        let result = parse(markdown: "# Title")
        guard case .heading(_, _, let span) = result.nodes.first else {
            return XCTFail()
        }
        XCTAssertFalse(span.isUnknown)
        XCTAssertEqual(span.startLine, 1)
    }

    func test_sourceSpan_multiLine() {
        let md = "# H1\n\n## H2"
        let result = parse(markdown: md)
        guard case .heading(_, _, let span1) = result.nodes[0],
              case .heading(_, _, let span2) = result.nodes[1] else {
            return XCTFail()
        }
        XCTAssertLessThan(span1.startLine, span2.startLine)
    }

    // MARK: - ParseResult helpers

    func test_blockContainingLine() {
        let md = "# Title\n\nParagraph"
        let result = parse(markdown: md)
        let block = result.block(containingLine: 1)
        guard case .heading = block else {
            return XCTFail("Line 1 should be in heading")
        }
    }

    func test_lineAlignedRange_forHeadingIncludesTrailingNewline() {
        let md = "# Title\nParagraph"
        let result = parse(markdown: md)
        guard case .heading(_, _, let span) = result.nodes.first,
              let range = lineAlignedRange(for: span, in: md, includeTrailingNewline: true) else {
            return XCTFail("Expected heading span")
        }

        let text = (md as NSString).substring(with: range)
        XCTAssertEqual(text, "# Title\n")
    }

    func test_currentLineRange_forEmptySecondLine() {
        let md = "# Title\n"
        let range = currentLineRange(containing: md.utf16.count, in: md)
        XCTAssertEqual(range.location, md.utf16.count)
        XCTAssertEqual(range.length, 0)
    }

    // MARK: - Incremental parser

    func test_dirtyBlockRange_singleBlock() {
        let text = "Hello world"
        let range = dirtyBlockRange(around: NSRange(location: 5, length: 1), in: text)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, text.utf16.count)
    }

    func test_dirtyBlockRange_multiBlock() {
        let text = "Block A\n\nBlock B\n\nBlock C"
        // 편집이 "Block B" 안에서 발생
        let editLoc = (text as NSString).range(of: "Block B").location + 3
        let range = dirtyBlockRange(around: NSRange(location: editLoc, length: 0), in: text)
        let dirty = (text as NSString).substring(with: range)
        XCTAssertTrue(dirty.contains("Block B"), "Dirty range should contain edited block")
        XCTAssertFalse(dirty.contains("Block A"), "Dirty range should not include Block A")
        XCTAssertFalse(dirty.contains("Block C"), "Dirty range should not include Block C")
    }

    // MARK: - Edge cases

    func test_emptyString() {
        let result = parse(markdown: "")
        XCTAssertTrue(result.nodes.isEmpty)
    }

    func test_onlyWhitespace() {
        let result = parse(markdown: "   \n\n   ")
        // 빈 문서로 처리되어야 함
        XCTAssertTrue(result.nodes.isEmpty || result.nodes.allSatisfy {
            if case .paragraph(let children, _) = $0 {
                return children.isEmpty || children == [.text("")]
            }
            return true
        })
    }

    func test_koreanText() {
        let result = parse(markdown: "# 한글 제목\n\n본문 **굵은** 텍스트")
        XCTAssertEqual(result.nodes.count, 2)
        guard case .heading(1, let titleChildren, _) = result.nodes[0] else {
            return XCTFail()
        }
        XCTAssertEqual(titleChildren, [.text("한글 제목")])
    }
}
