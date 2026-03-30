import Foundation

/// `swift-markdown`의 `SourceSpan`을 AppKit/Foundation이 쓰는 `NSRange`로 변환한다.
/// upperBound는 exclusive column으로 취급한다.
func nsRange(for span: SourceSpan, in text: String) -> NSRange? {
    guard !span.isUnknown else { return nil }

    let lines = text.components(separatedBy: "\n")
    guard span.startLine >= 1,
          span.endLine >= span.startLine,
          span.startLine <= lines.count,
          span.endLine <= lines.count else {
        return nil
    }

    let startLineText = lines[span.startLine - 1] as NSString
    let endLineText = lines[span.endLine - 1] as NSString

    let startColumn = max(1, min(span.startColumn, startLineText.length + 1))
    let endColumn = max(1, min(span.endColumn, endLineText.length + 1))

    let startOffset = lines.prefix(span.startLine - 1)
        .reduce(0) { $0 + ($1 as NSString).length + 1 } + (startColumn - 1)
    let endOffset = lines.prefix(span.endLine - 1)
        .reduce(0) { $0 + ($1 as NSString).length + 1 } + (endColumn - 1)

    let length = max(0, endOffset - startOffset)
    let textLength = (text as NSString).length
    guard startOffset >= 0, startOffset + length <= textLength else { return nil }
    return NSRange(location: startOffset, length: length)
}

/// 블록 전체 줄 범위를 반환한다. 필요하면 trailing newline까지 포함한다.
func lineAlignedRange(for span: SourceSpan, in text: String, includeTrailingNewline: Bool = false) -> NSRange? {
    guard !span.isUnknown else { return nil }

    let lines = text.components(separatedBy: "\n")
    guard span.startLine >= 1,
          span.endLine >= span.startLine,
          span.startLine <= lines.count,
          span.endLine <= lines.count else {
        return nil
    }

    let startOffset = lineStart(line: span.startLine, in: text)
    let endLineStart = lineStart(line: span.endLine, in: text)
    let endLineLength = (lines[span.endLine - 1] as NSString).length
    var endOffset = endLineStart + endLineLength

    let textLength = (text as NSString).length
    if includeTrailingNewline, endOffset < textLength {
        let nextChar = (text as NSString).substring(with: NSRange(location: endOffset, length: 1))
        if nextChar == "\n" {
            endOffset += 1
        }
    }

    guard startOffset >= 0, endOffset >= startOffset, endOffset <= textLength else { return nil }
    return NSRange(location: startOffset, length: endOffset - startOffset)
}

/// 선택이 위치한 현재 줄 범위를 반환한다.
func currentLineRange(containing location: Int, in text: String) -> NSRange {
    let nsText = text as NSString
    let safeLocation = min(max(0, location), nsText.length)

    if nsText.length == 0 {
        return NSRange(location: 0, length: 0)
    }

    let lineStartOffset = lineStart(line: lineNumber(at: safeLocation, in: text), in: text)
    var lineEndOffset = lineStartOffset
    while lineEndOffset < nsText.length {
        if nsText.substring(with: NSRange(location: lineEndOffset, length: 1)) == "\n" {
            break
        }
        lineEndOffset += 1
    }

    return NSRange(location: lineStartOffset, length: lineEndOffset - lineStartOffset)
}
