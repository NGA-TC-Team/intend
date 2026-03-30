import Markdown

// MARK: - Entry point (순수 함수)

/// String → ParseResult 변환. 외부 상태 없음, 테스트 가능.
func parse(markdown: String) -> ParseResult {
    // 1. Frontmatter 전처리 (swift-markdown이 처리하지 못함)
    var leadingNodes: [BlockNode] = []
    var fmEndLine = 0  // frontmatter가 끝나는 줄 번호 (1-based)

    if let fm = extractFrontmatter(markdown) {
        leadingNodes.append(fm.node)
        fmEndLine = fm.endLine
    }

    // 2. swift-markdown 파싱
    let document = Document(parsing: markdown)
    var visitor  = RenderNodeVisitor()
    visitor.visitDocument(document)

    // 3. frontmatter 범위와 겹치는 노드 제거 (swift-markdown이 frontmatter를 paragraph로 파싱)
    let filteredNodes = visitor.blockNodes.filter { node in
        node.sourceRange.startLine > fmEndLine
    }

    return ParseResult(nodes: leadingNodes + filteredNodes, sourceText: markdown)
}

// MARK: - Frontmatter 전처리

private struct FrontmatterResult {
    let node: BlockNode
    let endLine: Int  // frontmatter 마지막 줄 번호 (1-based, 닫힘 `---` 포함)
}

private func extractFrontmatter(_ text: String) -> FrontmatterResult? {
    // 문서가 `---\n` 으로 시작해야 함
    guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return nil }

    // 줄 분리 후 닫힘 `---` 탐색 (첫 줄 이후부터)
    let lines = text.components(separatedBy: "\n")
    guard lines.count >= 3 else { return nil }

    var closeIdx: Int? = nil
    for i in 1 ..< lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "..." {
            closeIdx = i
            break
        }
    }
    guard let closeIdx else { return nil }

    // frontmatter 콘텐츠 (열기 --- 와 닫기 --- 사이 줄들)
    let content = lines[1 ..< closeIdx].joined(separator: "\n")

    // SourceSpan: 열기 줄(1) ~ 닫기 줄(closeIdx + 1, 1-based)
    let endLine = closeIdx + 1
    let span = SourceSpan(startLine: 1, startColumn: 1, endLine: endLine, endColumn: 3)

    return FrontmatterResult(
        node: .frontmatter(content: content, sourceRange: span),
        endLine: endLine
    )
}

// MARK: - Visitor

/// swift-markdown MarkupVisitor를 구현해 AST → [BlockNode] 변환.
private struct RenderNodeVisitor: MarkupVisitor {

    var blockNodes: [BlockNode] = []

    // MARK: - Block visitors

    mutating func visitDocument(_ document: Document) {
        document.children.forEach { visit($0) }
    }

    mutating func visitHeading(_ heading: Heading) -> () {
        let children = inlineNodes(from: heading)
        let span     = sourceSpan(of: heading)
        blockNodes.append(.heading(level: heading.level, children: children, sourceRange: span))
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        let children = inlineNodes(from: paragraph)
        let span     = sourceSpan(of: paragraph)
        blockNodes.append(.paragraph(children: children, sourceRange: span))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        var inner = RenderNodeVisitor()
        blockQuote.children.forEach { inner.visit($0) }
        blockNodes.append(.blockquote(children: inner.blockNodes, sourceRange: sourceSpan(of: blockQuote)))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        blockNodes.append(.codeBlock(
            language: codeBlock.language.flatMap { $0.isEmpty ? nil : $0 },
            code: codeBlock.code,
            sourceRange: sourceSpan(of: codeBlock)
        ))
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> () {
        let items = Array(list.listItems.map(convertListItem))
        blockNodes.append(.unorderedList(items: items, isTight: false, sourceRange: sourceSpan(of: list)))
    }

    mutating func visitOrderedList(_ list: OrderedList) -> () {
        let items = Array(list.listItems.map(convertListItem))
        blockNodes.append(.orderedList(
            start: Int(list.startIndex),
            items: items,
            isTight: false,
            sourceRange: sourceSpan(of: list)
        ))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        blockNodes.append(.horizontalRule(sourceRange: sourceSpan(of: thematicBreak)))
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> () {
        blockNodes.append(.htmlBlock(raw: html.rawHTML, sourceRange: sourceSpan(of: html)))
    }

    mutating func visitTable(_ table: Table) -> () {
        // 헤더 행
        let headers = Array(table.head.cells.map(\.plainText))

        // 열 정렬
        let alignments: [ColumnAlignment] = table.columnAlignments.map { align in
            switch align {
            case .left:   return .left
            case .center: return .center
            case .right:  return .right
            default:      return .none
            }
        }

        // 데이터 행
        let rows: [[String]] = table.body.rows.map { row in
            Array(row.cells.map(\.plainText))
        }

        blockNodes.append(.table(
            headers: headers,
            alignments: alignments,
            rows: rows,
            sourceRange: sourceSpan(of: table)
        ))
    }

    // 기본 구현 — 미지원 노드는 무시
    mutating func defaultVisit(_ markup: any Markup) -> () {}

    // MARK: - Helpers

    private func inlineNodes(from markup: any Markup) -> [InlineNode] {
        markup.children.flatMap(convertInline)
    }

    private func convertInline(_ markup: any Markup) -> [InlineNode] {
        switch markup {
        case let text as Markdown.Text:
            return [.text(text.string)]
        case let strong as Strong:
            return [.strong(children: inlineNodes(from: strong))]
        case let em as Emphasis:
            return [.emphasis(children: inlineNodes(from: em))]
        case let code as InlineCode:
            return [.inlineCode(code.code)]
        case let link as Markdown.Link:
            return [.link(
                url: link.destination ?? "",
                title: link.title,
                children: inlineNodes(from: link)
            )]
        case let image as Markdown.Image:
            return [.image(
                url: image.source ?? "",
                alt: image.plainText
            )]
        case is SoftBreak:
            return [.softBreak]
        case is LineBreak:
            return [.hardBreak]
        case let html as InlineHTML:
            return [.htmlInline(html.rawHTML)]
        case let strikethrough as Strikethrough:
            return [.strikethrough(children: inlineNodes(from: strikethrough))]
        default:
            // 미지원 인라인 → 플레인 텍스트로 fallback
            let text = markup.children.compactMap { $0 as? Markdown.Text }.map(\.string).joined()
            return text.isEmpty ? [] : [.text(text)]
        }
    }

    private func convertListItem(_ item: ListItem) -> ListItemNode {
        var inner = RenderNodeVisitor()
        item.children.forEach { inner.visit($0) }
        return ListItemNode(children: inner.blockNodes, sourceRange: sourceSpan(of: item))
    }

    private func sourceSpan(of markup: any Markup) -> SourceSpan {
        guard let range = markup.range else { return .unknown }
        return SourceSpan(
            startLine:   range.lowerBound.line,
            startColumn: range.lowerBound.column,
            endLine:     range.upperBound.line,
            endColumn:   range.upperBound.column
        )
    }
}
