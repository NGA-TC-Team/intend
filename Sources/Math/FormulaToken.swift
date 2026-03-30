import Foundation

// MARK: - Model

struct FormulaToken: Equatable {
    enum Kind: Equatable {
        case inlineLatex   // $...$
        case blockLatex    // $$...$$
        case mermaid       // ```mermaid...```
    }
    let kind: Kind
    let range: NSRange   // 원본 텍스트 내 전체 범위 (delimiter 포함)
    let content: String  // 렌더링 대상 내용 (delimiter 제외)
}

// MARK: - Scanner (순수 함수)

/// 텍스트에서 LaTeX/Mermaid 토큰을 순서대로 스캔.
/// 중첩 없음, 먼저 발견된 토큰이 우선.
func scanFormulaTokens(in text: String) -> [FormulaToken] {
    guard !text.isEmpty else { return [] }

    var tokens: [FormulaToken] = []
    let ns  = text as NSString
    let len = ns.length
    var i   = 0

    while i < len {
        // $$...$$ (blockLatex) — $$ 를 $보다 먼저 검사
        if i + 1 < len,
           ns.character(at: i) == 0x24,
           ns.character(at: i + 1) == 0x24
        {
            if let closeIdx = findDoubleDollar(in: ns, from: i + 2) {
                let fullRange    = NSRange(location: i, length: closeIdx + 2 - i)
                let contentLen   = closeIdx - (i + 2)
                let content      = contentLen > 0
                    ? ns.substring(with: NSRange(location: i + 2, length: contentLen))
                    : ""
                tokens.append(FormulaToken(kind: .blockLatex, range: fullRange,
                                           content: content.trimmingCharacters(in: .whitespacesAndNewlines)))
                i = closeIdx + 2
                continue
            }
        }

        // $...$ (inlineLatex) — 단일 줄만 허용
        if ns.character(at: i) == 0x24 {
            if let closeIdx = findSingleDollar(in: ns, from: i + 1) {
                let contentLen = closeIdx - (i + 1)
                let content    = contentLen > 0
                    ? ns.substring(with: NSRange(location: i + 1, length: contentLen))
                    : ""
                if !content.isEmpty {
                    let fullRange = NSRange(location: i, length: closeIdx + 1 - i)
                    tokens.append(FormulaToken(kind: .inlineLatex, range: fullRange, content: content))
                    i = closeIdx + 1
                    continue
                }
            }
        }

        // ```mermaid...```
        if i + 9 < len,
           ns.character(at: i)     == 0x60,  // `
           ns.character(at: i + 1) == 0x60,
           ns.character(at: i + 2) == 0x60,
           ns.length >= i + 10,
           ns.substring(with: NSRange(location: i + 3, length: 7)) == "mermaid"
        {
            let afterHeader = i + 10
            if let closeIdx = findTripleBacktick(in: ns, from: afterHeader) {
                let fullRange    = NSRange(location: i, length: closeIdx + 3 - i)
                let contentLen   = closeIdx - afterHeader
                let rawContent   = contentLen > 0
                    ? ns.substring(with: NSRange(location: afterHeader, length: contentLen))
                    : ""
                tokens.append(FormulaToken(kind: .mermaid, range: fullRange,
                                           content: rawContent.trimmingCharacters(in: .newlines)))
                i = closeIdx + 3
                continue
            }
        }

        i += 1
    }
    return tokens
}

// MARK: - Private helpers

/// `$$` 닫는 위치 탐색
private func findDoubleDollar(in ns: NSString, from start: Int) -> Int? {
    let len = ns.length
    var i   = start
    while i + 1 < len {
        if ns.character(at: i) == 0x24, ns.character(at: i + 1) == 0x24 { return i }
        i += 1
    }
    return nil
}

/// `$` 닫는 위치 탐색 (줄바꿈에서 중단)
private func findSingleDollar(in ns: NSString, from start: Int) -> Int? {
    var i = start
    while i < ns.length {
        let c = ns.character(at: i)
        if c == 0x0A { return nil }   // newline → 인라인 수식 끝
        if c == 0x24 { return i }     // '$'
        i += 1
    }
    return nil
}

/// ` ``` ` 닫는 위치 탐색
private func findTripleBacktick(in ns: NSString, from start: Int) -> Int? {
    let len = ns.length
    var i   = start
    while i + 2 < len {
        if ns.character(at: i)     == 0x60,
           ns.character(at: i + 1) == 0x60,
           ns.character(at: i + 2) == 0x60 { return i }
        i += 1
    }
    return nil
}
