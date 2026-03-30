import AppKit

// MARK: - Custom attribute keys

/// 표 행 전체 너비 배경색 (MarkdownTextView.drawBackground에서 full-width 드로잉에 사용).
/// NSAttributedString.Key.backgroundColor 대신 이 키를 쓰면 배경이 에디터 전체 폭을 채운다.
extension NSAttributedString.Key {
    static let tableRowBackground = NSAttributedString.Key("com.intend.tableRowBackground")
    /// HR(수평 구분선) 색상. MarkdownTextView.drawBackground에서 줄 중앙에 1pt 실선으로 그림.
    static let hrLineColor        = NSAttributedString.Key("com.intend.hrLineColor")
}

// MARK: - Rendering output

/// 특정 NSRange에 적용할 속성 묶음.
/// NSFont/NSColor 등 AppKit 클래스를 담으므로 Sendable 불가.
/// 항상 메인 스레드에서만 사용.
struct AttributePatch {
    let range:  NSRange
    let attrs:  [NSAttributedString.Key: Any]
}

// MARK: - Renderer (순수 함수)

/// ParseResult + AppConfig → [AttributePatch]
/// AppKit 의존성 있음 (NSFont, NSColor), 하지만 사이드 이펙트 없음.
func renderAttributes(
    from result: ParseResult,
    config: AppConfig,
    theme: ThemeManager
) -> [AttributePatch] {
    let ctx = RenderContext(config: config, theme: theme, text: result.sourceText)
    return result.nodes.flatMap { renderBlock($0, ctx: ctx) }
}

// MARK: - Block rendering

private func renderBlock(_ node: BlockNode, ctx: RenderContext) -> [AttributePatch] {
    switch node {
    case .heading(let level, let children, let span):
        return renderHeading(level: level, children: children, span: span, ctx: ctx)

    case .paragraph(let children, let span):
        return renderParagraph(children: children, span: span, ctx: ctx)

    case .blockquote(let children, let span):
        return renderBlockquote(children: children, span: span, ctx: ctx)

    case .codeBlock(let language, let code, let span):
        return renderCodeBlock(language: language, code: code, span: span, ctx: ctx)

    case .unorderedList(let items, _, let span):
        return renderList(items: items, ordered: false, startIndex: 1, span: span, ctx: ctx)

    case .orderedList(let start, let items, _, let span):
        return renderList(items: items, ordered: true, startIndex: start, span: span, ctx: ctx)

    case .horizontalRule(let span):
        return renderHorizontalRule(span: span, ctx: ctx)

    case .htmlBlock(_, _):
        return []

    case .frontmatter(let content, let span):
        return renderFrontmatter(content: content, span: span, ctx: ctx)

    case .table(let headers, let alignments, let rows, let span):
        return renderTable(headers: headers, alignments: alignments, rows: rows, span: span, ctx: ctx)
    }
}

// MARK: - Block type implementations

