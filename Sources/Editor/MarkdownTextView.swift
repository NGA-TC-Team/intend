import AppKit

/// 마크다운 편집을 위한 커스텀 NSTextView.
/// 자동 치환 비활성화, config 기반 폰트/색상 적용.
final class MarkdownTextView: NSTextView {

    enum EditingState: Equatable {
        case idle
        case composing
        case committing
    }

    // MARK: - Frame resize debounce (scroll 성능)
    private var _frameResizeWork: DispatchWorkItem?
    private var editingState: EditingState = .idle

    // MARK: - Init

    init() {
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)

        let storage = MarkdownTextStorage()
        storage.addLayoutManager(layoutManager)

        super.init(frame: .zero, textContainer: container)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Config

    func applyConfig(_ config: AppConfig) {
        let editor    = config.editor
        let rendering = config.rendering

        // 폰트
        let bodyFont = resolveFont(family: editor.font.family, size: editor.font.size)
        font = bodyFont

        // 줄 간격
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = rendering.paragraph.lineHeight
        defaultParagraphStyle    = style

        // 배경색
        backgroundColor  = ThemeManager.shared.backgroundColor
        insertionPointColor = ThemeManager.shared.foregroundColor
        textColor        = ThemeManager.shared.foregroundColor
        typingAttributes = baseTypingAttributes(for: config)

        needsDisplay = true
    }

    // MARK: - Table full-width background

    /// 표 행 배경(.tableRowBackground)을 에디터 전체 너비로 확장해 그린다.
    /// 일반 .backgroundColor는 글리프 extents만 채우지만, 이 override는 행 전체를 채운다.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage,
              storage.length > 0 else { return }

        let insetY = textContainerInset.height

        // 뷰 좌표계에서 보이는 glyph 범위 → character 범위
        let visibleGlyphRange = lm.glyphRange(forBoundingRect: rect, in: tc)
        guard visibleGlyphRange.length > 0 else { return }
        let visibleCharRange = lm.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        guard visibleCharRange.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        let insetX = textContainerInset.width

