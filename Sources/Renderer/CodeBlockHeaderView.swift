import AppKit

// MARK: - CodeBlockHeaderView

/// 코드 블록 우측 상단에 배치되는 오버레이 뷰.
/// 언어 레이블 + 클립보드 복사 버튼을 표시.
final class CodeBlockHeaderView: NSView {

    // MARK: State

    var onCopy: (() -> Void)?

    // MARK: Subviews

    private let languageLabel = NSTextField(labelWithString: "")
    private let copyButton    = NSButton()

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 4

        // 언어 레이블
        languageLabel.font      = .systemFont(ofSize: 10)
        languageLabel.textColor = .tertiaryLabelColor
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(languageLabel)

        // 복사 버튼
        copyButton.bezelStyle      = .regularSquare
        copyButton.isBordered      = false
        copyButton.image           = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: String(localized: "action.copy"))
        copyButton.imageScaling    = .scaleProportionallyUpOrDown
        copyButton.contentTintColor = .tertiaryLabelColor
        copyButton.toolTip         = String(localized: "action.copy")
        copyButton.target          = self
        copyButton.action          = #selector(didClickCopy)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            languageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            languageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 16),
            copyButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Public

    func configure(language: String?) {
        languageLabel.stringValue = language?.capitalized ?? ""
    }

    // MARK: Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }

    private func updateBackground() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = isDark
            ? NSColor(white: 0.22, alpha: 0.90).cgColor
            : NSColor(white: 0.94, alpha: 0.90).cgColor
    }

    // MARK: Actions

    @objc private func didClickCopy() {
        onCopy?()
        // 시각적 피드백: 아이콘 일시 변경
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: String(localized: "action.copied"))
        copyButton.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: String(localized: "action.copy"))
            self?.copyButton.contentTintColor = .tertiaryLabelColor
        }
    }
}
