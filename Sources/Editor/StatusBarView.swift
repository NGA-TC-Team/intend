import AppKit

// MARK: - StatusBarView

/// 편집기 하단 24pt 상태바.
/// 글자 수(공백 포함/제외), 마지막 편집 시각, 맨 위/아래 이동 버튼을 표시.
final class StatusBarView: NSView {

    // MARK: - Subviews

    private let countLabel  = NSTextField(labelWithString: "")
    private let timeLabel   = NSTextField(labelWithString: "")
    private let separator   = NSBox()
    private let topButton   = NSButton()
    private let bottomButton = NSButton()

    // MARK: - Callbacks

    var onScrollToTop:    (() -> Void)?
    var onScrollToBottom: (() -> Void)?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // 상단 구분선
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // 글자 수 레이블 (좌측)
        countLabel.font      = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        // 마지막 편집 시각 레이블 (중앙-우측)
        timeLabel.font      = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        // 맨 위 / 맨 아래 버튼 (우측 끝)
        configureNavButton(topButton,    symbolName: "arrow.up",   action: #selector(scrollToTop))
        configureNavButton(bottomButton, symbolName: "arrow.down", action: #selector(scrollToBottom))

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 버튼: 우측 끝에 붙임
            bottomButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bottomButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomButton.widthAnchor.constraint(equalToConstant: 20),
            bottomButton.heightAnchor.constraint(equalToConstant: 20),

            topButton.trailingAnchor.constraint(equalTo: bottomButton.leadingAnchor, constant: -2),
            topButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            topButton.widthAnchor.constraint(equalToConstant: 20),
            topButton.heightAnchor.constraint(equalToConstant: 20),

            // 시각 레이블: 버튼 왼쪽
            timeLabel.trailingAnchor.constraint(equalTo: topButton.leadingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Private setup

    private func configureNavButton(_ button: NSButton, symbolName: String, action: Selector) {
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        button.image               = img
        button.imagePosition       = .imageOnly
        button.bezelStyle          = .smallSquare
        button.isBordered          = false
        button.contentTintColor    = .secondaryLabelColor
        button.target              = self
        button.action              = action
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
    }

    // MARK: - Actions

    @objc private func scrollToTop() {
        onScrollToTop?()
    }

    @objc private func scrollToBottom() {
        onScrollToBottom?()
    }

    // MARK: - Public

    func update(charCount: Int, nonSpaceCount: Int, lastEdited: Date?) {
        let formatter = NumberFormatter.intGrouped
        let total = formatter.string(from: NSNumber(value: charCount))     ?? "\(charCount)"
        let noSpc = formatter.string(from: NSNumber(value: nonSpaceCount)) ?? "\(nonSpaceCount)"
        countLabel.stringValue = String(format: NSLocalizedString("statusbar.count", comment: ""), total, noSpc)

        if let date = lastEdited {
            timeLabel.stringValue = DateFormatter.editedString(from: date)
        } else {
            timeLabel.stringValue = ""
        }
    }
}

// MARK: - DateFormatter helpers

private extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func editedString(from date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return String(format: NSLocalizedString("statusbar.today", comment: ""), timeOnly.string(from: date))
        } else {
            return dateTime.string(from: date)
        }
    }
}

// MARK: - NumberFormatter helper

private extension NumberFormatter {
    static let intGrouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle   = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()
}
