import AppKit

// MARK: - FindReplacePanel

/// VSCode 스타일 찾기/바꾸기 플로팅 패널 (NSView 서브클래스).
/// 편집기 오른쪽 상단에 overlay로 표시.
final class FindReplacePanel: NSView {

    // MARK: - Callbacks

    var onQueryChange: ((String, Bool, Bool) -> Void)?   // query, useRegex, caseSensitive
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplaceCurrent: ((String) -> Void)?
    var onReplaceAll: ((String) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Heights

    private static let rowHeight: CGFloat   = 36
    private static let panelWidth: CGFloat  = 380
    private static let hPad: CGFloat        = 8
    private static let vPad: CGFloat        = 6

    // MARK: - Subviews

    private let backdrop          = NSVisualEffectView()
    private let findField         = NSTextField()
    private let replaceField      = NSTextField()
    private let matchLabel        = NSTextField(labelWithString: "")
    private let regexButton       = FindToggleButton(symbol: ".*", tooltip: String(localized: "find.tooltip.regex"))
    private let caseButton        = FindToggleButton(symbol: "Aa", tooltip: String(localized: "find.tooltip.caseSensitive"))
    private let prevButton        = FindIconButton(symbol: "chevron.up",   tooltip: String(localized: "find.tooltip.prev"))
    private let nextButton        = FindIconButton(symbol: "chevron.down", tooltip: String(localized: "find.tooltip.next"))
    private let closeButton       = FindIconButton(symbol: "xmark",        tooltip: String(localized: "find.tooltip.close"))
    private let replaceOneButton  = NSButton()
    private let replaceAllButton  = NSButton()
    private let replaceRowView    = NSView()

    private var showReplace: Bool = false

    private var heightConstraint: NSLayoutConstraint?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupAppearance()
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupAppearance() {
        wantsLayer = true
        layer?.cornerRadius  = 8
        layer?.masksToBounds = true
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius  = 6
        layer?.shadowOffset  = CGSize(width: 0, height: -2)

        backdrop.material       = .sidebar
        backdrop.blendingMode   = .withinWindow
        backdrop.state          = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupSubviews() {
        // 찾기 필드
        findField.placeholderString           = String(localized: "find.placeholder.find")
        findField.font                        = .systemFont(ofSize: 12)
        findField.focusRingType               = .none
        findField.bezelStyle                  = .roundedBezel
        findField.translatesAutoresizingMaskIntoConstraints = false
        findField.target                      = self
        findField.action                      = #selector(findFieldChanged)
        (findField.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false

        // 바꾸기 필드
        replaceField.placeholderString        = String(localized: "find.placeholder.replace")
        replaceField.font                     = .systemFont(ofSize: 12)
        replaceField.focusRingType            = .none
        replaceField.bezelStyle               = .roundedBezel
        replaceField.translatesAutoresizingMaskIntoConstraints = false

        // 매치 수 레이블
        matchLabel.font                       = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        matchLabel.textColor                  = .secondaryLabelColor
        matchLabel.alignment                  = .right
        matchLabel.translatesAutoresizingMaskIntoConstraints = false

        // 바꾸기 버튼
        configureTextButton(replaceOneButton, title: String(localized: "find.action.replace"))
        replaceOneButton.target = self
        replaceOneButton.action = #selector(replaceCurrent)

        configureTextButton(replaceAllButton, title: String(localized: "find.action.replaceAll"))
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll)

        // 바꾸기 행
        replaceRowView.translatesAutoresizingMaskIntoConstraints = false
        replaceRowView.isHidden = true
        addSubview(replaceRowView)

        [replaceField, replaceOneButton, replaceAllButton].forEach {
            replaceRowView.addSubview($0)
        }

        // 버튼 타깃
        prevButton.target  = self; prevButton.action  = #selector(goPrevious)
        nextButton.target  = self; nextButton.action  = #selector(goNext)
        closeButton.target = self; closeButton.action = #selector(closePanel)
        regexButton.target = self; regexButton.action = #selector(toggleChanged)
        caseButton.target  = self; caseButton.action  = #selector(toggleChanged)

        // 찾기 행 구성
        [findField, matchLabel, regexButton, caseButton, prevButton, nextButton, closeButton]
            .forEach { addSubview($0) }

        let h = Self.rowHeight
        let p = Self.hPad
        let v = Self.vPad

        // 찾기 행 레이아웃
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -p),
            closeButton.centerYAnchor.constraint(equalTo: topAnchor, constant: h / 2),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            nextButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            nextButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 22),
            nextButton.heightAnchor.constraint(equalToConstant: 22),

            prevButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -2),
            prevButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 22),
            prevButton.heightAnchor.constraint(equalToConstant: 22),

            matchLabel.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -4),
            matchLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            matchLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            caseButton.trailingAnchor.constraint(equalTo: matchLabel.leadingAnchor, constant: -4),
            caseButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            caseButton.widthAnchor.constraint(equalToConstant: 28),
            caseButton.heightAnchor.constraint(equalToConstant: 22),

            regexButton.trailingAnchor.constraint(equalTo: caseButton.leadingAnchor, constant: -2),
            regexButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            regexButton.widthAnchor.constraint(equalToConstant: 28),
            regexButton.heightAnchor.constraint(equalToConstant: 22),

            findField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: p),
            findField.trailingAnchor.constraint(equalTo: regexButton.leadingAnchor, constant: -4),
            findField.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            findField.heightAnchor.constraint(equalToConstant: 22),

            // 바꾸기 행
            replaceRowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            replaceRowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            replaceRowView.topAnchor.constraint(equalTo: topAnchor, constant: h),
            replaceRowView.heightAnchor.constraint(equalToConstant: h),

            replaceField.leadingAnchor.constraint(equalTo: replaceRowView.leadingAnchor, constant: p),
            replaceField.centerYAnchor.constraint(equalTo: replaceRowView.centerYAnchor),
            replaceField.heightAnchor.constraint(equalToConstant: 22),

            replaceOneButton.leadingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: 4),
            replaceOneButton.centerYAnchor.constraint(equalTo: replaceRowView.centerYAnchor),

            replaceAllButton.leadingAnchor.constraint(equalTo: replaceOneButton.trailingAnchor, constant: 4),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceRowView.centerYAnchor),
            replaceAllButton.trailingAnchor.constraint(lessThanOrEqualTo: replaceRowView.trailingAnchor, constant: -p),
        ])

        heightConstraint = heightAnchor.constraint(equalToConstant: h)
        heightConstraint?.isActive = true
        widthAnchor.constraint(equalToConstant: Self.panelWidth).isActive = true

        _ = v // suppress warning
    }

    private func configureTextButton(_ button: NSButton, title: String) {
        button.title           = title
        button.bezelStyle      = .rounded
        button.controlSize     = .small
        button.font            = .systemFont(ofSize: 11)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Public

    func setShowReplace(_ show: Bool) {
        showReplace = show
        replaceRowView.isHidden = !show
        let h = Self.rowHeight * (show ? 2 : 1)
        heightConstraint?.constant = h
    }

    func focusFindField() {
        findField.window?.makeFirstResponder(findField)
    }

    func updateMatchLabel(count: Int, currentIndex: Int) {
        if count == 0 {
            matchLabel.stringValue = findField.stringValue.isEmpty ? "" : String(localized: "find.result.none")
            matchLabel.textColor   = findField.stringValue.isEmpty ? .secondaryLabelColor : .systemRed
        } else {
            matchLabel.stringValue = "\(currentIndex + 1)/\(count)"
            matchLabel.textColor   = .secondaryLabelColor
        }
    }

    func setFindFieldError(_ hasError: Bool) {
        findField.backgroundColor = hasError ? NSColor.systemRed.withAlphaComponent(0.15) : nil
        findField.drawsBackground  = hasError
    }

    /// 현재 쿼리/옵션으로 onQueryChange를 재트리거 (텍스트 변경 후 재검색용).
    func triggerQueryChange() {
        fireQueryChange()
    }

    /// 현재 패널 상태(쿼리+옵션)를 이용해 모두 바꾸기 수행.
    func replaceAllWithCurrentQuery(engine: FindReplaceEngine) {
        let replacement = replaceField.stringValue
        let count = engine.replaceAll(
            with: replacement,
            query: findField.stringValue,
            useRegex: regexButton.isOn,
            caseSensitive: caseButton.isOn
        )
        updateMatchLabel(count: 0, currentIndex: -1)
        matchLabel.stringValue = count > 0
            ? String(format: NSLocalizedString("find.result.replaced", comment: ""), count)
            : String(localized: "find.result.none")
    }

    // MARK: - Actions

    @objc private func findFieldChanged() {
        fireQueryChange()
    }

    @objc private func toggleChanged() {
        fireQueryChange()
    }

    @objc private func goNext() {
        onNext?()
    }

    @objc private func goPrevious() {
        onPrevious?()
    }

    @objc private func closePanel() {
        onClose?()
    }

    @objc private func replaceCurrent() {
        onReplaceCurrent?(replaceField.stringValue)
    }

    @objc private func replaceAll() {
        onReplaceAll?(replaceField.stringValue)
    }

    private func fireQueryChange() {
        onQueryChange?(findField.stringValue, regexButton.isOn, caseButton.isOn)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onClose?()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 { // Return / numpad Enter
            if event.modifierFlags.contains(.shift) {
                onPrevious?()
            } else {
                onNext?()
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - NSControlTextEditingDelegate (실시간 검색)

extension FindReplacePanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === findField else { return }
        fireQueryChange()
    }
}

// MARK: - FindToggleButton (텍스트 토글)

private final class FindToggleButton: NSButton {
    var isOn: Bool = false {
        didSet { updateAppearance() }
    }

    convenience init(symbol: String, tooltip: String) {
        self.init(frame: .zero)
        title                   = symbol
        font                    = .monospacedSystemFont(ofSize: 11, weight: .medium)
        bezelStyle              = .rounded
        isBordered              = true
        controlSize             = .small
        toolTip                 = tooltip
        translatesAutoresizingMaskIntoConstraints = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        sendAction(action, to: target)
    }

    private func updateAppearance() {
        contentTintColor = isOn ? .controlAccentColor : .secondaryLabelColor
    }
}

// MARK: - FindIconButton (SF Symbol 버튼)

private final class FindIconButton: NSButton {
    convenience init(symbol: String, tooltip: String) {
        self.init(frame: .zero)
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        image               = img
        imagePosition       = .imageOnly
        bezelStyle          = .smallSquare
        isBordered          = false
        contentTintColor    = .secondaryLabelColor
        toolTip             = tooltip
        translatesAutoresizingMaskIntoConstraints = false
    }
}