private func renderHeading(
    level: Int,
    children: [InlineNode],
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    guard !span.isUnknown, let nsRange = nsRange(for: span, in: ctx.text) else { return [] }

    let style     = ctx.config.rendering.headingStyle(level: level)
    let fontSize  = ctx.config.editor.font.size * style.scale
    let weight: NSFont.Weight = {
        switch style.weight {
        case "bold":     return .bold
        case "semibold": return .semibold
        case "medium":   return .medium
        default:         return .regular
        }
    }()

    let font  = ctx.fontDerived(from: ctx.bodyFont, size: fontSize, weight: weight)
    let color = style.color.flatMap(NSColor.init(hex:)) ?? ctx.theme.foregroundColor

    let paraStyle = NSMutableParagraphStyle()
    paraStyle.paragraphSpacingBefore = level == 1 ? 10 : 8
    paraStyle.paragraphSpacing = max(3, ctx.config.editor.font.size * 0.25)
    paraStyle.lineHeightMultiple = 1.25

    let patchRange = lineAlignedRange(for: span, in: ctx.text, includeTrailingNewline: true) ?? nsRange

    var patches: [AttributePatch] = [
        AttributePatch(range: patchRange, attrs: [
            .font:            font,
            .foregroundColor: color,
            .paragraphStyle:  paraStyle
        ])
    ]

    // trailing \n은 heading font 대신 body font로 덮어씌움.
    // \n 다음 줄에서 typing attributes가 heading 폰트(큰 크기)를 상속하면
    // IME 조합 중 applyAttributes()가 스킵되어 body text가 heading 크기로 보이는 버그 방지.
    // paragraphStyle(단락 간격)은 그대로 유지되므로 시각적 레이아웃에 영향 없음.
    if patchRange.length > nsRange.length {
        let nlRange = NSRange(location: NSMaxRange(nsRange), length: 1)
        patches.append(AttributePatch(range: nlRange, attrs: [
            .font:            ctx.bodyFont,
            .foregroundColor: ctx.theme.foregroundColor
        ]))
    }

    // # 토큰 완전히 숨김 + 공간 제거 (level + 1 글자: "## ")
    // font size 0.01 → 글리프 너비가 사실상 0. foregroundColor .clear로 완전 투명.
    let tokenLen = min(level + 1, nsRange.length)
    if tokenLen > 0 {
        let zeroFont = NSFont(name: ctx.bodyFont.fontName, size: 0.01)
            ?? NSFont.systemFont(ofSize: 0.01)
        patches.append(AttributePatch(
            range: NSRange(location: nsRange.location, length: tokenLen),
            attrs: [
                .foregroundColor: NSColor.clear,
                .font: zeroFont,
            ]
        ))
    }

    // 인라인 속성 (헤딩 안의 bold/italic 등)
    patches += renderInlines(children, baseRange: nsRange, ctx: ctx)
    return patches
}

private func renderParagraph(
    children: [InlineNode],
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    guard !span.isUnknown, let nsRange = nsRange(for: span, in: ctx.text) else { return [] }

    let paraStyle = NSMutableParagraphStyle()
    paraStyle.lineHeightMultiple = ctx.config.rendering.paragraph.lineHeight
    paraStyle.paragraphSpacing = 0

    var patches: [AttributePatch] = [
        AttributePatch(range: nsRange, attrs: [
            .font:           ctx.bodyFont,
            .foregroundColor: ctx.theme.foregroundColor,
            .paragraphStyle:  paraStyle
        ])
    ]
    patches += renderInlines(children, baseRange: nsRange, ctx: ctx)
    return patches
}

private func renderBlockquote(
    children: [BlockNode],
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    guard !span.isUnknown,
          let nsRange = lineAlignedRange(for: span, in: ctx.text, includeTrailingNewline: true) else { return [] }

    let bqConfig = ctx.config.rendering.blockquote
    let borderColor = bqConfig.borderColor.flatMap(NSColor.init(hex:))
                   ?? ctx.theme.foregroundColor.withAlphaComponent(0.35)
    let bgColor = bqConfig.backgroundColor.flatMap(NSColor.init(hex:))
               ?? ctx.theme.foregroundColor.withAlphaComponent(0.05)

    // 왼쪽 vertical bar 구현:
    // headIndent / firstLineHeadIndent 으로 본문을 오른쪽으로 밀고,
    // NSTextBlock을 이용한 배경 + 커스텀 border 대신 실용적 대안으로
    // '>' 글리프를 clear 처리하고 paragraphSpacingBefore / After 로 여백 확보.
    let paraStyle = NSMutableParagraphStyle()
    paraStyle.headIndent          = 18
    paraStyle.firstLineHeadIndent = 18
    paraStyle.paragraphSpacingBefore = 2
    paraStyle.paragraphSpacing       = 2

    var patches: [AttributePatch] = [
        AttributePatch(range: nsRange, attrs: [
            .foregroundColor: ctx.theme.foregroundColor.withAlphaComponent(0.75),
            .paragraphStyle:  paraStyle,
            .backgroundColor: bgColor,
        ])
    ]

    // `>` 문자를 borderColor 로 착색해 세로 바처럼 보이도록 함.
    // headIndent(18pt)로 본문이 들여쓰기되어 `>` 다음 내용과 분리됨.
    patches.append(AttributePatch(
        range: NSRange(location: nsRange.location, length: min(1, nsRange.length)),
        attrs: [
            .foregroundColor: borderColor,
            .font: NSFont.boldSystemFont(ofSize: ctx.config.editor.font.size),
        ]
    ))

    patches += children.flatMap { renderBlock($0, ctx: ctx) }
    return patches
}

