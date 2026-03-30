import Foundation

// MARK: - Entry point (순수 함수)

/// ParseResult → 완전한 HTML 문서 문자열.
func renderHTML(from result: ParseResult, config: AppConfig? = nil) -> String {
    let body = result.nodes.map(blockNodeToHTML).joined(separator: "\n")
    return wrapDocument(body: body, config: config)
}

// MARK: - Block rendering

private func blockNodeToHTML(_ node: BlockNode) -> String {
    switch node {
    case .heading(let level, let children, _):
        return "<h\(level)>\(inlinesHTML(children))</h\(level)>"

    case .paragraph(let children, _):
        return "<p>\(inlinesHTML(children))</p>"

    case .blockquote(let children, _):
        let inner = children.map(blockNodeToHTML).joined(separator: "\n")
        return "<blockquote>\(inner)</blockquote>"

    case .codeBlock(let language, let code, _):
        let cls = language.map { " class=\"language-\($0)\"" } ?? ""
        return "<pre><code\(cls)>\(escapeHTML(code))</code></pre>"

    case .unorderedList(let items, _, _):
        let items = items.map { "<li>\($0.children.map(blockNodeToHTML).joined())</li>" }.joined()
        return "<ul>\(items)</ul>"

    case .orderedList(let start, let items, _, _):
        let items = items.map { "<li>\($0.children.map(blockNodeToHTML).joined())</li>" }.joined()
        return "<ol start=\"\(start)\">\(items)</ol>"

    case .horizontalRule:
        return "<hr>"

    case .htmlBlock(let raw, _):
        return raw

    case .frontmatter(let content, _):
        return "<pre class=\"frontmatter\">---\n\(escapeHTML(content))\n---</pre>"

    case .table(let headers, _, let rows, _):
        let headerCells = headers.map { "<th>\(escapeHTML($0))</th>" }.joined()
        let dataRows = rows.map { row in
            let cells = row.map { "<td>\(escapeHTML($0))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined(separator: "\n")
        return "<table><thead><tr>\(headerCells)</tr></thead><tbody>\(dataRows)</tbody></table>"
    }
}

// MARK: - Inline rendering

private func inlinesHTML(_ nodes: [InlineNode]) -> String {
    nodes.map(inlineNodeToHTML).joined()
}

private func inlineNodeToHTML(_ node: InlineNode) -> String {
    switch node {
    case .text(let s):                  return escapeHTML(s)
    case .softBreak:                    return " "
    case .hardBreak:                    return "<br>"
    case .strong(let children):         return "<strong>\(inlinesHTML(children))</strong>"
    case .emphasis(let children):       return "<em>\(inlinesHTML(children))</em>"
    case .strikethrough(let children):  return "<del>\(inlinesHTML(children))</del>"
    case .inlineCode(let code):         return "<code>\(escapeHTML(code))</code>"
    case .link(let url, _, let children):
        return "<a href=\"\(escapeHTML(url))\">\(inlinesHTML(children))</a>"
    case .image(let url, let alt):
        return "<img src=\"\(escapeHTML(url))\" alt=\"\(escapeHTML(alt))\">"
    case .htmlInline(let raw):          return raw
    }
}

// MARK: - HTML escape

private func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&",  with: "&amp;")
     .replacingOccurrences(of: "<",  with: "&lt;")
     .replacingOccurrences(of: ">",  with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - Document wrapper

private func wrapDocument(body: String, config: AppConfig?) -> String {
    let resolvedConfig = config ?? .default
    let fontFamily = resolvedConfig.editor.font.family
    let fontSize   = resolvedConfig.editor.font.size
    let lineHeight = resolvedConfig.rendering.paragraph.lineHeight
    let h1Scale = resolvedConfig.rendering.headings.h1.scale
    let h2Scale = resolvedConfig.rendering.headings.h2.scale
    let h3Scale = resolvedConfig.rendering.headings.h3.scale
    let h4Scale = resolvedConfig.rendering.headings.h4.scale
    let h5Scale = resolvedConfig.rendering.headings.h5.scale
    let h6Scale = resolvedConfig.rendering.headings.h6.scale

    return """
    <!DOCTYPE html>
    <html lang="ko">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    :root { color-scheme: light dark; }
    body {
      /* 한글 폰트를 명시적으로 앞에 배치 — WKWebView createPDF 시 시스템 fallback이
         .notdef 글리프를 렌더하는 경우를 방지. */
      font-family: "\(fontFamily)", "Apple SD Gothic Neo", "AppleSDGothicNeo-Regular",
                   "Noto Sans KR", -apple-system, sans-serif;
      font-size: \(fontSize)px;
      line-height: \(lineHeight);
      max-width: 720px;
      margin: 0 auto;
      padding: 40px 24px;
      color: #1a1a1a;
      background: #ffffff;
    }
    @media (prefers-color-scheme: dark) {
      body { color: #e8e8e8; background: #1c1c1c; }
      a { color: #5ab0ff; }
      code, pre { background: #2a2a2a; }
    }
    h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 1.5em 0 0.5em; }
    h1, h2, h3, h4, h5, h6 {
      font-family: inherit;
    }
    h1 { font-size: \(h1Scale)em; }
    h2 { font-size: \(h2Scale)em; }
    h3 { font-size: \(h3Scale)em; }
    h4 { font-size: \(h4Scale)em; }
    h5 { font-size: \(h5Scale)em; }
    h6 { font-size: \(h6Scale)em; }
    p  { margin: 0.75em 0; }
    a  { color: #0070f3; text-decoration: none; }
    a:hover { text-decoration: underline; }
    blockquote {
      margin: 1em 0; padding: 0.5em 1em;
      border-left: 4px solid #d0d0d0;
      color: #666; background: #f9f9f9;
    }
    code {
      /* D2Coding: 한글 주석이 포함된 코드 블록의 깨짐 방지 */
      font-family: "D2Coding", "Nanum Gothic Coding", "SF Mono", Menlo, monospace;
      font-size: 0.875em;
      padding: 0.1em 0.3em;
      background: #f0f0f0; border-radius: 3px;
    }
    pre { padding: 1em; background: #f0f0f0; border-radius: 6px; overflow-x: auto; }
    pre code { padding: 0; background: none; }
    ul, ol { margin: 0.5em 0; padding-left: 2em; }
    li { margin: 0.25em 0; }
    hr { border: none; border-top: 1px solid #e0e0e0; margin: 2em 0; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; margin: 1em 0; }
    th, td { border: 1px solid #e0e0e0; padding: 0.5em 1em; text-align: left; }
    th { background: #f5f5f5; font-weight: 600; }
    </style>
    </head>
    <body>
    \(body)
    </body>
    </html>
    """
}
