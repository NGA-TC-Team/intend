import AppKit

/// NSTextStorage 서브클래스.
/// processEditing()에서 AttributeRenderer를 통해 마크다운 속성을 증분 적용.
/// ⚠️ processEditing() 안에서 replaceCharacters() 절대 금지 (재진입 → 무한루프)
final class MarkdownTextStorage: NSTextStorage {

    // MARK: - Backing store

    private let backing = NSMutableAttributedString()

    // MARK: - Parse cache

    private var parseResult: ParseResult = ParseResult(nodes: [], sourceText: "")

    // MARK: - Stats callback

    /// 글자 수 변경 시 메인 스레드에서 호출 (200ms debounce).
    /// (charCount: 공백 포함, nonSpaceCount: 공백 제외)
    var onStatsChange: ((Int, Int) -> Void)?
    private var statsDebounceWork: DispatchWorkItem?

    // MARK: - TOC callback

    /// 헤딩 목록 변경 시 메인 스레드에서 호출 (150ms debounce).
    var onTOCEntriesChange: (([TOCEntry]) -> Void)?
    private var tocDebounceWork: DispatchWorkItem?

    // MARK: - Appearance

    /// 라이트↔다크 전환 시 전체 속성 재적용.
    /// 조합 중에는 즉시 재도색하지 않고 커밋 뒤에 한 번만 반영한다.
    func reapplyAllAttributes() {
        refreshRenderedRanges()
    }

    // MARK: - Attribute cycle guard

    /// processEditing 재진입 방지 플래그.
    /// attribute-only 사이클에서 applyAttributes() 중복 호출을 막는다.
    private var isApplyingAttributes = false
    private var activeEditingBlockRange: NSRange?
    private var renderingSuspensionDepth = 0
    private var needsDeferredRefresh = false

    func suspendRendering() {
        renderingSuspensionDepth += 1
    }

    func resumeRendering() {
        guard renderingSuspensionDepth > 0 else { return }
        renderingSuspensionDepth -= 1
        guard renderingSuspensionDepth == 0, needsDeferredRefresh else { return }
        refreshRenderedRanges()
    }

    func refreshRenderedRanges(after selection: NSRange? = nil) {
        if let selection {
            activeEditingBlockRange = editingBlockRange(containing: selection, in: parseResult, text: backing.string)
        }
        guard renderingSuspensionDepth == 0 else {
            needsDeferredRefresh = true
            return
        }

        needsDeferredRefresh = false
        applyAttributes()
        notifyAttributeEditing(for: [NSRange(location: 0, length: backing.length)])
        scheduleStatsUpdate()
        scheduleTOCUpdate()
    }

    // MARK: - NSTextStorage required overrides