private func renderCodeBlock(
    language: String?,
    code: String,
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    guard !span.isUnknown,
          let nsRange = lineAlignedRange(for: span, in: ctx.text, includeTrailingNewline: true) else { return [] }

    let cbConfig = ctx.config.rendering.codeBlock
    let monoFont = NSFont(name: cbConfig.font, size: cbConfig.fontSize)
               ?? NSFont.monospacedSystemFont(ofSize: cbConfig.fontSize, weight: .regular)
    let bgColor  = cbConfig.backgroundColor.flatMap(NSColor.init(hex:))
               ?? ctx.theme.foregroundColor.withAlphaComponent(0.05)

    let paraStyle = NSMutableParagraphStyle()
    paraStyle.lineHeightMultiple = 1.35
    paraStyle.paragraphSpacingBefore = 6
    paraStyle.paragraphSpacing = 6

    var patches: [AttributePatch] = [
        AttributePatch(range: nsRange, attrs: [
            .font: monoFont,
            .foregroundColor: ctx.theme.foregroundColor,
            .backgroundColor: bgColor,
            .paragraphStyle: paraStyle
        ])
    ]

    // 줄 단위로 delimiter 처리
    let lines   = ctx.text.components(separatedBy: "\n")
    let textLen = (ctx.text as NSString).length
    var offset  = 0

    for (i, line) in lines.enumerated() {
        let lineLen = (line as NSString).length
        let lineNum = i + 1

        defer { offset += lineLen + 1 }
        guard lineNum >= span.startLine, lineNum <= span.endLine else { continue }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if lineNum == span.startLine {
            // 열기 행: ``` + 언어 식별자
            // ``` 자체 (첫 3자): clear
            let tickLen = min(3, lineLen)
            let tickRange = NSRange(location: offset, length: tickLen)
            if NSMaxRange(tickRange) <= textLen {
                patches.append(AttributePatch(range: tickRange, attrs: [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.01)
                ]))
            }
            // 언어 식별자 (``` 이후): 파란색 소문자 label
            if let lang = language, !lang.isEmpty {
                let langStart = offset + tickLen
                let langLen   = lineLen - tickLen
                if langLen > 0, langStart + langLen <= textLen {
                    patches.append(AttributePatch(
                        range: NSRange(location: langStart, length: langLen),
                        attrs: [
                            .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.7),
                            .font: NSFont.systemFont(ofSize: cbConfig.fontSize - 1)
                        ]
                    ))
                }
            } else if lineLen > 3 {
                // 언어 없이 추가 텍스트가 있으면 clear
                let restRange = NSRange(location: offset + tickLen, length: lineLen - tickLen)
                if NSMaxRange(restRange) <= textLen {
                    patches.append(AttributePatch(range: restRange, attrs: [.foregroundColor: NSColor.clear]))
                }
            }

        } else if lineNum == span.endLine {
            // 닫기 행: ``` → clear
            if trimmed.hasPrefix("```") {
                let closeRange = NSRange(location: offset, length: min(3, textLen - offset))
                if closeRange.length > 0, NSMaxRange(closeRange) <= textLen {
                    patches.append(AttributePatch(range: closeRange, attrs: [
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.systemFont(ofSize: 0.01)
                    ]))
                }
            }

        } else {
            // 코드 콘텐츠 행: 문법 하이라이트
            if let lang = language, !lang.isEmpty, lineLen > 0 {
                let codeLineRange = NSRange(location: offset, length: min(lineLen, textLen - offset))
                if codeLineRange.length > 0, NSMaxRange(codeLineRange) <= textLen {
                    let tokens = syntaxHighlight(code: line, language: lang)
                    for token in tokens {
                        let absRange = NSRange(location: offset + token.range.location,
                                               length: token.range.length)
                        guard NSMaxRange(absRange) <= textLen else { continue }
                        patches.append(AttributePatch(range: absRange, attrs: [
                            .foregroundColor: token.color
                        ]))
                    }
                }
            }
        }
    }

    return patches
}

