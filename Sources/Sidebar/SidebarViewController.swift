import AppKit

// MARK: - Delegate

@MainActor
protocol SidebarViewControllerDelegate: AnyObject {
    func sidebar(_ vc: SidebarViewController, didSelectFile url: URL)
}

// MARK: - View Controller

final class SidebarViewController: NSViewController {

    weak var delegate: SidebarViewControllerDelegate?

    // MARK: - Subviews

    private let headerView   = NSView()
    private let headerLabel  = NSTextField(labelWithString: "최근 파일")
    private let clearButton  = NSButton()
    private let tagBarScroll = NSScrollView()
    private let tagStack     = NSStackView()
    private let scrollView   = NSScrollView()
    private let tableView    = NSTableView()
    private let emptyLabel   = NSTextField(labelWithString: "최근에 열린 파일이 없습니다")

    // MARK: - State

    private var allRecentURLs: [URL] = []          // 원본 전체 목록
    private var displayedURLs: [URL] = []          // 필터 적용된 표시 목록
    private var tagCache: [URL: [String]] = [:]    // URL → 태그 배열
    private var selectedTag: String? = nil         // nil = "모두"

    private static let allowedExtensions: Set<String> = ["md", "markdown", "mdown", "mdxk"]

    // MARK: - Lifecycle

    override func loadView() {
        view = SidebarBackgroundView()
        view.wantsLayer = true
        setupHeader()
        setupTagBar()
        setupTableView()
        setupConstraints()
        loadRecents()
    }

    /// 파일 열기/닫기 후 외부에서 호출해 목록 갱신.
    func refresh() {
        loadRecents()
    }

    // MARK: - Header

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerView.addSubview(headerLabel)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .inline
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "최근 파일 지우기")
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.isBordered = false
        clearButton.toolTip = "최근 파일 목록 지우기"
        clearButton.target = self
        clearButton.action = #selector(clearRecents)
        headerView.addSubview(clearButton)
    }

    // MARK: - Tag Bar

    private func setupTagBar() {
        tagStack.orientation  = .horizontal
        tagStack.spacing      = 6
        tagStack.alignment    = .centerY
        tagStack.distribution = .fill
        tagStack.edgeInsets   = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        tagStack.translatesAutoresizingMaskIntoConstraints = false

        tagBarScroll.hasVerticalScroller   = false
        tagBarScroll.hasHorizontalScroller = false
        tagBarScroll.autohidesScrollers    = true
        tagBarScroll.drawsBackground       = false
        tagBarScroll.documentView          = tagStack
        tagBarScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tagBarScroll)
    }

    private func rebuildTagBar() {
        tagStack.arrangedSubviews.forEach { tagStack.removeArrangedSubview($0); $0.removeFromSuperview() }

        // 전체 태그 수집 (중복 제거, 정렬)
        var allTags: [String] = []
        var seen = Set<String>()
        for url in allRecentURLs {
            for tag in tagCache[url] ?? [] {
                if seen.insert(tag).inserted { allTags.append(tag) }
            }
        }
        allTags.sort()

        // 태그 없으면 바 숨김
        tagBarScroll.isHidden = allTags.isEmpty
        guard !allTags.isEmpty else { return }

        // "모두" 칩
        let allTagTitle = String(localized: "sidebar.tag.all")
        let allChip = TagChip(title: allTagTitle, isSelected: selectedTag == nil)
        allChip.target = self
        allChip.action = #selector(tagChipTapped(_:))
        tagStack.addArrangedSubview(allChip)

        // 개별 태그 칩
        for tag in allTags {
            let chip = TagChip(title: tag, isSelected: selectedTag == tag)
            chip.target = self
            chip.action = #selector(tagChipTapped(_:))
            tagStack.addArrangedSubview(chip)
        }

        // stackView가 scrollView 높이에 맞도록
        if let clipView = tagBarScroll.contentView as? NSClipView {
            tagStack.heightAnchor.constraint(equalTo: clipView.heightAnchor).isActive = true
        }
    }

    @objc private func tagChipTapped(_ sender: TagChip) {
        let tappedTitle = sender.chipTitle
        let allTagTitle = String(localized: "sidebar.tag.all")
        selectedTag = (tappedTitle == allTagTitle) ? nil : tappedTitle

        // 칩 선택 상태 갱신
        for view in tagStack.arrangedSubviews {
            guard let chip = view as? TagChip else { continue }
            chip.isSelected = (selectedTag == nil)
                ? chip.chipTitle == allTagTitle
                : chip.chipTitle == selectedTag
        }

        applyFilter()
    }

    // MARK: - Table view

    private func setupTableView() {
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("RecentFile"))
        col.isEditable = false
        tableView.addTableColumn(col)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        view.addSubview(scrollView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
    }

    // MARK: - Constraints

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header — 탭 바 높이(34pt)에 맞춰 top offset 없이 정렬
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 34),

            clearButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 18),
            clearButton.heightAnchor.constraint(equalToConstant: 18),

            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            headerLabel.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // Tag bar (32pt 고정 높이, 태그 없을 때도 공간 유지 — isHidden으로 처리)
            tagBarScroll.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            tagBarScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tagBarScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tagBarScroll.heightAnchor.constraint(equalToConstant: 28),

            // Scroll / Table
            scrollView.topAnchor.constraint(equalTo: tagBarScroll.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Empty state
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Data

    private func loadRecents() {
        allRecentURLs = NSDocumentController.shared.recentDocumentURLs
            .filter { Self.allowedExtensions.contains($0.pathExtension.lowercased()) }

        applyFilter()
        loadTagsAsync()
    }

    /// 백그라운드에서 각 파일의 태그를 읽어 캐시에 저장.
    private func loadTagsAsync() {
        let urls = allRecentURLs
        let existing = tagCache
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var newCache = existing
            for url in urls where existing[url] == nil {
                newCache[url] = TagExtractor.extract(from: url)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tagCache = newCache
                self.rebuildTagBar()
                self.applyFilter()
            }
        }
    }

    private func applyFilter() {
        if let tag = selectedTag {
            displayedURLs = allRecentURLs.filter { tagCache[$0]?.contains(tag) == true }
        } else {
            displayedURLs = allRecentURLs
        }
        tableView.reloadData()
        let isEmpty = displayedURLs.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = selectedTag != nil
            ? "'\(selectedTag!)' 태그가 있는 파일이 없습니다"
            : "최근에 열린 파일이 없습니다"
    }

    // MARK: - Actions

    @objc private func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        tagCache = [:]
        selectedTag = nil
        loadRecents()
    }
}

