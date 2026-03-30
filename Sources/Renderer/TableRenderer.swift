import AppKit

// MARK: - TableToken

struct TableToken {
    let range:      NSRange
    let headers:    [String]
    let alignments: [ColumnAlignment]
    let rows:       [[String]]
}

// MARK: - TableAttachment

/// 마크다운 표를 이미지로 렌더링한 NSTextAttachment.
/// 커서가 표 밖에 있을 때 이미지 표시, 커서가 들어오면 원본 마크다운 텍스트 복원.
final class TableAttachment: NSTextAttachment {

    let rawSource: String

    init(image: NSImage, rawSource: String) {
        self.rawSource = rawSource
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var attributedString: NSAttributedString {
        NSAttributedString(attachment: self)
    }
}

// MARK: - Table image renderer

/// 표 토큰을 NSImage로 렌더링. 열 너비는 totalWidth / numCols로 균등 분할.
func renderTableImage(
    headers:    [String],
    alignments: [ColumnAlignment],
    rows:       [[String]],
    totalWidth: CGFloat,
    isDark:     Bool,
    fontSize:   CGFloat
) -> NSImage {

    let numCols  = max(!headers.isEmpty ? headers.count : (rows.first?.count ?? 1), 1)
    let colWidth = totalWidth / CGFloat(numCols)

    let rowH:  CGFloat = ceil(fontSize * 1.75)
    let sepH:  CGFloat = 1
    let hasHeader = !headers.isEmpty
    let totalH = (hasHeader ? rowH + sepH : 0) + CGFloat(rows.count) * rowH

    let size   = NSSize(width: totalWidth, height: max(totalH, rowH))
    let image  = NSImage(size: size)
    image.lockFocus()

    // ── 색상 팔레트 ──────────────────────────────────────────────────
    let bg        = NSColor(white: isDark ? 0.10 : 0.98, alpha: 1)
    let headerBg  = NSColor(white: isDark ? 0.20 : 0.88, alpha: 1)
    let altRowBg  = NSColor(white: isDark ? 0.15 : 0.93, alpha: 1)
    let sepColor  = NSColor(white: isDark ? 0.30 : 0.72, alpha: 1)
    let colSep    = NSColor(white: isDark ? 0.22 : 0.82, alpha: 1)
    let textColor = NSColor(white: isDark ? 0.95 : 0.05, alpha: 1)
    let hdrColor  = NSColor(white: isDark ? 1.00 : 0.00, alpha: 1)

    // ── 배경 ─────────────────────────────────────────────────────────
    bg.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    // ── 그리기 시작 위치: 이미지 좌표계는 좌하단이 원점 ──────────────
    //   Y = size.height → 맨 위 / Y = 0 → 맨 아래
    var curY = size.height

    // ── 헤더 행 ──────────────────────────────────────────────────────
    if hasHeader {
        curY -= rowH
        headerBg.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: curY, width: totalWidth, height: rowH)).fill()
        drawCells(headers, y: curY, rowH: rowH, numCols: numCols, colWidth: colWidth,
                  fontSize: fontSize, color: hdrColor, bold: true)

        // 헤더-데이터 구분선
        curY -= sepH
        sepColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: curY, width: totalWidth, height: sepH)).fill()
    }

    // ── 데이터 행 ────────────────────────────────────────────────────
    for (ri, row) in rows.enumerated() {
        curY -= rowH
        if ri % 2 == 1 {
            altRowBg.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: curY, width: totalWidth, height: rowH)).fill()
        }
        drawCells(row, y: curY, rowH: rowH, numCols: numCols, colWidth: colWidth,
                  fontSize: fontSize, color: textColor, bold: false)
    }

    // ── 열 구분선 ────────────────────────────────────────────────────
    colSep.setFill()
    for col in 1 ..< numCols {
        let x = CGFloat(col) * colWidth
        NSBezierPath(rect: NSRect(x: x - 0.5, y: 0, width: 1, height: size.height)).fill()
    }

    image.unlockFocus()
    return image
}

// MARK: - Private drawing helper

private func drawCells(
    _ cells:    [String],
    y:          CGFloat,
    rowH:       CGFloat,
    numCols:    Int,
    colWidth:   CGFloat,
    fontSize:   CGFloat,
    color:      NSColor,
    bold:       Bool
) {
    let pad: CGFloat = 10
    let font: NSFont = bold
        ? NSFont.boldSystemFont(ofSize: fontSize)
        : NSFont.systemFont(ofSize: fontSize)

    let para = NSMutableParagraphStyle()
    para.lineBreakMode = .byTruncatingTail
    para.alignment     = .left

    let attrs: [NSAttributedString.Key: Any] = [
        .font:            font,
        .foregroundColor: color,
        .paragraphStyle:  para
    ]

    for col in 0 ..< numCols {
        let text    = col < cells.count ? cells[col].trimmingCharacters(in: .whitespaces) : ""
        let textH   = fontSize + 2
        let cellX   = CGFloat(col) * colWidth + pad
        let cellW   = colWidth - pad * 2
        let cellY   = y + (rowH - textH) / 2

        guard cellW > 0 else { continue }

        // 클리핑 + 그리기
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: cellX, y: cellY, width: cellW, height: rowH)).setClip()
        (text as NSString).draw(
            in: NSRect(x: cellX, y: cellY, width: cellW, height: textH),
            withAttributes: attrs
        )
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