private func renderHorizontalRule(span: SourceSpan, ctx: RenderContext) -> [AttributePatch] {
    guard !span.isUnknown,
          let hrRange = lineAlignedRange(for: span, in: ctx.text, includeTrailingNewline: true) else { return [] }

    // `---` 텍스트를 숨기고, 위아래 여백 확보 후 중앙에 1pt 실선을 그림.
    // backgroundColor는 paragraph spacing까지 채워 두껍게 보이므로 사용하지 않음.
    // 대신 hrLineColor custom attribute를 MarkdownTextView.drawBackground에서 처리.
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight      = 20   // 위아래 여백을 포함한 전체 행 높이
    style.maximumLineHeight      = 20
    style.paragraphSpacingBefore = 0
    style.paragraphSpacing       = 0

    return [AttributePatch(range: hrRange, attrs: [
        .foregroundColor: NSColor.clear,
        .hrLineColor:     NSColor.separatorColor,
        .paragraphStyle:  style,
        .font:            NSFont.systemFont(ofSize: 0.01)
    ])]
}

// MARK: - Frontmatter

private func renderFrontmatter(
    content: String,
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    guard !span.isUnknown,
          let fmRange = lineAlignedRange(for: span, in: ctx.text, includeTrailingNewline: true) else { return [] }
    let textLen = (ctx.text as NSString).length

    let isDark = ctx.theme.isDark
    let bgColor: NSColor = isDark
        ? NSColor.systemOrange.withAlphaComponent(0.07)
        : NSColor.systemYellow.withAlphaComponent(0.09)

    var patches: [AttributePatch] = [
        AttributePatch(range: fmRange, attrs: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .backgroundColor: bgColor
        ])
    ]

    // 열기/닫기 `---` 행 흐리게
    let lines      = ctx.text.components(separatedBy: "\n")
    var lineOffset = 0
    for (i, line) in lines.enumerated() {
        let lineLen = (line as NSString).length
        let lineRange = NSRange(location: lineOffset, length: lineLen)

        // span 범위 내 줄만 처리
        let lineNum = i + 1  // 1-based
        if lineNum < span.startLine || lineNum > span.endLine {
            lineOffset += lineLen + 1; continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed == "---" || trimmed == "..." {
            patches.append(AttributePatch(range: lineRange, attrs: [
                .foregroundColor: ctx.theme.syntaxTokenColor
            ]))
        } else if line.contains(":") {
            // 키: 값 행 — `:` 기준으로 분리
            let ns   = line as NSString
            let cIdx = ns.range(of: ":").location
            if cIdx != NSNotFound {
                let keyRange = NSRange(location: lineOffset, length: cIdx)
                let valRange = NSRange(location: lineOffset + cIdx + 1,
                                      length: lineLen - cIdx - 1)
                if keyRange.length > 0 {
                    patches.append(AttributePatch(range: keyRange, attrs: [
                        .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.85)
                    ]))
                }
                if valRange.length > 0, NSMaxRange(valRange) <= textLen {
                    patches.append(AttributePatch(range: valRange, attrs: [
                        .foregroundColor: NSColor.systemGreen.withAlphaComponent(0.85)
                    ]))
                }
            }
        }
        lineOffset += lineLen + 1
    }

    return patches
}

// MARK: - Table

