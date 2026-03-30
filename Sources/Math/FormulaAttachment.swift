import AppKit

// MARK: - NSTextAttachment 서브클래스

/// LaTeX/Mermaid 렌더링 결과를 NSTextAttachment으로 감싸는 래퍼.
/// rawSource 를 보관해 커서 재진입 시 원본 텍스트 복원에 사용.
final class FormulaAttachment: NSTextAttachment {

    let kind:      FormulaToken.Kind
    let rawSource: String   // 원본 토큰 전체 ($$...$$ / ```mermaid...``` 포함)

    init(image: NSImage, kind: FormulaToken.Kind, rawSource: String) {
        self.kind      = kind
        self.rawSource = rawSource
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Attributed string helper

extension FormulaAttachment {
    /// FormulaAttachment 를 단일 attachment 문자(U+FFFC) NSAttributedString 으로 래핑.
    var attributedString: NSAttributedString {
        NSAttributedString(attachment: self)
    }
}

// MARK: - Placeholder image (JS 없이 fallback)

/// KaTeX/Mermaid JS 없을 때 사용하는 placeholder 이미지.
func makePlaceholderImage(for content: String, kind: FormulaToken.Kind) -> NSImage {
    let isMermaid  = kind == .mermaid
    let width: CGFloat  = isMermaid ? 280 : CGFloat(max(80, content.count * 7 + 24))
    let height: CGFloat = isMermaid ? 80  : 26
    let size = CGSize(width: width, height: height)

    return NSImage(size: size, flipped: false) { rect in
        // 배경
        NSColor.systemYellow.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()

        // 테두리
        NSColor.systemOrange.withAlphaComponent(0.4).setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        path.lineWidth = 0.5
        path.stroke()

        // 레이블
        let label = isMermaid ? "mermaid" : content
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.systemOrange,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let textSize = str.size()
        let textRect = NSRect(
            x: (rect.width  - textSize.width)  / 2,
            y: (rect.height - textSize.height) / 2,
            width: textSize.width, height: textSize.height
        )
        str.draw(in: textRect)
        return true
    }
}
