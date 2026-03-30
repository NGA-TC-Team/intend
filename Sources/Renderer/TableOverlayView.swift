import AppKit

// MARK: - TableInfo

/// 표 렌더링에 필요한 데이터 묶음.
struct TableInfo {
    let headers:    [String]
    let alignments: [ColumnAlignment]
    let rows:       [[String]]
    let charRange:  NSRange

    var columnCount: Int {
        max(1, headers.isEmpty ? (rows.first?.count ?? 1) : headers.count)
    }

    /// 열 너비 퍼시스턴스 키 (헤더 텍스트 기반).
    var widthKey: String { headers.joined(separator: "\u{001F}") }
}

// MARK: - TableOverlayView

/// 마크다운 표를 에디터 위에 직접 렌더링하는 오버레이 NSView.
///
/// - 커서가 표 범위 **밖**에 있을 때 표시 (EditorViewController가 isHidden 제어)
/// - 커서가 표 안으로 들어오면 isHidden = true → 원본 마크다운 텍스트 편집 가능
/// - 열 구분선(±6pt 히트박스)을 드래그해 열 너비 비율 조절
final class TableOverlayView: NSView {

    // MARK: - Configuration

    var info:     TableInfo = TableInfo(headers: [], alignments: [], rows: [], charRange: NSRange(location: 0, length: 0))
    var isDark:   Bool      = false { didSet { needsDisplay = true } }
    var fontSize: CGFloat   = 14    { didSet { needsDisplay = true } }

    /// 열 너비 비율 배열 (합 ≈ 1.0). 비어있으면 균등 분할.
    var columnRatios: [CGFloat] = [] { didSet { needsDisplay = true } }

    /// 드래그 완료 시 호출 — 새 비율 배열 전달.
    var onColumnRatiosChange: (([CGFloat]) -> Void)?

    // MARK: - Drag

    private struct DragState {
        let dividerIndex:  Int
        let startX:        CGFloat
        let initialRatios: [CGFloat]
    }
    private var dragState: DragState?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // NSTextView와 동일한 flipped 좌표계 사용 (y=0이 상단)
    override var isFlipped: Bool { true }

    // MARK: - Computed

    private var numCols: Int { info.columnCount }

    private var effectiveRatios: [CGFloat] {
        let n = numCols
        guard columnRatios.count == n, columnRatios.allSatisfy({ $0 > 0.01 }) else {
            return Array(repeating: 1.0 / CGFloat(n), count: n)
        }
        return columnRatios
    }

    // MARK: - Drawing

    static let rowHeight: CGFloat = 28   // ceil(fontSize * 1.75) 기준값; draw()에서 재계산