// MARK: - NSTableViewDataSource

extension SidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { displayedURLs.count }
}

// MARK: - NSTableViewDelegate

extension SidebarViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let url = displayedURLs[row]
        let cell = RecentFileCellView()
        cell.configure(url: url, tags: tagCache[url] ?? [])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 48 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        let url = displayedURLs[row]
        tableView.deselectRow(row)
        delegate?.sidebar(self, didSelectFile: url)
    }
}

// MARK: - SidebarBackgroundView

/// 사이드바 배경 — 탭 바와 동일한 색상을 사용해 경계 없이 연결됨.
private final class SidebarBackgroundView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bg: NSColor = isDark
            ? NSColor(white: 0.16, alpha: 1)
            : NSColor(white: 0.90, alpha: 1)
        bg.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - TagChip

private final class TagChip: NSButton {

    var chipTitle: String { title }

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    convenience init(title: String, isSelected: Bool) {
        self.init(frame: .zero)
        self.title = title
        self.isSelected = isSelected
        self.translatesAutoresizingMaskIntoConstraints = false

        font         = .systemFont(ofSize: 11, weight: .medium)
        bezelStyle   = .inline
        isBordered   = false
        wantsLayer   = true
        layer?.cornerRadius = 10

        updateAppearance()
    }

    override func layout() {
        super.layout()
        // 수평 패딩 적용
        let h = bounds.height
        layer?.cornerRadius = h / 2
    }

    private func updateAppearance() {
        if isSelected {
            contentTintColor     = .white
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            contentTintColor     = .secondaryLabelColor
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    // NSButton은 레이어를 직접 관리하므로 appearance 변경 시 재적용
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - RecentFileCellView

private final class RecentFileCellView: NSTableCellView {

    private let icon      = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let tagRow    = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)

        icon.translatesAutoresizingMaskIntoConstraints  = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        tagRow.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font          = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.wraps   = false

        pathLabel.font          = .systemFont(ofSize: 11)
        pathLabel.textColor     = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.cell?.wraps   = false

        tagRow.orientation  = .horizontal
        tagRow.spacing      = 4
        tagRow.alignment    = .centerY

        addSubview(icon)
        addSubview(nameLabel)
        addSubview(tagRow)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            tagRow.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            tagRow.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(url: URL, tags: [String]) {
        nameLabel.stringValue = url.lastPathComponent

        // ~/로 시작하도록 홈 디렉터리 단축
        let parent = url.deletingLastPathComponent().path
        let home   = FileManager.default.homeDirectoryForCurrentUser.path
        let displayPath = parent.hasPrefix(home)
            ? "~" + parent.dropFirst(home.count)
            : parent
        pathLabel.stringValue = displayPath

        // 실제 파일 아이콘
        let img: NSImage
        if FileManager.default.fileExists(atPath: url.path) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage()
        }
        img.size = NSSize(width: 24, height: 24)
        icon.image = img

        // 태그 배지 (최대 3개 표시)
        tagRow.arrangedSubviews.forEach { tagRow.removeArrangedSubview($0); $0.removeFromSuperview() }
        tagRow.isHidden = tags.isEmpty
        for tag in tags.prefix(3) {
            let label = InlineBadge(title: tag)
            tagRow.addArrangedSubview(label)
        }
        if tags.count > 3 {
            let more = InlineBadge(title: "+\(tags.count - 3)")
            tagRow.addArrangedSubview(more)
        }
    }
}

// MARK: - InlineBadge

private final class InlineBadge: NSView {

    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue  = title
        label.font         = .systemFont(ofSize: 9, weight: .medium)
        label.textColor    = .controlAccentColor
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        label.textColor        = .controlAccentColor
    }
}