private func renderTable(
    headers: [String],
    alignments: [ColumnAlignment],
    rows: [[String]],
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    guard !span.isUnknown,
          let nsRange = lineAlignedRange(for: span, in: ctx.text, includeTrailingNewline: true) else { return [] }

    // 표 텍스트를 투명으로 처리 — TableOverlayView가 위에서 렌더링.
    // 커서가 표 안에 있으면 filteredPatches가 이 패치를 억제 → 원본 텍스트가 보여 편집 가능.
    //
    // 각 행의 line height는 오버레이 높이와 정확히 일치해야 위치가 맞음:
    //   - 헤더/데이터 행: ceil(fontSize * 1.75)
    //   - 구분선 행 (|---|): 1pt (오버레이의 구분선과 동일)
    let fontSize = ctx.config.editor.font.size
    let rowH     = ceil(fontSize * 1.75)
    let textLen  = (ctx.text as NSString).length

    let rowStyle = NSMutableParagraphStyle()
    rowStyle.minimumLineHeight    = rowH
    rowStyle.maximumLineHeight    = rowH
    rowStyle.paragraphSpacing     = 0
    rowStyle.paragraphSpacingBefore = 0

    let sepStyle = NSMutableParagraphStyle()
    sepStyle.minimumLineHeight    = 1
    sepStyle.maximumLineHeight    = 1
    sepStyle.paragraphSpacing     = 0
    sepStyle.paragraphSpacingBefore = 0

    let bodyFont = NSFont.systemFont(ofSize: fontSize)
    let tinyFont = NSFont.systemFont(ofSize: 0.01)

    var patches: [AttributePatch] = []
    let lines = ctx.text.components(separatedBy: "\n")
    var lineOffset = 0
    var rowIndex   = 0  // 0=헤더, 1=구분선, 2+=데이터

    for (i, line) in lines.enumerated() {
        let lineLen = (line as NSString).length
        let lineNum = i + 1
        if lineNum < span.startLine || lineNum > span.endLine {
            lineOffset += lineLen + 1; continue
        }
        guard lineOffset + lineLen <= textLen else { lineOffset += lineLen + 1; continue }

        let lineRange = NSRange(location: lineOffset, length: lineLen)

        if rowIndex == 1 {
            // 구분선 행 → 1pt 고정 (오버레이의 header-data 구분선과 높이 동기화)
            patches.append(AttributePatch(range: lineRange, attrs: [
                .foregroundColor: NSColor.clear,
                .font:            tinyFont,
                .paragraphStyle:  sepStyle
            ]))
        } else {
            // 헤더 & 데이터 행 → rowH 고정, 투명
            patches.append(AttributePatch(range: lineRange, attrs: [
                .foregroundColor: NSColor.clear,
                .font:            bodyFont,
                .paragraphStyle:  rowStyle
            ]))
        }

        lineOffset += lineLen + 1
        rowIndex   += 1
    }

    return patches
}

private func renderList(
    items: [ListItemNode],
    ordered: Bool,
    startIndex: Int,
    span: SourceSpan,
    ctx: RenderContext
) -> [AttributePatch] {
    items.enumerated().flatMap { index, item -> [AttributePatch] in
        var patches = item.children.flatMap { renderBlock($0, ctx: ctx) }

        guard !item.sourceRange.isUnknown,
              let itemRange = lineAlignedRange(for: item.sourceRange, in: ctx.text),
              itemRange.length > 0 else {
            return patches
        }

        if !ordered {
            // unordered: `*`, `-`, `+` 마커를 • 글리프로 교체.
            // NSGlyphInfo 를 이용해 backing store 를 바꾸지 않고 화면 글리프만 교체.
            // baseString 은 backing store 의 실제 문자와 일치해야 함.
            let markerRange = NSRange(location: itemRange.location, length: 1)
            let markerChar  = (ctx.text as NSString).length > itemRange.location
                ? (ctx.text as NSString).substring(with: markerRange)
                : "*"
            // 시스템 폰트 사용 — "bullet" PostScript 글리프가 반드시 존재함.
            let bulletFont = NSFont.systemFont(ofSize: ctx.config.editor.font.size)
            if let glyphInfo = NSGlyphInfo(glyphName: "bullet", for: bulletFont, baseString: markerChar) {
                patches.append(AttributePatch(
                    range: markerRange,
                    attrs: [
                        .glyphInfo:       glyphInfo,
                        .font:            bulletFont,
                        .foregroundColor: ctx.theme.foregroundColor,
                    ]
                ))
            }
        } else {
            // ordered: `1.` 마커 흐리게
            let dotIdx = (ctx.text as NSString)
                .range(of: ".", range: NSRange(location: itemRange.location,
                                               length: min(4, itemRange.length)))
            if dotIdx.location != NSNotFound {
                let markerRange = NSRange(location: itemRange.location,
                                         length: dotIdx.location - itemRange.location + 1)
                patches.append(AttributePatch(
                    range: markerRange,
                    attrs: [.foregroundColor: ctx.theme.syntaxTokenColor]
                ))
            }
        }

        // 목록 들여쓰기 + 항목 간 여백
        let indent = ctx.config.rendering.list.indentWidth
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.headIndent            = indent
        paraStyle.firstLineHeadIndent   = indent
        paraStyle.paragraphSpacing      = ctx.config.editor.font.size * 0.25   // 약 4pt (16px 기준)
        paraStyle.paragraphSpacingBefore = 0
        patches.append(AttributePatch(range: itemRange, attrs: [.paragraphStyle: paraStyle]))

        return patches
    }
}

