import AppKit

// MARK: - TabBarView

/// VS Code 스타일 탭 바.
/// 탭 버튼을 가로로 나열. 활성 탭은 강조색 하단 인디케이터로 표시.
/// 더블클릭으로 탭 이름 인라인 편집 가능.
/// 드래그 앤 드롭으로 탭 순서 변경 가능.
final class TabBarView: NSView {

    // MARK: - Callbacks

    var onSelectTab:  ((Int) -> Void)?
    var onCloseTab:   ((Int) -> Void)?
    var onRenameTab:  ((Int, String) -> Void)?
    /// 탭 이동: (fromIndex, toIndex)
    var onMoveTab:    ((Int, Int) -> Void)?

    // MARK: - Constants

    static let height: CGFloat = 34
    private static let dragType = NSPasteboard.PasteboardType("com.intend.tabDrag")

    // MARK: - State

    private var tabButtons: [TabButton] = []
    private(set) var activeIndex: Int = 0

    // 드래그 중인 탭 인덱스와 드롭 삽입 위치 표시
    private var dragSourceIndex: Int?
    private var dropInsertIndex: Int?   // nil이면 드롭 바 미표시

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([Self.dragType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Drawing

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bg: NSColor = isDark
            ? NSColor(white: 0.16, alpha: 1)
            : NSColor(white: 0.90, alpha: 1)
        bg.setFill()
        bounds.fill()

        // 하단 구분선
        let sep: NSColor = isDark
            ? NSColor(white: 0.08, alpha: 1)
            : NSColor(white: 0.75, alpha: 1)
        sep.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        // 드롭 삽입 위치 표시 바
        if let insertIdx = dropInsertIndex {
            let xPos: CGFloat
            if insertIdx >= tabButtons.count {
                xPos = tabButtons.last.map { $0.frame.maxX } ?? 0
            } else {
                xPos = tabButtons[insertIdx].frame.minX
            }
            NSColor.systemBlue.withAlphaComponent(0.85).setFill()
            NSRect(x: xPos - 1, y: 2, width: 2, height: bounds.height - 4).fill()
        }
    }

    // MARK: - Drag source (TabButton → TabBarView로 위임)

    /// TabButton이 드래그 시작을 요청하면 호출.
    func beginDrag(fromIndex index: Int, event: NSEvent) {
        dragSourceIndex = index
        let pb = NSPasteboard(name: .drag)
        pb.clearContents()
        pb.setString("\(index)", forType: Self.dragType)

        let button = tabButtons[index]
        let img    = button.snapshot() ?? NSImage(size: button.bounds.size)
        let item   = NSDraggingItem(pasteboardWriter: pb.pasteboardItems!.first!)
        item.setDraggingFrame(button.bounds, contents: img)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadItem(
            withDataConformingToTypes: [Self.dragType.rawValue]) else { return [] }
        updateDropInsert(for: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadItem(
            withDataConformingToTypes: [Self.dragType.rawValue]) else { return [] }
        updateDropInsert(for: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropInsertIndex = nil
        needsDisplay    = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            dropInsertIndex = nil
            dragSourceIndex = nil
            needsDisplay    = true
        }
        guard let pb    = sender.draggingPasteboard.string(forType: Self.dragType),
              let from  = Int(pb),
              let toRaw = dropInsertIndex else { return false }

        // toRaw: 삽입 위치. from 이후에 삽입하면 -1 조정
        let to = toRaw > from ? toRaw - 1 : toRaw
        guard from != to else { return false }
        onMoveTab?(from, to)
        return true
    }

    private func updateDropInsert(for sender: NSDraggingInfo) {
        let localX   = convert(sender.draggingLocation, from: nil).x
        var insertIdx = tabButtons.count
        for (i, btn) in tabButtons.enumerated() {
            if localX < btn.frame.midX {
                insertIdx = i
                break
            }
        }
        if dropInsertIndex != insertIdx {
            dropInsertIndex = insertIdx
            needsDisplay    = true
        }
    }

    // MARK: - Public

    func reload(tabs: [TabItem], activeIndex: Int) {
        self.activeIndex = activeIndex
        subviews.forEach { $0.removeFromSuperview() }
        tabButtons = []

        var x: CGFloat = 0
        for (i, tab) in tabs.enumerated() {
            let btn = TabButton(
                title:    tab.displayName,
                index:    i,
                isActive: i == activeIndex
            )
            let w = btn.preferredWidth
            btn.frame = NSRect(x: x, y: 0, width: w, height: Self.height)
            btn.onSelect = { [weak self] idx in self?.onSelectTab?(idx) }
            btn.onClose  = { [weak self] idx in self?.onCloseTab?(idx) }
            btn.onRename = { [weak self] idx, name in self?.onRenameTab?(idx, name) }
            addSubview(btn)
            tabButtons.append(btn)
            x += w
        }
        needsDisplay = true
    }
}

// MARK: - TabButton

private final class TabButton: NSView {

    // MARK: Callbacks
    var onSelect: ((Int) -> Void)?
    var onClose:  ((Int) -> Void)?
    var onRename: ((Int, String) -> Void)?

    // MARK: State
    private let index:    Int
    private var isActive: Bool
    private var title:    String

    // MARK: Subviews
    private let titleLabel:  NSTextField
    private let closeButton: NSButton
    private var editField:   NSTextField?

    var preferredWidth: CGFloat {
        let measured = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12)
        ]).width
        return min(max(measured + 52, 80), 220)
    }

    // MARK: Init

    init(title: String, index: Int, isActive: Bool) {
        self.title    = title
        self.index    = index
        self.isActive = isActive

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font          = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail

        closeButton = NSButton()
        closeButton.bezelStyle             = .regularSquare
        closeButton.isBordered             = false
        closeButton.title                  = ""
        closeButton.image                  = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "action.close"))
        closeButton.imageScaling           = .scaleProportionallyUpOrDown
        closeButton.contentTintColor       = .tertiaryLabelColor

        super.init(frame: .zero)
        wantsLayer   = true
        clipsToBounds = true  // 하단 인디케이터 클리핑용

        addSubview(titleLabel)
        addSubview(closeButton)

        closeButton.target = self
        closeButton.action = #selector(didClickClose)
        closeButton.toolTip = "탭 닫기 (⌘W)"

        let dbl = NSClickGestureRecognizer(target: self, action: #selector(didDoubleClick))
        dbl.numberOfClicksRequired = 2
        addGestureRecognizer(dbl)

        // 마우스 hover 트래킹
        let area = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h       = bounds.height
        let closeS: CGFloat = 14
        let closePad: CGFloat = 6
        let leftPad:  CGFloat = 12

        closeButton.frame = NSRect(
            x:      bounds.width - closeS - closePad,
            y:      (h - closeS) / 2,
            width:  closeS,
            height: closeS
        )
        titleLabel.frame = NSRect(
            x:      leftPad,
            y:      (h - 16) / 2,
            width:  bounds.width - closeS - closePad - leftPad - 4,
            height: 16
        )
    }

    // MARK: Appearance

    private var isHovered = false

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isActive {
            // 활성 탭: 밝은 배경 + 강조색 하단 3pt 인디케이터
            layer?.backgroundColor = isDark
                ? NSColor(white: 0.22, alpha: 1).cgColor
                : NSColor.white.cgColor
            titleLabel.textColor = isDark ? .white : .labelColor
            closeButton.contentTintColor = isDark
                ? NSColor.white.withAlphaComponent(0.6)
                : NSColor.labelColor.withAlphaComponent(0.5)
        } else {
            let hoverBg: CGColor = isDark
                ? NSColor(white: 0.20, alpha: 1).cgColor
                : NSColor(white: 0.86, alpha: 1).cgColor
            let normalBg: CGColor = NSColor.clear.cgColor
            layer?.backgroundColor = isHovered ? hoverBg : normalBg
            titleLabel.textColor = isDark
                ? NSColor.white.withAlphaComponent(0.5)
                : NSColor.labelColor.withAlphaComponent(0.55)
            closeButton.contentTintColor = .clear
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isActive {
            // 하단 강조색 인디케이터 (3pt)
            let accent = ThemeManager.shared.accentColor
            accent.setFill()
            NSRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3).fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 { onSelect?(index) }
        // 드래그 감지: 마우스를 누른 채 움직이면 탭 이동 시작
        let startPoint = event.locationInWindow
        var dragged    = false
        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self] tracked, stop in
            guard let self, let tracked else { stop.pointee = true; return }
            if tracked.type == .leftMouseUp { stop.pointee = true; return }
            let cur  = tracked.locationInWindow
            let dist = hypot(cur.x - startPoint.x, cur.y - startPoint.y)
            if dist > 4, !dragged {
                dragged = true
                stop.pointee = true
                // TabBarView에 드래그 위임
                (self.superview as? TabBarView)?.beginDrag(fromIndex: self.index, event: event)
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        if !isActive { closeButton.contentTintColor = .tertiaryLabelColor }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    @objc private func didClickClose() {
        onClose?(index)
    }

    // MARK: Double-click rename

    @objc private func didDoubleClick() {
        guard editField == nil else { return }

        let field = NSTextField(frame: NSRect(
            x:      titleLabel.frame.minX - 2,
            y:      titleLabel.frame.minY - 1,
            width:  bounds.width - titleLabel.frame.minX - 28,
            height: titleLabel.frame.height + 2
        ))
        field.stringValue     = title
        field.font            = titleLabel.font
        field.isBordered      = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType   = .none
        field.delegate        = self
        addSubview(field)
        editField = field
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    private func commitRename() {
        guard let field = editField else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        field.removeFromSuperview()
        editField = nil
        if !newName.isEmpty, newName != title {
            title = newName
            titleLabel.stringValue = newName
            onRename?(index, newName)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard editField != nil else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 36: commitRename()           // Return
        case 53:                          // Escape
            editField?.removeFromSuperview()
            editField = nil
        default: super.keyDown(with: event)
        }
    }
}

extension TabButton: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }
}

// MARK: - TabButton snapshot helper

extension TabButton {
    /// 드래그 이미지용 스냅샷 NSImage 생성.
    func snapshot() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - TabBarView NSDraggingSource

extension TabBarView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }
}
