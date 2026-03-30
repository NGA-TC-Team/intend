import Foundation

// MARK: - Incremental parsing (순수 함수)

/// 편집된 NSRange 주변의 "더티 블록"을 감지해 해당 블록만 재파싱.
/// 마크다운은 빈 줄(\n\n)이 블록 경계이므로, 빈 줄 사이 구간만 재파싱.

/// 편집된 range를 포함하는 블록 경계(빈 줄 사이) NSRange 반환.
func dirtyBlockRange(around editedRange: NSRange, in text: String) -> NSRange {
    guard !text.isEmpty else { return NSRange(location: 0, length: 0) }

    let nsText   = text as NSString
    let length   = nsText.length
    let editStart = min(editedRange.location, length)
    let editEnd   = min(NSMaxRange(editedRange), length)

    // 앞 방향: 빈 줄(\n\n) 또는 문서 시작 탐색
    var blockStart = editStart
    while blockStart > 0 {
        // 이전 두 문자가 \n\n이면 현재 위치가 블록 시작
        if blockStart >= 2,
           nsText.substring(with: NSRange(location: blockStart - 2, length: 2)) == "\n\n" {
            break
        }
        blockStart -= 1
    }

    // 뒤 방향: 빈 줄(\n\n) 또는 문서 끝 탐색
    var blockEnd = editEnd
    while blockEnd < length {
        if blockEnd + 1 < length,
           nsText.substring(with: NSRange(location: blockEnd, length: 2)) == "\n\n" {
            break
        }
        blockEnd += 1
    }

    return NSRange(location: blockStart, length: blockEnd - blockStart)
}

/// 이전 ParseResult와 새 텍스트를 받아 최소한의 재파싱 수행.
/// - editedRange: NSTextStorage가 보고한 변경 범위
/// - 반환: 업데이트된 ParseResult
func reparseIncremental(
    newText: String,
    editedRange: NSRange,
    previous: ParseResult
) -> ParseResult {
    // 현재 구현: 전체 재파싱 (Phase 3에서 진짜 증분으로 교체 예정)
    // 이 함수의 시그니처와 호출 지점은 유지하면서 내부만 교체
    parse(markdown: newText)
}

// MARK: - Line utilities (순수 함수)

/// 문자열에서 특정 NSRange가 속한 줄 번호(1-based) 반환
func lineNumber(at location: Int, in text: String) -> Int {
    guard location > 0 else { return 1 }
    let prefix = (text as NSString).substring(to: min(location, (text as NSString).length))
    return prefix.components(separatedBy: "\n").count
}

/// 줄 번호(1-based)를 해당 줄 시작 NSRange.location으로 변환
func lineStart(line: Int, in text: String) -> Int {
    let lines = text.components(separatedBy: "\n")
    guard line > 0 && line <= lines.count else { return 0 }
    return lines.prefix(line - 1).reduce(0) { $0 + $1.utf16.count + 1 }
}