    override var string: String {
        backing.string
    }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(
            .editedCharacters,
            range: range,
            changeInLength: (str as NSString).length - range.length
        )
        endEditing()
    }

    override func setAttributes(
        _ attrs: [NSAttributedString.Key: Any]?,
        range: NSRange
    ) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Attribute application

    override func processEditing() {
        let isRenderingSuspended = renderingSuspensionDepth > 0

        // 재진입(attribute-only 사이클)이 아닐 때만 속성 적용.
        if !isRenderingSuspended, !isApplyingAttributes {
            isApplyingAttributes = true
            applyAttributes()   // backing store 직접 수정 (edited() 호출 없음)
            isApplyingAttributes = false
        } else if isRenderingSuspended {
            needsDeferredRefresh = true
        }

        // ① character edit을 정확한 범위로 layout manager에 통지.
        //    이전 코드처럼 여기서 edited(.editedAttributes, 0..len) 를 먼저 호출하면
        //    character edit의 changeInLength가 전체 범위에 합산되어
        //    layout manager가 커서 위치를 잃는 버그 발생.
        super.processEditing()

        // ② attribute 변경 통지를 별도 edit 사이클로 분리 (changeInLength=0).
        //    isApplyingAttributes 플래그로 재진입 시 applyAttributes() 재호출 방지.
        if !isRenderingSuspended, !isApplyingAttributes {
            notifyAttributeEditing(for: [NSRange(location: 0, length: backing.length)])
            scheduleStatsUpdate()
            scheduleTOCUpdate()
        }
    }

    func updateActiveEditingBlock(for selection: NSRange) {
        let previous = activeEditingBlockRange
        let next = editingBlockRange(containing: selection, in: parseResult, text: backing.string)
        guard previous != next else { return }
        activeEditingBlockRange = next
        guard renderingSuspensionDepth == 0 else {
            needsDeferredRefresh = true
            return
        }
        reapplyRanges(previous: previous, next: next)
    }

    private func applyAttributes() {
        let fullText   = backing.string
        let totalLen   = backing.length
        let fullRange  = NSRange(location: 0, length: totalLen)
        let tv         = layoutManagers.first?.firstTextView as? MarkdownTextView
        // editedRange가 backing 범위를 초과하는 엣지 케이스 방어
        let safeEdited = NSIntersectionRange(editedRange, fullRange)
        let config     = ConfigManager.shared.current

        // 1. 파싱 (증분: 편집된 단락 범위만 재파싱, 나머지는 캐시 활용)
        let newResult = reparseIncremental(
            newText: fullText,
            editedRange: safeEdited,
            previous: parseResult
        )
        parseResult = newResult

        // processEditing 실행 중에는 tv?.selectedRange()가 아직 갱신되지 않은
        // 편집 전 커서 위치(구 위치)를 반환한다. 구 위치를 activeEditingBlockRange에
        // 사용하면, 실제 커서가 이동할 블록이 아닌 엉뚱한 블록의 패치가 억제돼
        // 특수기호가 순간적으로 보이는 플리커가 발생한다.
        //
        // 해결: 문자 편집이 있을 때는 editedRange + changeInLength로
        //       새 커서가 위치할 지점을 추정해 activeEditingBlockRange를 계산한다.
        //  - 삽입/치환 (changeInLength >= 0): NSMaxRange(safeEdited) — 삽입된 문자 바로 뒤
        //  - 삭제         (changeInLength < 0): safeEdited.location — 삭제 시작 위치
        let cursorRange: NSRange
        if editedMask.contains(.editedCharacters) {
            let estimatedLoc = changeInLength >= 0
                ? min(NSMaxRange(safeEdited), totalLen)
                : min(safeEdited.location, totalLen)
            cursorRange = NSRange(location: estimatedLoc, length: 0)
        } else {
            // 속성 전용 사이클이거나 외부에서 직접 호출된 경우 — 선택 범위가 정확함
            cursorRange = tv?.selectedRange() ?? NSRange(location: 0, length: 0)
        }
        activeEditingBlockRange = editingBlockRange(containing: cursorRange, in: newResult, text: fullText)

        applyBaseAttributes(to: [fullRange], config: config)

        // 2. AttributeRenderer → AttributePatch 목록 → backing에 적용
        let patches = renderAttributes(
            from: newResult,
            config: config,
            theme: ThemeManager.shared
        )
        applyPatches(filteredPatches(patches))
    }

    private func scheduleStatsUpdate() {
        guard onStatsChange != nil else { return }
        statsDebounceWork?.cancel()
        let text = backing.string
        let work = DispatchWorkItem { [weak self] in
            guard let callback = self?.onStatsChange else { return }
            let charCount     = text.count
            let nonSpaceCount = text.filter { !$0.isWhitespace }.count
            callback(charCount, nonSpaceCount)
        }
        statsDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
    }

    private func scheduleTOCUpdate() {
        guard onTOCEntriesChange != nil else { return }
        tocDebounceWork?.cancel()
        let snapshot = parseResult
        // DispatchQueue.main.asyncAfter → work도 메인 스레드에서 실행됨
        let work = DispatchWorkItem { [weak self] in
            guard let callback = self?.onTOCEntriesChange else { return }
            let entries = extractTOCEntries(from: snapshot)
            callback(entries)
        }
        tocDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func applyBaseAttributes(to ranges: [NSRange], config: AppConfig) {
        let baseFont  = resolveFont(family: config.editor.font.family, size: config.editor.font.size)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = config.rendering.paragraph.lineHeight

        for range in ranges {
            guard range.length > 0, NSMaxRange(range) <= backing.length else { continue }
            backing.addAttributes([
                .font: baseFont,
                .foregroundColor: ThemeManager.shared.foregroundColor,
                .paragraphStyle: paragraphStyle
            ], range: range)
        }
    }

    private func filteredPatches(_ patches: [AttributePatch]) -> [AttributePatch] {
        guard let activeEditingBlockRange else { return patches }
        return patches.filter { NSIntersectionRange($0.range, activeEditingBlockRange).length == 0 }
    }

    private func reapplyRanges(previous: NSRange?, next: NSRange?) {
        let fullRange = NSRange(location: 0, length: backing.length)
        let targetRanges = normalizedRanges([previous, next].compactMap { $0 }, within: fullRange)
        guard !targetRanges.isEmpty else { return }

        let config = ConfigManager.shared.current
        applyBaseAttributes(to: targetRanges, config: config)

        let patches = filteredPatches(
            renderAttributes(from: parseResult, config: config, theme: ThemeManager.shared)
        ).filter { patch in
            targetRanges.contains { NSIntersectionRange($0, patch.range).length > 0 }
        }
        applyPatches(patches)

        notifyAttributeEditing(for: targetRanges)
    }

    private func editingBlockRange(containing selection: NSRange, in result: ParseResult, text: String) -> NSRange? {
        guard !text.isEmpty else { return nil }
        let length = (text as NSString).length
        let location = max(0, min(selection.location, length))

        if let emptyLineRange = emptyEditableLineRange(at: location, in: text) {
            return emptyLineRange
        }

        let lookupLocation = max(0, min(location, max(0, length - 1)))
        let line = lineNumber(at: lookupLocation, in: text)

        if let block = result.block(containingLine: line) {
            return lineAlignedRange(for: block.sourceRange, in: text, includeTrailingNewline: true)
        }

        let fallback = dirtyBlockRange(around: selection, in: text)
        return fallback.length > 0 ? fallback : nil
    }

    private func emptyEditableLineRange(at location: Int, in text: String) -> NSRange? {
        let lineRange = currentLineRange(containing: location, in: text)
        let lineText = (text as NSString).substring(with: lineRange)
        return lineText.trimmingCharacters(in: .whitespaces).isEmpty
            ? NSRange(location: lineRange.location, length: 0)
            : nil
    }

    private func normalizedRanges(_ ranges: [NSRange], within fullRange: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges {
            let safe = NSIntersectionRange(range, fullRange)
            guard safe.length > 0 else { continue }
            if result.contains(where: { NSEqualRanges($0, safe) }) { continue }
            result.append(safe)
        }
        return result.sorted { $0.location < $1.location }
    }

    private func applyPatches(_ patches: [AttributePatch]) {
        let length = backing.length
        for patch in patches {
            let safeRange = NSRange(
                location: patch.range.location,
                length: min(patch.range.length, max(0, length - patch.range.location))
            )
            guard safeRange.location >= 0, safeRange.length > 0,
                  NSMaxRange(safeRange) <= length else { continue }

            // AttributePatch.attrs의 Sendable 값을 NSAttributedString.Key dict로 변환
            var nsAttrs: [NSAttributedString.Key: Any] = [:]
            for (key, value) in patch.attrs { nsAttrs[key] = value }
            backing.addAttributes(nsAttrs, range: safeRange)
        }
    }

    private func notifyAttributeEditing(for ranges: [NSRange]) {
        let validRanges = ranges.filter { $0.length > 0 }
        guard !validRanges.isEmpty else { return }

        isApplyingAttributes = true
        beginEditing()
        for range in validRanges {
            edited(.editedAttributes, range: range, changeInLength: 0)
        }
        endEditing()
        isApplyingAttributes = false
    }
}
