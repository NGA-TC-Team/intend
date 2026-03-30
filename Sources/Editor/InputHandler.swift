import Foundation

// MARK: - Result type

/// 키 입력 변환 결과.
/// nil → 기본 NSTextView 동작 수행.
struct EditResult {
    /// backing store의 range를 대체할 텍스트
    let text:   String
    /// 교체할 범위
    let range:  NSRange
    /// 적용 후 설정할 커서/선택 범위
    let cursor: NSRange
}

// MARK: - Auto-pair

/// 자동 쌍 문자 삽입.
/// 우선순위: (1) 선택 영역 wrapping → (2) skip-over → (3) ( after ] → (4) pair 삽입
func autoPairEdit(
    typed char: String,
    in text: String,
    selectedRange sel: NSRange
) -> EditResult? {
    guard char.count == 1, let ch = char.unicodeScalars.first.map(Character.init) else { return nil }

    let ns      = text as NSString
    let cursor  = sel.location

    // (1) 선택 영역 wrapping: _text_, *text*, `text`
    if sel.length > 0, wrapChars.contains(ch) {
        let close   = pairMap[ch].map(String.init) ?? char
        let inner   = ns.substring(with: sel)
        let wrapped = char + inner + close
        return EditResult(
            text:   wrapped,
            range:  sel,
            cursor: NSRange(location: sel.location + char.count, length: sel.length)
        )
    }

    guard sel.length == 0 else { return nil }

    // (2) skip-over: 커서 오른쪽이 닫힘 문자일 때 그냥 통과
    if skipOverChars.contains(ch), cursor < ns.length {
        let next = ns.substring(with: NSRange(location: cursor, length: 1))
        if next == char {
            return EditResult(
                text:   "",
                range:  NSRange(location: cursor, length: 0),
                cursor: NSRange(location: cursor + 1, length: 0)
            )
        }
    }

    // (3) ( → ] 바로 뒤에서만 auto-pair
    if ch == "(" {
        guard cursor > 0,
              ns.substring(with: NSRange(location: cursor - 1, length: 1)) == "]"
        else { return nil }
        return EditResult(
            text:   "()",
            range:  NSRange(location: cursor, length: 0),
            cursor: NSRange(location: cursor + 1, length: 0)
        )
    }

    // (4) 일반 pair 삽입: _ → _|_, ` → `|`, [ → [|]
    guard let close = pairMap[ch] else { return nil }
    return EditResult(
        text:   char + String(close),
        range:  NSRange(location: cursor, length: 0),
        cursor: NSRange(location: cursor + 1, length: 0)
    )
}

private let pairMap: [Character: Character] = [
    "_": "_",
    "`": "`",
    "[": "]",
]

private let wrapChars: Set<Character>     = ["_", "`", "*"]
private let skipOverChars: Set<Character> = ["_", "`", "]", ")"]

// MARK: - Smart Enter

/// 리스트 항목에서 Enter: 다음 항목 자동 생성.
/// 빈 항목에서 Enter: 프리픽스 제거 (리스트 종료).
func smartEnterEdit(in text: String, selectedRange sel: NSRange) -> EditResult? {
    guard sel.length == 0 else { return nil }

    let ns  = text as NSString
    let pos = sel.location

    let lineStart = currentLineStart(at: pos, in: ns)
    let lineEnd   = currentLineEnd(at: pos, in: ns)
    let fullLine  = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))

    guard let prefix = listPrefix(in: fullLine) else { return nil }

    // 빈 리스트 아이템 (프리픽스만 존재) → 프리픽스 삭제
    if fullLine == prefix {
        return EditResult(
            text:   "",
            range:  NSRange(location: lineStart, length: prefix.count),
            cursor: NSRange(location: lineStart, length: 0)
        )
    }

    // 새 아이템 삽입
    let next = nextListPrefix(for: prefix)
    return EditResult(
        text:   "\n" + next,
        range:  sel,
        cursor: NSRange(location: pos + 1 + next.count, length: 0)
    )
}

// MARK: - Smart Tab / Shift+Tab

/// 리스트 항목에서 Tab: 2 공백 들여쓰기.
/// Shift+Tab: 2 공백 내어쓰기.
/// 비리스트 컨텍스트 → nil (기본 동작).
func smartTabEdit(in text: String, selectedRange sel: NSRange, dedent: Bool) -> EditResult? {
    let ns  = text as NSString
    let pos = sel.location

    let lineStart = currentLineStart(at: pos, in: ns)
    let lineEnd   = currentLineEnd(at: pos, in: ns)
    let fullLine  = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))

    guard listPrefix(in: fullLine) != nil else { return nil }

    let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)

    if dedent {
        guard fullLine.hasPrefix("  ") else { return nil }
        let newLine   = String(fullLine.dropFirst(2))
        let newCursor = max(lineStart, pos - 2)
        return EditResult(
            text:   newLine,
            range:  lineRange,
            cursor: NSRange(location: newCursor, length: 0)
        )
    } else {
        return EditResult(
            text:   "  " + fullLine,
            range:  lineRange,
            cursor: NSRange(location: pos + 2, length: 0)
        )
    }
}

// MARK: - Smart Backspace

/// 커서가 빈 쌍 문자 사이에 있을 때 양쪽 동시 삭제.
/// 예: `_|_`, `[|]`, `(|)`, `` `|` ``
func smartBackspaceEdit(in text: String, selectedRange sel: NSRange) -> EditResult? {
    guard sel.length == 0, sel.location > 0 else { return nil }

    let ns  = text as NSString
    let pos = sel.location
    guard pos < ns.length else { return nil }

    let prev = ns.substring(with: NSRange(location: pos - 1, length: 1))
    let next = ns.substring(with: NSRange(location: pos,     length: 1))

    let pairs: [(String, String)] = [
        ("_", "_"), ("`", "`"), ("[", "]"), ("(", ")"), ("\"", "\""),
    ]
    guard pairs.contains(where: { $0.0 == prev && $0.1 == next }) else { return nil }

    return EditResult(
        text:   "",
        range:  NSRange(location: pos - 1, length: 2),
        cursor: NSRange(location: pos - 1, length: 0)
    )
}

// MARK: - Private helpers

private func currentLineStart(at pos: Int, in ns: NSString) -> Int {
    var start = pos
    while start > 0 {
        if ns.substring(with: NSRange(location: start - 1, length: 1)) == "\n" { break }
        start -= 1
    }
    return start
}

private func currentLineEnd(at pos: Int, in ns: NSString) -> Int {
    var end = pos
    while end < ns.length {
        if ns.substring(with: NSRange(location: end, length: 1)) == "\n" { break }
        end += 1
    }
    return end
}

/// "- ", "* ", "+ ", "1. " 등 리스트 프리픽스 감지 (선행 공백 포함).
private func listPrefix(in line: String) -> String? {
    // 비순서: (공백*)([-*+])[ ]
    if let m = line.firstMatch(of: /^(\s*)([-*+])[ ]/) {
        return String(line[m.range])
    }
    // 순서: (공백*)(\d+)[.][ ]
    if let m = line.firstMatch(of: /^(\s*)(\d+)[.][ ]/) {
        return String(line[m.range])
    }
    return nil
}

/// 순서 목록 프리픽스 → 다음 번호. 비순서는 그대로 반환.
private func nextListPrefix(for prefix: String) -> String {
    if let m = prefix.firstMatch(of: /^(\s*)(\d+)[.][ ]/) {
        let indent = String(m.output.1)
        let num    = Int(m.output.2)!
        return "\(indent)\(num + 1). "
    }
    return prefix
}