// MARK: - Inline rendering

private func renderInlines(
    _ nodes: [InlineNode],
    baseRange: NSRange,
    ctx: RenderContext
) -> [AttributePatch] {
    _ = nodes
    var patches: [AttributePatch] = []
    let text = ctx.textInRange(baseRange)
    guard !text.isEmpty else { return [] }

    if text.contains("**") {
        patches += renderBoldInRange(text, offset: baseRange.location, ctx: ctx)
    }
    if text.contains("_") {
        patches += renderItalicInRange(text, offset: baseRange.location, ctx: ctx)
    }
    if text.contains("`") {
        patches += renderInlineCodeInRange(text, offset: baseRange.location, ctx: ctx)
    }
    if text.contains("](") {
        patches += renderLinkInRange(text, offset: baseRange.location, ctx: ctx)
    }

    return patches
}

private func renderBoldInRange(_ text: String, offset: Int, ctx: RenderContext) -> [AttributePatch] {
    collectRanges(pattern: /\*\*(.+?)\*\*/, in: text, offset: offset)
        .flatMap { (tokenRange, _) -> [AttributePatch] in
            let boldFont = NSFont.systemFont(ofSize: ctx.config.editor.font.size, weight: .bold)
            return [
                AttributePatch(range: tokenRange, attrs: [.font: boldFont]),
                // ** 토큰: 편집 블록 밖에서 완전히 숨김 (편집 블록 안에서는 filteredPatches가 스킵하므로 기본 색상으로 표시됨)
                AttributePatch(range: NSRange(location: tokenRange.location, length: 2),
                               attrs: [.foregroundColor: NSColor.clear]),
                AttributePatch(range: NSRange(location: NSMaxRange(tokenRange) - 2, length: 2),
                               attrs: [.foregroundColor: NSColor.clear])
            ]
        }
}

private func renderItalicInRange(_ text: String, offset: Int, ctx: RenderContext) -> [AttributePatch] {
    // _text_ 패턴 사용 (lookbehind 불필요, ** bold와 충돌 없음)
    collectRanges(pattern: /_([^_\n]+)_/, in: text, offset: offset)
        .flatMap { (tokenRange, _) -> [AttributePatch] in
            let descriptor = ctx.bodyFont.fontDescriptor.withSymbolicTraits(.italic)
            let italicFont = NSFont(descriptor: descriptor, size: ctx.config.editor.font.size)
                          ?? ctx.bodyFont
            return [
                AttributePatch(range: tokenRange, attrs: [.font: italicFont]),
                AttributePatch(range: NSRange(location: tokenRange.location, length: 1),
                               attrs: [.foregroundColor: ctx.theme.syntaxTokenColor]),
                AttributePatch(range: NSRange(location: NSMaxRange(tokenRange) - 1, length: 1),
                               attrs: [.foregroundColor: ctx.theme.syntaxTokenColor])
            ]
        }
}

