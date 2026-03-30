import AppKit

/// 메인 편집기 뷰. NSTextView 래핑 + Document 연결.
final class EditorViewController: NSViewController {

    // MARK: - Subviews

    private let backgroundView = BackgroundView()
    private let scrollView     = NSScrollView()
    private let textView       = MarkdownTextView()
    private let statusBar      = StatusBarView()

    // MARK: - State

    private weak var document: MarkdownDocument?
    private var isLoadingDocument = false

    /// 텍스트 변경 시 호출되는 콜백 (프리뷰 업데이트 등).
    var onTextChange: ((String) -> Void)?

    /// 헤딩 목록 변경 시 호출되는 콜백 (TOC 패널 업데이트).
    var onTOCEntriesChange: (([TOCEntry]) -> Void)? {
        didSet { syncTOCCallback() }
    }

    // MARK: - Code block overlays

    /// language 라벨 + 복사 버튼 오버레이 (코드 블록마다 1개).
    private var codeBlockOverlays: [(language: String?, code: String, range: NSRange, view: CodeBlockHeaderView)] = []
    private var overlayUpdateWork: DispatchWorkItem?
    private var postCommitSyncWork: DispatchWorkItem?

    // MARK: - Table overlays

    private var tableOverlays: [(charRange: NSRange, view: TableOverlayView)] = []

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupConstraints()
        configureTextView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: .configDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backgroundSettingsDidChange),
            name: .backgroundSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: .appearanceDidChange,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 스크롤 시 오버레이 위치 재계산
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    // MARK: - Public

    func load(document: MarkdownDocument) {
        self.document = document
        isLoadingDocument = true
        let src = document.source
        textView.string = src
        isLoadingDocument = false
        (textView.textStorage as? MarkdownTextStorage)?.updateActiveEditingBlock(for: textView.selectedRange())
        window?.title = document.displayName
        // 문서 로드 직후 상태바 초기 표시
        let charCount     = src.count
        let nonSpaceCount = src.filter { !$0.isWhitespace }.count
        let lastEdited    = document.lastSavedAt
        statusBar.update(charCount: charCount, nonSpaceCount: nonSpaceCount, lastEdited: lastEdited)
        // 코드 블록 오버레이 초기화
        scheduleOverlayUpdate(markdown: src)
    }

    /// Finder 드래그앤드롭 콜백 — EditorWindowController에서 주입.
    var onFileDropped: ((URL) -> Void)? {
        get { textView.onFileDropped }
        set { textView.onFileDropped = newValue }
    }

    // MARK: - Layout

    private func setupScrollView() {
        // 배경 뷰 (z-order 최하단)
        view.addSubview(backgroundView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = true
        scrollView.documentView          = textView
        view.addSubview(scrollView)

        view.addSubview(statusBar)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // 배경: 전체 영역
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // 상태바: 하단 24pt 고정
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            // 스크롤뷰: 상태바 위까지
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ])
    }

    private func configureTextView() {
        let config = ConfigManager.shared.current
        textView.delegate = self          // textDidChange 수신에 필수
        textView.applyConfig(config)
        applyBackgroundSettings()
        syncStatsCallback()
        syncScrollButtons()
        (textView.textStorage as? MarkdownTextStorage)?.updateActiveEditingBlock(for: textView.selectedRange())
    }

    private func syncStatsCallback() {
        (textView.textStorage as? MarkdownTextStorage)?.onStatsChange = { [weak self] charCount, nonSpace in
            guard let self else { return }
            let lastEdited = self.document?.lastTypedAt ?? self.document?.lastSavedAt
            self.statusBar.update(charCount: charCount, nonSpaceCount: nonSpace, lastEdited: lastEdited)
        }
    }

    private func syncScrollButtons() {
        statusBar.onScrollToTop = { [weak self] in
            guard let sv = self?.scrollView else { return }
            sv.contentView.scroll(to: .zero)
            sv.reflectScrolledClipView(sv.contentView)
        }
        statusBar.onScrollToBottom = { [weak self] in
            guard let sv = self?.scrollView,
                  let docView = sv.documentView else { return }
            let bottom = NSPoint(x: 0, y: docView.frame.height - sv.contentView.bounds.height)
            sv.contentView.scroll(to: bottom)
            sv.reflectScrolledClipView(sv.contentView)
        }
    }

    // MARK: - Background

    func applyBackgroundSettings() {
        let settings = BackgroundSettings.load()
        switch settings.mode {
        case .none:
            backgroundView.reset()
            scrollView.drawsBackground = true
            textView.drawsBackground   = true
            view.window?.isOpaque      = true
            view.window?.backgroundColor = nil

        case .transparent:
            scrollView.drawsBackground = false
            textView.drawsBackground   = false
            view.window?.isOpaque      = false
            view.window?.backgroundColor = .clear
            backgroundView.applyTransparent(alpha: settings.alpha)

        case .image:
            guard let url = settings.imageURL else {
                // 보안 범위 북마크 해제 실패 → 기본 배경 fallback (재귀 방지)
                backgroundView.reset()
                scrollView.drawsBackground   = true
                textView.drawsBackground     = true
                view.window?.isOpaque        = true
                view.window?.backgroundColor = nil
                return
            }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let image = NSImage(contentsOf: url) else { return }
            // 윈도우는 불투명 유지 — 콘텐츠 영역(BackgroundView) 뒤로 바탕화면이 보이면 안 됨.
            // scrollView/textView만 투명으로 설정해 BackgroundView의 이미지가 비쳐 보이게 함.
            scrollView.drawsBackground   = false
            textView.drawsBackground     = false
            view.window?.isOpaque        = true
            view.window?.backgroundColor = nil
            backgroundView.applyImage(image,
                                      contentMode: settings.contentMode,
                                      overlayAlpha: settings.overlayAlpha)
        }
    }

    // MARK: - Public

    /// 포커스를 받을 수 있는 뷰 (탭 전환 시 firstResponder 설정에 사용).
    var focusableView: NSView { textView }

    // MARK: - Public (TOC)

    /// 특정 문자 오프셋(헤딩 줄 시작)으로 편집기를 스크롤하고 커서를 이동.
    func scrollToHeading(offset: Int) {
        let range = NSRange(location: min(offset, textView.string.utf16.count), length: 0)
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Config

    @objc private func configDidChange(_ notification: Notification) {
        guard let config = notification.object as? AppConfig else { return }
        textView.applyConfig(config)
    }

    @objc private func backgroundSettingsDidChange(_ notification: Notification) {
        applyBackgroundSettings()
    }

    @objc private func appearanceDidChange(_ notification: Notification) {
        // 투명/이미지 배경의 overlay 재계산 (다크 모드에서 overlay를 약간 강화)
        applyBackgroundSettings()
    }

    @objc private func scrollViewBoundsChanged(_ notification: Notification) {
        repositionCodeBlockOverlays()
        repositionTableOverlays()
    }

    // MARK: - Private

    private func syncTOCCallback() {
        (textView.textStorage as? MarkdownTextStorage)?.onTOCEntriesChange = onTOCEntriesChange
    }

    private func schedulePostCommitSync() {
        postCommitSyncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.textView.isInTransientInputState else { return }
            let source = self.textView.string
            (self.textView.textStorage as? MarkdownTextStorage)?.refreshRenderedRanges(after: self.textView.selectedRange())
            self.document?.update(source: source)
            self.onTextChange?(source)
            self.scheduleOverlayUpdate(markdown: source)
        }
        postCommitSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    // MARK: - Overlays (코드 블록 + 표)

    /// 텍스트 변경 후 debounce로 모든 오버레이를 갱신.
    private func scheduleOverlayUpdate(markdown: String) {
        overlayUpdateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let result = parse(markdown: markdown)
            self.updateCodeBlockOverlays(result: result, markdown: markdown)
            self.updateTableOverlays(result: result, markdown: markdown)
            self.syncTableOverlayVisibility()
        }
        overlayUpdateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: Code block overlays

    private func updateCodeBlockOverlays(result: ParseResult, markdown: String) {
        let blocks: [(language: String?, code: String, range: NSRange)] = result.nodes.compactMap { node in
            guard case .codeBlock(let lang, let code, let span) = node,
                  !span.isUnknown else { return nil }
            guard let nsRange = lineAlignedRange(for: span, in: markdown) else { return nil }
            return (lang, code, nsRange)
        }

        codeBlockOverlays.forEach { $0.view.removeFromSuperview() }
        codeBlockOverlays = []

        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!

        for block in blocks {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            var boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            boundingRect.origin.x += textView.textContainerInset.width
            boundingRect.origin.y += textView.textContainerInset.height

            let overlayH: CGFloat = 22
            let overlayW: CGFloat = min(180, boundingRect.width)
            let overlayX = boundingRect.maxX - overlayW - 4
            let overlayY = textView.isFlipped
                ? boundingRect.minY + 2
                : boundingRect.maxY - overlayH - 2

            let overlayView = CodeBlockHeaderView(frame: NSRect(
                x: overlayX, y: overlayY, width: overlayW, height: overlayH
            ))
            overlayView.configure(language: block.language)
            let capturedCode = block.code
            overlayView.onCopy = {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(capturedCode, forType: .string)
            }

            textView.addSubview(overlayView)
            codeBlockOverlays.append((block.language, block.code, block.range, overlayView))
        }
    }

    private func repositionCodeBlockOverlays() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let overlayH: CGFloat = 22
        for overlay in codeBlockOverlays {
            let charRange = NSRange(
                location: min(overlay.range.location, textView.string.utf16.count),
                length: min(overlay.range.length, max(0, textView.string.utf16.count - overlay.range.location))
            )
            guard charRange.length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            var br = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            br.origin.x += textView.textContainerInset.width
            br.origin.y += textView.textContainerInset.height
            let overlayW = min(180, br.width)
            let overlayX = br.maxX - overlayW - 4
            let overlayY = textView.isFlipped ? br.minY + 2 : br.maxY - overlayH - 2
            overlay.view.frame = NSRect(x: overlayX, y: overlayY, width: overlayW, height: overlayH)
        }
    }

    // MARK: - Find/Replace

    private let findEngine = FindReplaceEngine()
    private var findPanel: FindReplacePanel?

    /// Cmd+F: 찾기 패널 열기.
    @objc func performFindAction(_ sender: Any?) {
        showFindPanel(withReplace: false)
    }

    /// Cmd+Option+F: 찾기/바꾸기 패널 열기.
    @objc func performFindReplaceAction(_ sender: Any?) {
        showFindPanel(withReplace: true)
    }

    /// Cmd+G: 다음 매치로 이동.
    @objc func findNext(_ sender: Any?) {
        findEngine.selectNext()
    }

    /// Cmd+Shift+G: 이전 매치로 이동.
    @objc func findPrevious(_ sender: Any?) {
        findEngine.selectPrevious()
    }

    private func showFindPanel(withReplace: Bool) {
        if findPanel == nil {
            let panel = FindReplacePanel()
            findEngine.textView = textView
            findEngine.delegate = self

            panel.onQueryChange = { [weak self, weak panel] query, useRegex, caseSensitive in
                guard let self, let panel else { return }
                self.findEngine.search(query: query, useRegex: useRegex, caseSensitive: caseSensitive)
                let hasError = !query.isEmpty && self.findEngine.matches.isEmpty
                panel.setFindFieldError(hasError)
            }
            panel.onNext     = { [weak self] in self?.findEngine.selectNext() }
            panel.onPrevious = { [weak self] in self?.findEngine.selectPrevious() }

            panel.onReplaceCurrent = { [weak self, weak panel] replacement in
                guard let self, let panel else { return }
                self.findEngine.replaceCurrent(with: replacement)
                // 교체 후 재검색 — panelのonQueryChange를 재트리거
                panel.triggerQueryChange()
            }
            panel.onReplaceAll = { [weak self, weak panel] replacement in
                guard let self, let panel else { return }
                panel.replaceAllWithCurrentQuery(engine: self.findEngine)
            }
            panel.onClose = { [weak self] in self?.hideFindPanel() }

            view.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
                panel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            ])
            findPanel = panel
        }

        findPanel?.setShowReplace(withReplace)
        findPanel?.focusFindField()
    }

    private func hideFindPanel() {
        findEngine.clearHighlights()
        findPanel?.removeFromSuperview()
        findPanel = nil
        view.window?.makeFirstResponder(textView)
    }

    // MARK: Table overlays

    /// 열 너비 비율 퍼시스턴스 (widthKey → [CGFloat]).
    private var tableColumnRatiosStore: [String: [CGFloat]] = [:]

    private func updateTableOverlays(result: ParseResult, markdown: String) {
        let infos: [TableInfo] = result.nodes.compactMap { node -> TableInfo? in
            guard case .table(let headers, let alignments, let rows, let span) = node,
                  !span.isUnknown,
                  let nsRange = lineAlignedRange(for: span, in: markdown, includeTrailingNewline: true)
            else { return nil }
            return TableInfo(headers: headers, alignments: alignments, rows: rows, charRange: nsRange)
        }

        tableOverlays.forEach { $0.view.removeFromSuperview() }
        tableOverlays = []

        guard let lm = textView.layoutManager,
              let tc = textView.textContainer else { return }

        let insetX   = textView.textContainerInset.width
        let insetY   = textView.textContainerInset.height
        let isDark   = ThemeManager.shared.isDark
        let fontSize = ConfigManager.shared.current.editor.font.size

        for info in infos {
            let overlayH = TableOverlayView.height(
                headers: info.headers, rows: info.rows, fontSize: fontSize
            )
            let glyphRange = lm.glyphRange(forCharacterRange: info.charRange, actualCharacterRange: nil)
            var br = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            br.origin.x += insetX
            br.origin.y += insetY

            let overlayX = insetX
            let overlayW = textView.frame.width - 2 * insetX
            // textView.isFlipped = true: br.minY가 표의 상단 (Y가 작을수록 위)
            let overlayY = br.minY

            let ov = TableOverlayView(frame: NSRect(
                x: overlayX, y: overlayY, width: max(overlayW, 60), height: overlayH
            ))
            ov.info          = info
            ov.isDark        = isDark
            ov.fontSize      = fontSize
            ov.columnRatios  = tableColumnRatiosStore[info.widthKey] ?? []

            let key = info.widthKey
            ov.onColumnRatiosChange = { [weak self] ratios in
                self?.tableColumnRatiosStore[key] = ratios
            }

            textView.addSubview(ov)
            tableOverlays.append((info.charRange, ov))
        }
    }

    private func repositionTableOverlays() {
        guard let lm = textView.layoutManager,
              let tc = textView.textContainer else { return }
        let insetX   = textView.textContainerInset.width
        let insetY   = textView.textContainerInset.height
        let fontSize = ConfigManager.shared.current.editor.font.size
        let strLen   = textView.string.utf16.count

        for (charRange, ov) in tableOverlays {
            let safeRange = NSRange(
                location: min(charRange.location, strLen),
                length: min(charRange.length, max(0, strLen - charRange.location))
            )
            guard safeRange.length > 0 else { continue }
            let glyphRange = lm.glyphRange(forCharacterRange: safeRange, actualCharacterRange: nil)
            var br = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            br.origin.x += insetX
            br.origin.y += insetY

            let overlayH = TableOverlayView.height(
                headers: ov.info.headers, rows: ov.info.rows, fontSize: fontSize
            )
            let overlayX = insetX
            let overlayW = textView.frame.width - 2 * insetX
            let overlayY = br.minY

            ov.frame = NSRect(x: overlayX, y: overlayY, width: max(overlayW, 60), height: overlayH)
        }
    }

    /// 커서 위치에 따라 표 오버레이 표시/숨김 전환.
    private func syncTableOverlayVisibility() {
        let cursorLoc = textView.selectedRange().location
        for (charRange, ov) in tableOverlays {
            ov.isHidden = NSLocationInRange(cursorLoc, charRange)
        }
    }

    // MARK: - Helpers

    private var window: NSWindow? { view.window }
}

// MARK: - FindReplaceEngineDelegate

extension EditorViewController: FindReplaceEngineDelegate {
    func engineDidUpdateMatches(count: Int, currentIndex: Int) {
        findPanel?.updateMatchLabel(count: count, currentIndex: currentIndex)
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !isLoadingDocument else { return }
        (textView.textStorage as? MarkdownTextStorage)?.updateActiveEditingBlock(for: textView.selectedRange())
        guard !textView.isInTransientInputState, !textView.hasMarkedText() else { return }
        schedulePostCommitSync()
        // 텍스트 변경 시 찾기 결과 갱신
        findPanel?.triggerQueryChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        (textView.textStorage as? MarkdownTextStorage)?.updateActiveEditingBlock(for: textView.selectedRange())
        syncTableOverlayVisibility()
    }
}

// MARK: - Stats (syncStatsCallback에서 콜백으로 처리)
// 상태바 lastEdited 실시간 갱신은 onStatsChange 콜백 내 document?.lastTypedAt 참조로 처리됨.
