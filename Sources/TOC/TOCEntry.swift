import Foundation

// MARK: - Data Model

struct TOCEntry: Equatable {
    let level:           Int    // 1–6
    let title:           String // 헤딩 plain text
    let characterOffset: Int    // NSTextStorage 내 UTF-16 오프셋 (헤딩 줄 시작)
}

// MARK: - ParseResult → [TOCEntry] (순수 함수)

func extractTOCEntries(from result: ParseResult) -> [TOCEntry] {
    result.nodes.compactMap { node -> TOCEntry? in
        guard case .heading(let level, let children, let span) = node,
              !span.isUnknown
        else { return nil }

        let title  = children.map { plainText(from: $0) }.joined()
        let offset = utf16LineStartOffset(line: span.startLine, in: result.sourceText)
        return TOCEntry(level: level, title: title, characterOffset: offset)
    }
}

// MARK: - Helpers (순수 함수)

/// InlineNode → plain text (마크다운 기호 제거)
private func plainText(from node: InlineNode) -> String {
    switch node {
    case .text(let s):              return s
    case .inlineCode(let s):        return s
    case .strong(let c):            return c.map { plainText(from: $0) }.joined()
    case .emphasis(let c):          return c.map { plainText(from: $0) }.joined()
    case .strikethrough(let c):     return c.map { plainText(from: $0) }.joined()
    case .link(_, _, let c):        return c.map { plainText(from: $0) }.joined()
    case .image(_, let alt):        return alt
    case .softBreak, .hardBreak:    return " "
    case .htmlInline:               return ""
    }
}

/// 1-based 줄 번호 → UTF-16 오프셋 (줄 시작 위치)
private func utf16LineStartOffset(line: Int, in text: String) -> Int {
    guard line > 1 else { return 0 }
    var current = 1
    var offset  = 0
    for unit in text.utf16 {
        if current == line { break }
        if unit == 0x0A { current += 1 }  // '\n'
        offset += 1
    }
    return offset
}