private func renderInlineCodeInRange(_ text: String, offset: Int, ctx: RenderContext) -> [AttributePatch] {
    let icConfig = ctx.config.rendering.inlineCode
    let font = NSFont(name: icConfig.font, size: icConfig.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: icConfig.fontSize, weight: .regular)

    // Notion 스타일: 붉은 계열 텍스트 + 연한 핑크/베이지 배경.
    // 다크 모드 여부에 따라 색상 쌍 분기.
    let isDark = ctx.theme.isDark
    let textColor: NSColor = isDark
        ? NSColor(srgbRed: 0.93, green: 0.40, blue: 0.38, alpha: 1)   // 다크: 연한 코랄
        : NSColor(srgbRed: 0.82, green: 0.18, blue: 0.13, alpha: 1)   // 라이트: 노션 레드
    let bg: NSColor = icConfig.backgroundColor.flatMap(NSColor.init(hex:))
        ?? (isDark
            ? NSColor(srgbRed: 0.35, green: 0.14, blue: 0.13, alpha: 0.6)   // 다크 배경
            : NSColor(srgbRed: 0.98, green: 0.89, blue: 0.87, alpha: 1.0))  // 라이트 배경

    return collectRanges(pattern: /`([^`\n]+)`/, in: text, offset: offset)
        .flatMap { (tokenRange, _) -> [AttributePatch] in [
            // 전체 범위: 모노폰트 + 노션 텍스트 색 + 배경
            AttributePatch(range: tokenRange, attrs: [
                .font:            font,
                .foregroundColor: textColor,
                .backgroundColor: bg,
            ]),
            // 백틱 ` 흐리게
            AttributePatch(range: NSRange(location: tokenRange.location, length: 1),
                           attrs: [.foregroundColor: ctx.theme.syntaxTokenColor]),
            AttributePatch(range: NSRange(location: NSMaxRange(tokenRange) - 1, length: 1),
                           attrs: [.foregroundColor: ctx.theme.syntaxTokenColor]),
        ]}
}

private func renderLinkInRange(_ text: String, offset: Int, ctx: RenderContext) -> [AttributePatch] {
    let linkConfig = ctx.config.rendering.link
    let color = linkConfig.color.flatMap(NSColor.init(hex:)) ?? NSColor.linkColor

    return collectRanges(pattern: /\[(.+?)\]\((.+?)\)/, in: text, offset: offset)
        .map { (tokenRange, _) -> AttributePatch in
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if linkConfig.underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            return AttributePatch(range: tokenRange, attrs: attrs)
        }
}

// MARK: - Regex helper (순수 함수)

private func collectRanges<R: RegexComponent>(
    pattern: R,
    in text: String,
    offset: Int
) -> [(tokenRange: NSRange, contentRange: NSRange)] {
    text.matches(of: pattern).compactMap { match in
        guard let utf16Start = match.range.lowerBound.samePosition(in: text.utf16),
              let utf16End   = match.range.upperBound.samePosition(in: text.utf16) else {
            return nil
        }
        let start = text.utf16.distance(from: text.utf16.startIndex, to: utf16Start)
        let end   = text.utf16.distance(from: text.utf16.startIndex, to: utf16End)
        return (
            tokenRange:   NSRange(location: offset + start, length: end - start),
            contentRange: NSRange(location: offset + start, length: end - start)
        )
    }
}

// MARK: - Render context

/// 렌더링에 필요한 공유 데이터. 매 렌더링 사이클마다 생성 (값 타입).
private struct RenderContext {
    let config: AppConfig
    let theme:  ThemeManager
    let text:   String

    var bodyFont: NSFont {
        resolveFont(family: config.editor.font.family, size: config.editor.font.size)
    }

    func textInRange(_ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    func fontDerived(from base: NSFont, size: Double, weight: NSFont.Weight) -> NSFont {
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        return NSFont(descriptor: descriptor, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - NSColor hex extension (모듈 전체 공유)

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else { return nil }

        let r, g, b, a: Double
        if hex.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8)  & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8)  & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// NSColor → "#RRGGBB" 문자열 (sRGB 기준)
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(c.redComponent   * 255 + 0.5)
        let g = Int(c.greenComponent * 255 + 0.5)
        let b = Int(c.blueComponent  * 255 + 0.5)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