    override func draw(_ dirtyRect: NSRect) {
        let w  = bounds.width
        let n  = numCols
        let r  = effectiveRatios
        let cw = r.map { $0 * w }

        let rowH: CGFloat = ceil(fontSize * 1.75)
        let sepH: CGFloat = 1

        // ── 색상 ────────────────────────────────────────────────────────────
        let bg           = isDark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        let headerBg     = isDark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.87, alpha: 1)
        let altRowBg     = isDark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        let sepLineColor = isDark ? NSColor(white: 0.30, alpha: 1) : NSColor(white: 0.70, alpha: 1)
        let colSepColor  = isDark ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.78, alpha: 1)
        let textColor    = isDark ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.10, alpha: 1)
        let hdrColor     = isDark ? NSColor(white: 1.00, alpha: 1) : NSColor(white: 0.00, alpha: 1)

        // ── 전체 배경 ────────────────────────────────────────────────────────
        bg.setFill()
        bounds.fill()

        var curY: CGFloat = 0

        // ── 헤더 행 ──────────────────────────────────────────────────────────
        if !info.headers.isEmpty {
            headerBg.setFill()
            NSRect(x: 0, y: curY, width: w, height: rowH).fill()
            drawRow(cells: info.headers, y: curY, rowH: rowH,
                    colWidths: cw, numCols: n, textColor: hdrColor, bold: true)
            curY += rowH
            sepLineColor.setFill()
            NSRect(x: 0, y: curY, width: w, height: sepH).fill()
            curY += sepH
        }

        // ── 데이터 행 ────────────────────────────────────────────────────────
        for (ri, row) in info.rows.enumerated() {
            if ri % 2 == 1 {
                altRowBg.setFill()
                NSRect(x: 0, y: curY, width: w, height: rowH).fill()
            }
            drawRow(cells: row, y: curY, rowH: rowH,
                    colWidths: cw, numCols: n, textColor: textColor, bold: false)
            curY += rowH
        }

        // ── 열 구분선 ────────────────────────────────────────────────────────
        colSepColor.setFill()
        var divX: CGFloat = 0
        for i in 0 ..< n - 1 {
            divX += cw[i]
            NSRect(x: divX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }

        // ── 외곽선 ───────────────────────────────────────────────────────────
        sepLineColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    // MARK: - Row drawing helper

    private func drawRow(
        cells: [String], y: CGFloat, rowH: CGFloat,
        colWidths: [CGFloat], numCols: Int,
        textColor: NSColor, bold: Bool
    ) {
        let pad:  CGFloat = 10
        let font: NSFont  = bold
            ? NSFont.boldSystemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: textColor,
            .paragraphStyle:  para
        ]

        var cellX: CGFloat = 0
        for col in 0 ..< numCols {
            let text = col < cells.count
                ? cells[col].trimmingCharacters(in: .whitespaces) : ""
            let cw    = colWidths[col]
            let drawX = cellX + pad
            let drawW = cw - pad * 2
            // isFlipped = true: drawY는 셀 top-baseline 위치
            // NSString.draw(in:)은 flipped 좌표에서 rect의 y가 상단
            let textH = font.boundingRectForFont.height
            let drawY = y + (rowH - textH) / 2

            if drawW > 0 {
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: cellX, y: y, width: cw, height: rowH)).setClip()
                (text as NSString).draw(
                    in: NSRect(x: drawX, y: drawY, width: drawW, height: textH),
                    withAttributes: attrs
                )
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            cellX += cw
        }
    }

    // MARK: - Hit testing (열 구분선에만 반응, 나머지는 통과)

    override func hitTest(_ point: NSPoint) -> NSView? {
        let r = effectiveRatios
        let w = bounds.width
        var x: CGFloat = 0
        for i in 0 ..< r.count - 1 {
            x += r[i] * w
            if abs(point.x - x) < 8 { return super.hitTest(point) }
        }
        return nil  // 클릭 이벤트를 NSTextView로 통과시킴
    }

    // MARK: - Mouse events (열 너비 드래그)

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let r   = effectiveRatios
        let w   = bounds.width
        var x: CGFloat = 0
        for i in 0 ..< r.count - 1 {
            x += r[i] * w
            if abs(loc.x - x) < 8 {
                dragState = DragState(dividerIndex: i, startX: loc.x, initialRatios: r)
                NSCursor.resizeLeftRight.push()
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag = dragState else { super.mouseDragged(with: event); return }
        let loc   = convert(event.locationInWindow, from: nil)
        let delta = (loc.x - drag.startX) / bounds.width
        let i     = drag.dividerIndex
        let minR: CGFloat = 0.04

        var r = drag.initialRatios
        let newLeft = max(minR, min(r[i] + delta, 1.0 - minR))
        let diff    = newLeft - r[i]
        r[i]        = newLeft
        r[i + 1]    = max(minR, r[i + 1] - diff)

        let total = r.reduce(0, +)
        columnRatios = r.map { $0 / total }
    }

    override func mouseUp(with event: NSEvent) {
        if dragState != nil {
            NSCursor.pop()
            onColumnRatiosChange?(columnRatios.isEmpty ? effectiveRatios : columnRatios)
        }
        dragState = nil
        super.mouseUp(with: event)
    }

    // MARK: - Cursor rects

    override func resetCursorRects() {
        let r = effectiveRatios
        let w = bounds.width
        var x: CGFloat = 0
        for i in 0 ..< r.count - 1 {
            x += r[i] * w
            addCursorRect(
                NSRect(x: x - 6, y: 0, width: 12, height: bounds.height),
                cursor: .resizeLeftRight
            )
        }
    }

    // MARK: - Height calculation

    /// 주어진 row 수와 fontSize 기준으로 오버레이 높이를 계산.
    static func height(headers: [String], rows: [[String]], fontSize: CGFloat) -> CGFloat {
        let rowH: CGFloat = ceil(fontSize * 1.75)
        let sepH: CGFloat = 1
        let hasHeader = !headers.isEmpty
        return (hasHeader ? rowH + sepH : 0) + CGFloat(rows.count) * rowH
    }
}
