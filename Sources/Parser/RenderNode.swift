/// RenderNode — 마크다운 AST를 렌더러가 소비하는 값 타입으로 표현.
/// AppKit/Foundation UI 의존성 없음. 순수 Swift.
///
/// 설계 원칙:
///   - Block/Inline 두 레벨로 분리 (CommonMark 구조 반영)
///   - sourceRange: 증분 파싱 및 커서 블록 판별에 사용
///   - Equatable: 이전 parse 결과와 diff 비교 가능

// MARK: - Block level

indirect enum BlockNode: Equatable, Sendable {
    case heading(level: Int, children: [InlineNode], sourceRange: SourceSpan)
    case paragraph(children: [InlineNode], sourceRange: SourceSpan)
    case blockquote(children: [BlockNode], sourceRange: SourceSpan)
    case codeBlock(language: String?, code: String, sourceRange: SourceSpan)
    case unorderedList(items: [ListItemNode], isTight: Bool, sourceRange: SourceSpan)
    case orderedList(start: Int, items: [ListItemNode], isTight: Bool, sourceRange: SourceSpan)
    case horizontalRule(sourceRange: SourceSpan)
    case htmlBlock(raw: String, sourceRange: SourceSpan)
    /// YAML frontmatter (`---` 블록). swift-markdown이 처리하지 않으므로 Parser에서 전처리.
    case frontmatter(content: String, sourceRange: SourceSpan)
    /// GitHub-style 표.
    case table(headers: [String], alignments: [ColumnAlignment], rows: [[String]], sourceRange: SourceSpan)

    var sourceRange: SourceSpan {
        switch self {
        case .heading(_, _, let r):          return r
        case .paragraph(_, let r):           return r
        case .blockquote(_, let r):          return r
        case .codeBlock(_, _, let r):        return r
        case .unorderedList(_, _, let r):    return r
        case .orderedList(_, _, _, let r):   return r
        case .horizontalRule(let r):         return r
        case .htmlBlock(_, let r):           return r
        case .frontmatter(_, let r):         return r
        case .table(_, _, _, let r):         return r
        }
    }
}

// MARK: - Table column alignment

enum ColumnAlignment: Equatable, Sendable {
    case left, center, right, none
}

// MARK: - List item

struct ListItemNode: Equatable, Sendable {
    let children: [BlockNode]
    let sourceRange: SourceSpan
}

// MARK: - Inline level

indirect enum InlineNode: Equatable, Sendable {
    case text(String)
    case softBreak
    case hardBreak
    case strong(children: [InlineNode])
    case emphasis(children: [InlineNode])
    case strikethrough(children: [InlineNode])
    case inlineCode(String)
    case link(url: String, title: String?, children: [InlineNode])
    case image(url: String, alt: String)
    case htmlInline(String)
}

// MARK: - Source span (줄/열 기반, swift-markdown과 호환)

struct SourceSpan: Equatable, Sendable {
    let startLine:   Int  // 1-based
    let startColumn: Int  // 1-based
    let endLine:     Int
    let endColumn:   Int

    static let unknown = SourceSpan(startLine: 0, startColumn: 0, endLine: 0, endColumn: 0)

    var isUnknown: Bool { startLine == 0 }
}

// MARK: - Parse result

struct ParseResult: Equatable, Sendable {
    let nodes: [BlockNode]
    let sourceText: String

    /// 특정 줄을 포함하는 BlockNode 반환 (커서 블록 판별용)
    func block(containingLine line: Int) -> BlockNode? {
        nodes.first { node in
            let span = node.sourceRange
            return !span.isUnknown && span.startLine <= line && line <= span.endLine
        }
    }
}
