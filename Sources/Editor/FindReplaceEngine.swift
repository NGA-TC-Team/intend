import AppKit

// MARK: - FindReplaceEngineDelegate

@MainActor
protocol FindReplaceEngineDelegate: AnyObject {
    func engineDidUpdateMatches(count: Int, currentIndex: Int)
}

// MARK: - FindReplaceEngine

/// 문서 내 찾기/바꾸기 로직. NSLayoutManager의 temporaryAttributes로 비파괴 하이라이트.
@MainActor
final class FindReplaceEngine {

    weak var textView: NSTextView?
    weak var delegate: FindReplaceEngineDelegate?

    private(set) var matches: [NSRange] = []
    private(set) var currentIndex: Int = -1

    // MARK: - 검색

    func search(query: String, useRegex: Bool, caseSensitive: Bool) {
        clearHighlights()
        matches = []
        currentIndex = -1

        guard let textView,
              !query.isEmpty,
              let text = textView.textStorage?.string,
              !text.isEmpty else {
            delegate?.engineDidUpdateMatches(count: 0, currentIndex: -1)
            return
        }

        let pattern: String
        if useRegex {
            pattern = query
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }

        var options: NSRegularExpression.Options = []
        if !caseSensitive { options.insert(.caseInsensitive) }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            delegate?.engineDidUpdateMatches(count: 0, currentIndex: -1)
            return
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        matches = regex.matches(in: text, options: [], range: fullRange).map(\.range)

        highlightAll()

        // 현재 커서 위치 기준으로 가장 가까운 다음 매치 선택
        if !matches.isEmpty {
            let cursorLoc = textView.selectedRange().location
            currentIndex = matches.firstIndex(where: { $0.location >= cursorLoc }) ?? 0
            highlightCurrent()
            scrollToCurrent()
        }

        delegate?.engineDidUpdateMatches(count: matches.count, currentIndex: currentIndex)
    }

    // MARK: - 이전/다음

    func selectNext() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        highlightCurrent()
        scrollToCurrent()
        delegate?.engineDidUpdateMatches(count: matches.count, currentIndex: currentIndex)
    }

    func selectPrevious() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        highlightCurrent()
        scrollToCurrent()
        delegate?.engineDidUpdateMatches(count: matches.count, currentIndex: currentIndex)
    }

    // MARK: - 바꾸기

    func replaceCurrent(with replacement: String) {
        guard !matches.isEmpty,
              currentIndex >= 0,
              currentIndex < matches.count,
              let textView else { return }

        let range = matches[currentIndex]
        guard let storage = textView.textStorage else { return }

        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()

        // 바꾼 후 동일 쿼리로 재검색 (인덱스는 엔진 외부에서 유지)
        // 호출 측에서 search를 다시 호출하도록 위임
    }

    func replaceAll(with replacement: String, query: String, useRegex: Bool, caseSensitive: Bool) -> Int {
        guard let textView,
              !query.isEmpty,
              let storage = textView.textStorage else { return 0 }

        let pattern: String
        if useRegex {
            pattern = query
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }

        var regexOptions: NSRegularExpression.Options = []
        if !caseSensitive { regexOptions.insert(.caseInsensitive) }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else { return 0 }

        let text = storage.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let allMatches = regex.matches(in: text, options: [], range: fullRange).map(\.range)
        guard !allMatches.isEmpty else { return 0 }

        // 뒤에서 앞으로 교체 (범위 오프셋 변화 방지)
        storage.beginEditing()
        for matchRange in allMatches.reversed() {
            storage.replaceCharacters(in: matchRange, with: replacement)
        }
        storage.endEditing()

        clearHighlights()
        matches = []
        currentIndex = -1
        delegate?.engineDidUpdateMatches(count: 0, currentIndex: -1)
        return allMatches.count
    }

    // MARK: - 하이라이트

    func clearHighlights() {
        guard let textView,
              let storage = textView.textStorage,
              let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    }

    private func highlightAll() {
        guard let textView,
              let layoutManager = textView.layoutManager else { return }

        let dimColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for range in matches {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: dimColor, forCharacterRange: range)
        }
    }

    private func highlightCurrent() {
        guard let textView,
              let layoutManager = textView.layoutManager,
              currentIndex >= 0,
              currentIndex < matches.count else { return }

        // 전체 하이라이트 재적용 후 현재 매치는 더 진하게
        highlightAll()
        let currentRange = matches[currentIndex]
        let activeColor = NSColor.systemOrange.withAlphaComponent(0.65)
        layoutManager.addTemporaryAttribute(.backgroundColor, value: activeColor, forCharacterRange: currentRange)
        textView.setSelectedRange(currentRange)
    }

    private func scrollToCurrent() {
        guard let textView,
              currentIndex >= 0,
              currentIndex < matches.count else { return }
        textView.scrollRangeToVisible(matches[currentIndex])
    }
}