        // 표 행 배경 (전체 너비)
        storage.enumerateAttribute(
            .tableRowBackground,
            in: visibleCharRange,
            options: []
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            guard color.cgColor.alpha > 0.005 else { return }

            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, _ in
                let rowRect = NSRect(
                    x: insetX,
                    y: lineRect.minY + insetY,
                    width: self.frame.width - 2 * insetX,
                    height: lineRect.height
                )
                color.setFill()
                rowRect.fill()
            }
        }

        // HR 실선 — 행 높이 중앙에 1pt 선
        storage.enumerateAttribute(
            .hrLineColor,
            in: visibleCharRange,
            options: []
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, _ in
                let midY = lineRect.minY + insetY + lineRect.height / 2
                let lineRect1pt = NSRect(
                    x: insetX,
                    y: midY - 0.5,
                    width: self.frame.width - 2 * insetX,
                    height: 1
                )
                color.setFill()
                lineRect1pt.fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Appearance

    /// 시스템 라이트↔다크 전환 시 TextStorage 전체 속성 재적용.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        (textStorage as? MarkdownTextStorage)?.reapplyAllAttributes()
        backgroundColor     = ThemeManager.shared.backgroundColor
        insertionPointColor = ThemeManager.shared.foregroundColor
        textColor           = ThemeManager.shared.foregroundColor
        // 다른 컴포넌트(배경, 사이드바 등)에 외관 변경 전파
        NotificationCenter.default.post(name: .appearanceDidChange, object: nil)
    }

    // MARK: - Formula WYSIWYG

    /// 커서 이동 감지: 이전 위치가 수식 범위였으면 attachment로 교체.
    /// 새 위치가 attachment면 원본 텍스트로 복원.
    override func setSelectedRange(
        _ charRange: NSRange,
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        resetTypingAttributesIfNeeded()
    }

    func renderAllTables() {
        // Source-first editor mode: keep tables as markdown source in the editor.
    }

    // MARK: - Drag and Drop (Finder → New Tab)

    /// Finder에서 .md 파일을 드롭하면 새 탭으로 열기.
    var onFileDropped: ((URL) -> Void)?

    private func markdownURLs(from pasteboard: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly:          true,
            .urlReadingContentsConformToTypes: ["public.plain-text",
                                               "net.daringfireball.markdown",
                                               "public.data"]
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
        let mdExts = Set(["md", "markdown", "mdown", "mkd", "txt"])
        return urls.filter { mdExts.contains($0.pathExtension.lowercased()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !markdownURLs(from: sender.draggingPasteboard).isEmpty {
            showDropHighlight(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !markdownURLs(from: sender.draggingPasteboard).isEmpty {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        showDropHighlight(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = markdownURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        showDropHighlight(false)
        urls.forEach { onFileDropped?($0) }
        return true
    }

    /// 드래그 진입 시 scrollView 테두리에 파란색 강조 표시.
    private func showDropHighlight(_ on: Bool) {
        guard let sv = enclosingScrollView else { return }
        sv.wantsLayer = true
        sv.layer?.borderColor  = on ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        sv.layer?.borderWidth  = on ? 2.5 : 0
        sv.layer?.cornerRadius = on ? 6   : 0
    }

    // MARK: - IME 조합 상태 추적
    //
    // hasMarkedText()는 IME가 조합 문자를 교체하는 순간(이전 마크 해제 →
    // 새 마크 설정 사이)에 순간적으로 false를 반환한다.
    // 이 틈에 processEditing()이 applyAttributes()를 호출하면
    // backing의 모든 속성이 초기화되어 IME 조합 추적 정보가 유실된다.
    //
    // setMarkedText / unmarkText override로 조합 구간 전체를 정확히 포착.
    // MarkdownTextStorage.processEditing()이 이 프로퍼티를 참조한다.
    var isIMEComposing: Bool { editingState == .composing }
    var isInTransientInputState: Bool { editingState != .idle }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        transitionEditingState(to: .composing)
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func unmarkText() {
        super.unmarkText()
        if editingState == .composing {
            transitionEditingState(to: .committing)
            schedulePostCommitRefresh()
        }
    }

    // MARK: - Key input overrides

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // 조합 중에는 AppKit이 문자열 교체를 전적으로 관리하게 둔다.
        guard editingState != .composing, !hasMarkedText() else {
            transitionEditingState(to: .committing)
            super.insertText(string, replacementRange: replacementRange)
            schedulePostCommitRefresh()
            return
        }
        transitionEditingState(to: .idle)
        let str: String
        if let s = string as? String { str = s }
        else if let a = string as? NSAttributedString { str = a.string }
        else { super.insertText(string, replacementRange: replacementRange); return }

        let effective = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if let result = autoPairEdit(typed: str, in: self.string, selectedRange: effective) {
            apply(result)
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
        resetTypingAttributesIfNeeded()
    }

    override func insertNewline(_ sender: Any?) {
        guard editingState != .composing, !hasMarkedText() else {
            transitionEditingState(to: .committing)
            super.insertNewline(sender)
            schedulePostCommitRefresh()
            return
        }
        if let result = smartEnterEdit(in: string, selectedRange: selectedRange()) {
            apply(result)
        } else {
            super.insertNewline(sender)
        }
        resetTypingAttributesIfNeeded()
    }

    override func insertTab(_ sender: Any?) {
        if let result = smartTabEdit(in: string, selectedRange: selectedRange(), dedent: false) {
            apply(result)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let result = smartTabEdit(in: string, selectedRange: selectedRange(), dedent: true) {
            apply(result)
        } else {
            super.insertBacktab(sender)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        // 조합 중엔 스마트 백스페이스 건너뜀.
        guard !hasMarkedText() else { super.deleteBackward(sender); return }
        if let result = smartBackspaceEdit(in: string, selectedRange: selectedRange()) {
            apply(result)
        } else {
            super.deleteBackward(sender)
        }
    }

    /// Cmd+Backspace: 커서~줄 시작까지 삭제.
    /// 줄 시작에 커서가 있으면 앞의 \n을 삭제해 이전 단락과 병합.
    override func deleteToBeginningOfLine(_ sender: Any?) {
        guard !hasMarkedText() else { super.deleteToBeginningOfLine(sender); return }
        let sel = selectedRange()
        // 선택 영역이 있으면 기본 동작에 위임
        guard sel.length == 0 else { super.deleteToBeginningOfLine(sender); return }

        let ns  = string as NSString
        let pos = sel.location
        let lineStart = lineStartOffset(at: pos, in: ns)

        if pos == lineStart {
            // 줄 시작: 앞 \n 삭제 → 이전 단락과 병합
            guard lineStart > 0 else { return }
            let delRange = NSRange(location: lineStart - 1, length: 1)
            guard shouldChangeText(in: delRange, replacementString: "") else { return }
            textStorage?.replaceCharacters(in: delRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: lineStart - 1, length: 0))
        } else {
            // 커서 위치 ~ 줄 시작 삭제
            let delRange = NSRange(location: lineStart, length: pos - lineStart)
            guard delRange.length > 0 else { return }
            guard shouldChangeText(in: delRange, replacementString: "") else { return }
            textStorage?.replaceCharacters(in: delRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: lineStart, length: 0))
        }
    }

    /// Alt+Backspace: 단어 단위 역삭제.
    /// 커서 바로 앞이 \n이면 그 \n만 삭제해 단락 병합.
    override func deleteWordBackward(_ sender: Any?) {
        guard !hasMarkedText() else { super.deleteWordBackward(sender); return }
        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0 else { super.deleteWordBackward(sender); return }

        let ns      = string as NSString
        let pos     = sel.location
        let prevChar = ns.substring(with: NSRange(location: pos - 1, length: 1))

        if prevChar == "\n" {
            // 단락 경계에서 \n만 삭제해 이전 줄과 병합
            let delRange = NSRange(location: pos - 1, length: 1)
            guard shouldChangeText(in: delRange, replacementString: "") else { return }
            textStorage?.replaceCharacters(in: delRange, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: pos - 1, length: 0))
        } else {
            super.deleteWordBackward(sender)
        }
    }

    /// InputHandler 결과를 NSTextView에 적용.
    /// shouldChangeText → replaceCharacters → didChangeText 순서로 undo 통합.
    private func apply(_ result: EditResult) {
        // 텍스트 변경 없이 커서만 이동하는 경우
        if result.text.isEmpty && result.range.length == 0 {
            setSelectedRange(result.cursor)
            return
        }
        guard shouldChangeText(in: result.range, replacementString: result.text) else { return }
        textStorage?.replaceCharacters(in: result.range, with: result.text)
        didChangeText()
        setSelectedRange(result.cursor)
        resetTypingAttributesIfNeeded()
    }

    // MARK: - Private helpers

    private var markdownStorage: MarkdownTextStorage? {
        textStorage as? MarkdownTextStorage
    }

    private func transitionEditingState(to nextState: EditingState) {
        guard editingState != nextState else { return }
        let wasSuspended = editingState != .idle
        let willSuspend = nextState != .idle

        editingState = nextState

        if !wasSuspended, willSuspend {
            markdownStorage?.suspendRendering()
        } else if wasSuspended, !willSuspend {
            markdownStorage?.resumeRendering()
        }
    }

    private func schedulePostCommitRefresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.transitionEditingState(to: .idle)
            self.resetTypingAttributesIfNeeded()
            self.markdownStorage?.refreshRenderedRanges(after: self.selectedRange())
        }
    }

    private func baseTypingAttributes(for config: AppConfig = ConfigManager.shared.current) -> [NSAttributedString.Key: Any] {
        let font = resolveFont(family: config.editor.font.family, size: config.editor.font.size)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = config.rendering.paragraph.lineHeight

        return [
            .font: font,
            .foregroundColor: ThemeManager.shared.foregroundColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func resetTypingAttributesIfNeeded() {
        guard selectedRange().length == 0, !hasMarkedText() else { return }
        typingAttributes = baseTypingAttributes()
    }

    /// 주어진 위치의 현재 줄 시작 오프셋 반환.
    private func lineStartOffset(at pos: Int, in ns: NSString) -> Int {
        var start = pos
        while start > 0 {
            if ns.substring(with: NSRange(location: start - 1, length: 1)) == "\n" { break }
            start -= 1
        }
        return start
    }

    private func commonInit() {
        // 비연속 레이아웃: 보이지 않는 영역의 glyph 생성 지연 (대용량 문서 성능)
        layoutManager?.allowsNonContiguousLayout = true
        // 레이아웃 완료 시 textView frame을 content 높이에 맞게 갱신 (스크롤 활성화)
        layoutManager?.delegate = self
        // 스크롤 중 frame resize 디바운스용
        _frameResizeWork = nil

        // 파일 드래그앤드롭: 기존 텍스트 타입에 fileURL 추가
        registerForDraggedTypes(readablePasteboardTypes + [.fileURL])

        isRichText                          = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled  = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled     = false
        isAutomaticTextCompletionEnabled    = false
        isAutomaticDataDetectionEnabled     = false
        allowsUndo                          = true
        typingAttributes                    = baseTypingAttributes()

        // 줄바꿈
        textContainer?.widthTracksTextView    = true
        textContainer?.containerSize          = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        isHorizontallyResizable = false
        isVerticallyResizable   = true
        autoresizingMask        = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // 내부 여백 — top/bottom 대칭 40pt (bottom 여유는 frame 갱신 시 120pt 추가)
        textContainerInset = NSSize(width: 60, height: 40)
    }
}

// MARK: - NSLayoutManagerDelegate (스크롤 활성화)

extension MarkdownTextView: NSLayoutManagerDelegate {
    /// 레이아웃 완료(또는 부분 완료) 시 textView frame을 실제 콘텐츠 높이에 맞게 갱신.
    /// allowsNonContiguousLayout = true 환경에서 scrollView가 올바른 contentSize를
    /// 알 수 있도록 frame을 동기화한다. bottom에 120pt 여유 공간을 추가한다.
    nonisolated func layoutManager(
        _ layoutManager: NSLayoutManager,
        didCompleteLayoutFor textContainer: NSTextContainer?,
        atEnd layoutFinishedFlag: Bool
    ) {
        // NSLayoutManager 콜백은 항상 메인 스레드에서 발생.
        // self 프로퍼티만 참조해 Swift 6 data-race 경고를 피함.
        MainActor.assumeIsolated {
            guard let lm = self.layoutManager,
                  let tc = self.textContainer,
                  let clipView = self.enclosingScrollView?.contentView else { return }

            let used      = lm.usedRect(for: tc)
            let inset     = self.textContainerInset.height
            let minH      = clipView.bounds.height
            let bottomPad: CGFloat = 120
            let newH      = max(used.height + inset * 2 + bottomPad, minH)

            // 현재 frame보다 작으면 갱신 불필요 (스크롤 중 shrink 방지)
            guard newH > self.frame.height + 1 else { return }

            // 50ms 디바운스: 스크롤 중 잦은 setFrameSize 호출 방지
            self._frameResizeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.setFrameSize(NSSize(width: self.frame.width, height: newH))
                if let sv = self.enclosingScrollView {
                    sv.reflectScrolledClipView(sv.contentView)
                }
            }
            self._frameResizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }
    }
}
