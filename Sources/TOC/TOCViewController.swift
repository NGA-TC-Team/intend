import AppKit

// MARK: - Delegate

@MainActor
protocol TOCViewControllerDelegate: AnyObject {
    func toc(_ vc: TOCViewController, didSelectEntry entry: TOCEntry)
}

// MARK: - Tree connector info

/// 각 TOC 항목에 대한 트리 연결선 정보.
private struct TreeInfo {
    /// 이 항목의 왼쪽에 수직선이 그려져야 하는 레벨 집합.
    /// 예: {1, 2} → 1번째·2번째 열에 │ 선 표시.
    let openColumns: Set<Int>
    /// true → └── (마지막 자식), false → ├── (형제 더 있음)
    let isLastChild: Bool
    /// 최상위(level 1) 항목은 커넥터 없음
    let isRoot: Bool
}

/// [TOCEntry] 배열에서 각 항목의 트리 연결선 정보를 계산.
private func computeTreeInfo(entries: [TOCEntry]) -> [TreeInfo] {
    let n = entries.count
    var result: [TreeInfo] = []

    for i in 0..<n {
        let level = entries[i].level

        // 최상위(level 1) = 루트: 커넥터 없음
        if level <= 1 {
            result.append(TreeInfo(openColumns: [], isLastChild: false, isRoot: true))
            continue
        }

        // isLastChild: 다음에 같은 레벨 형제가 나타나기 전에 더 높은 레벨(낮은 숫자)이 등장하면 true
        var isLastChild = true
        for j in (i + 1)..<n {
            let nextLevel = entries[j].level
            if nextLevel < level  { break }          // 상위 레벨 → 마지막 자식
            if nextLevel == level { isLastChild = false; break }  // 같은 레벨 형제 존재
            // nextLevel > level: 더 깊은 자손 → 계속 탐색
        }

        // openColumns: 각 조상 레벨(1 …< level)에 대해
        // 이 항목 이후에도 해당 레벨의 형제가 남아 있으면 수직선 유지
        var openCols: Set<Int> = []
        for col in 1..<level {
            for j in (i + 1)..<n {
                let nextLevel = entries[j].level
                if nextLevel < col  { break }            // 조상이 닫힘
                if nextLevel == col { openCols.insert(col); break }  // 같은 레벨 형제 → 선 유지
            }
        }

        result.append(TreeInfo(openColumns: openCols, isLastChild: isLastChild, isRoot: false))
    }
    return result
}

// MARK: - View Controller

final class TOCViewController: NSViewController {

    weak var delegate: TOCViewControllerDelegate?

    private var entries:  [TOCEntry]  = []
    private var treeInfo: [TreeInfo]  = []
    private let scrollView = NSScrollView()
    private let tableView  = NSTableView()

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupTableView()
    }

    // MARK: - Public

    func reload(entries: [TOCEntry]) {
        self.entries  = entries
        self.treeInfo = computeTreeInfo(entries: entries)
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller   = true
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false
        scrollView.borderType            = .noBorder
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("toc"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView  = nil
        tableView.rowHeight   = 24
        tableView.backgroundColor          = .clear
        tableView.selectionHighlightStyle  = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.target     = self
        tableView.action     = #selector(rowClicked)

        scrollView.documentView    = tableView
        tableView.frame            = scrollView.bounds
        tableView.autoresizingMask = [.width, .height]
    }

    // MARK: - Actions

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < entries.count else { return }
        delegate?.toc(self, didSelectEntry: entries[row])
    }
}

// MARK: - NSTableViewDataSource

extension TOCViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
}

// MARK: - NSTableViewDelegate

extension TOCViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < entries.count, row < treeInfo.count else { return nil }

        let entry    = entries[row]
        let info     = treeInfo[row]
        let cellID   = NSUserInterfaceItemIdentifier("TOCCell")

        let cell: TOCCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? TOCCellView {
            cell = reused
        } else {
            cell = TOCCellView()
            cell.identifier = cellID
        }
        cell.configure(entry: entry, info: info)
        return cell
    }
}

// MARK: - TOCCellView

private final class TOCCellView: NSTableCellView {

    // MARK: Subviews
    private let treeCanvas = TreeConnectorView()
    private let label      = NSTextField(labelWithString: "")

    // MARK: Layout constants
    private static let unitWidth:   CGFloat = 14   // 레벨 당 열 너비
    private static let labelLeft:   CGFloat = 4    // canvas 오른쪽에서 레이블까지 간격

    override init(frame: NSRect) {
        super.init(frame: frame)

        treeCanvas.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints      = false
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(treeCanvas)
        addSubview(label)

        NSLayoutConstraint.activate([
            treeCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            treeCanvas.topAnchor.constraint(equalTo: topAnchor),
            treeCanvas.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.leadingAnchor.constraint(equalTo: treeCanvas.trailingAnchor,
                                           constant: Self.labelLeft),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(entry: TOCEntry, info: TreeInfo) {
        // ── 레이블 스타일
        switch entry.level {
        case 1:
            label.font      = .boldSystemFont(ofSize: 12)
            label.textColor = .labelColor
        case 2:
            label.font      = .systemFont(ofSize: 12)
            label.textColor = .labelColor
        default:
            label.font      = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        label.stringValue = entry.title

        // ── 트리 캔버스 너비: level * unitWidth
        let canvasWidth = CGFloat(max(entry.level - 1, 0)) * Self.unitWidth + (info.isRoot ? 8 : 0)
        treeCanvas.widthAnchor.constraint(equalToConstant: canvasWidth).isActive = false
        for c in treeCanvas.constraints where c.firstAttribute == .width {
            c.isActive = false
        }
        let wc = treeCanvas.widthAnchor.constraint(equalToConstant: canvasWidth)
        wc.isActive = true

        treeCanvas.configure(level: entry.level, info: info, unitWidth: Self.unitWidth)
    }
}

// MARK: - TreeConnectorView

/// git-lens 스타일 트리 연결선을 커스텀 드로잉하는 뷰.
private final class TreeConnectorView: NSView {

    private var level:     Int      = 1
    private var info:      TreeInfo = TreeInfo(openColumns: [], isLastChild: false, isRoot: true)
    private var unitWidth: CGFloat  = 14

    override var isFlipped: Bool { true }

    func configure(level: Int, info: TreeInfo, unitWidth: CGFloat) {
        self.level     = level
        self.info      = info
        self.unitWidth = unitWidth
        needsDisplay   = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !info.isRoot, level > 1 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let lineColor: NSColor = isDark
            ? NSColor(white: 1.0, alpha: 0.18)
            : NSColor(white: 0.0, alpha: 0.18)
        let accentColor = ThemeManager.shared.accentColor.withAlphaComponent(0.7)

        let midY   = bounds.height / 2
        let lastColX = CGFloat(level - 2) * unitWidth + unitWidth / 2  // 현재 레벨의 연결점 X

        // ── 조상 레벨 수직선 (열 0 … level-2 중 openColumns에 포함된 것만)
        lineColor.setStroke()
        for col in 1..<(level - 1) {
            if info.openColumns.contains(col) {
                let x = CGFloat(col - 1) * unitWidth + unitWidth / 2
                let path = NSBezierPath()
                path.lineWidth = 1.2
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.height))
                path.stroke()
            }
        }

        // ── 현재 레벨 연결선 (강조색 또는 기본색)
        accentColor.setStroke()
        let vertPath = NSBezierPath()
        vertPath.lineWidth = 1.5

        if info.isLastChild {
            // └── : 위에서 중간까지 수직, 그 다음 수평으로 오른쪽
            vertPath.move(to: NSPoint(x: lastColX, y: 0))
            vertPath.line(to: NSPoint(x: lastColX, y: midY))
        } else {
            // ├── : 전체 수직
            vertPath.move(to: NSPoint(x: lastColX, y: 0))
            vertPath.line(to: NSPoint(x: lastColX, y: bounds.height))
        }
        vertPath.stroke()

        // 수평선 (연결점 → 레이블 쪽)
        let horizPath = NSBezierPath()
        horizPath.lineWidth = 1.5
        horizPath.move(to: NSPoint(x: lastColX, y: midY))
        horizPath.line(to: NSPoint(x: bounds.width, y: midY))
        horizPath.stroke()

        // 작은 원형 노드 (연결점)
        let nodePath = NSBezierPath(ovalIn: NSRect(
            x: lastColX - 2.5, y: midY - 2.5, width: 5, height: 5
        ))
        accentColor.setFill()
        nodePath.fill()
    }
}
