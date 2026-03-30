import AppKit

// MARK: - 비밀번호 입력 시트

/// 암호화 저장(save) 또는 복호화(open) 시 비밀번호를 받는 모달 시트.
///
/// 사용법:
/// ```swift
/// PasswordSheetController.promptForEncrypt(relativeTo: window) { password in
///     // password == nil → 취소
/// }
/// PasswordSheetController.promptForDecrypt(relativeTo: window) { password in … }
/// ```
@MainActor
enum PasswordSheetController {

    // MARK: - Public entry points

    /// 암호화 저장 모드: 비밀번호 + 확인 필드 두 개.
    static func promptForEncrypt(
        relativeTo window: NSWindow,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        present(mode: .encrypt, relativeTo: window, completion: completion)
    }

    /// 복호화 모드: 비밀번호 필드 하나.
    static func promptForDecrypt(
        relativeTo window: NSWindow,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        present(mode: .decrypt, relativeTo: window, completion: completion)
    }

    // MARK: - Private

    private enum Mode { case encrypt, decrypt }

    private static func present(
        mode: Mode,
        relativeTo window: NSWindow,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = mode == .encrypt
            ? String(localized: "encryption.title.save")
            : String(localized: "encryption.title.unlock")
        alert.informativeText = mode == .encrypt
            ? String(localized: "encryption.info.save")
            : String(localized: "encryption.info.open")
        alert.alertStyle = .informational
        alert.addButton(withTitle: mode == .encrypt ? String(localized: "encryption.action.save") : String(localized: "action.open"))
        alert.addButton(withTitle: String(localized: "action.cancel"))

        if mode == .encrypt {
            let container = EncryptPasswordView()
            alert.accessoryView = container

            // 확인 버튼: 유효성 통과 전까지 비활성
            if let confirmButton = alert.buttons.first {
                confirmButton.isEnabled = false
                container.onValidationChanged = { isValid in
                    confirmButton.isEnabled = isValid
                }
            }

            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else {
                    completion(nil); return
                }
                completion(container.password)
            }
        } else {
            let container = DecryptPasswordView()
            alert.accessoryView = container

            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else {
                    completion(nil); return
                }
                let p = container.password
                guard !p.isEmpty else {
                    Self.showError(String(localized: "encryption.error.empty"), in: window) {
                        Self.present(mode: mode, relativeTo: window, completion: completion)
                    }
                    return
                }
                completion(p)
            }
        }
    }

    private static func showError(
        _ message: String,
        in window: NSWindow,
        completion: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle  = .warning
        alert.addButton(withTitle: String(localized: "action.confirm"))
        alert.beginSheetModal(for: window) { _ in completion() }
    }
}

// MARK: - 암호화 모드 뷰 (비밀번호 + 확인 + 유효성 메시지)

private final class EncryptPasswordView: NSView, NSTextFieldDelegate {

    var onValidationChanged: ((Bool) -> Void)?

    private(set) var password: String = ""

    private let fieldWidth: CGFloat = 360
    private let fieldHeight: CGFloat = 26

    private lazy var pw1Field: NSSecureTextField = makeField(placeholder: String(localized: "encryption.placeholder.password"))
    private lazy var pw2Field: NSSecureTextField = makeField(placeholder: String(localized: "encryption.placeholder.confirm"))

    private lazy var validationLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 84))
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        pw1Field.delegate = self
        pw2Field.delegate = self

        addSubview(pw1Field)
        addSubview(pw2Field)
        addSubview(validationLabel)

        pw1Field.translatesAutoresizingMaskIntoConstraints = false
        pw2Field.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pw1Field.topAnchor.constraint(equalTo: topAnchor),
            pw1Field.leadingAnchor.constraint(equalTo: leadingAnchor),
            pw1Field.trailingAnchor.constraint(equalTo: trailingAnchor),
            pw1Field.heightAnchor.constraint(equalToConstant: fieldHeight),

            pw2Field.topAnchor.constraint(equalTo: pw1Field.bottomAnchor, constant: 8),
            pw2Field.leadingAnchor.constraint(equalTo: leadingAnchor),
            pw2Field.trailingAnchor.constraint(equalTo: trailingAnchor),
            pw2Field.heightAnchor.constraint(equalToConstant: fieldHeight),

            validationLabel.topAnchor.constraint(equalTo: pw2Field.bottomAnchor, constant: 4),
            validationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            validationLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // 레이어 기반 테두리 준비
        pw1Field.wantsLayer = true
        pw2Field.wantsLayer = true
        applyBorder(to: pw1Field, state: .neutral)
        applyBorder(to: pw2Field, state: .neutral)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        validate()
    }

    // MARK: - Validation

    private enum FieldState { case neutral, error, success }

    private func validate() {
        let p1 = pw1Field.stringValue
        let p2 = pw2Field.stringValue

        // pw1 비어있으면 중립
        if p1.isEmpty {
            applyBorder(to: pw1Field, state: .neutral)
            applyBorder(to: pw2Field, state: .neutral)
            setValidation(message: "", color: .secondaryLabelColor)
            onValidationChanged?(false)
            return
        }

        // pw1에 내용 있으면 pw2 비교 시작
        if p2.isEmpty {
            applyBorder(to: pw1Field, state: .neutral)
            applyBorder(to: pw2Field, state: .neutral)
            setValidation(message: "", color: .secondaryLabelColor)
            onValidationChanged?(false)
            return
        }

        if p1 == p2 {
            applyBorder(to: pw1Field, state: .success)
            applyBorder(to: pw2Field, state: .success)
            setValidation(message: String(localized: "encryption.validation.match"), color: .systemGreen)
            password = p1
            onValidationChanged?(true)
        } else {
            applyBorder(to: pw1Field, state: .neutral)
            applyBorder(to: pw2Field, state: .error)
            setValidation(message: String(localized: "encryption.validation.mismatch"), color: .systemRed)
            password = ""
            onValidationChanged?(false)
        }
    }

    private func applyBorder(to field: NSTextField, state: FieldState) {
        field.layer?.cornerRadius = 5
        field.layer?.borderWidth = state == .neutral ? 0 : 1.5

        switch state {
        case .neutral:
            field.layer?.borderColor = NSColor.clear.cgColor
        case .error:
            field.layer?.borderColor = NSColor.systemRed.cgColor
        case .success:
            field.layer?.borderColor = NSColor.systemGreen.cgColor
        }
    }

    private func setValidation(message: String, color: NSColor) {
        validationLabel.stringValue = message
        validationLabel.textColor = color
    }
}

// MARK: - 복호화 모드 뷰 (비밀번호 단일 필드)

private final class DecryptPasswordView: NSView {

    var password: String { pw1Field.stringValue }

    private lazy var pw1Field: NSSecureTextField = makeField(placeholder: String(localized: "encryption.placeholder.password"))

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        addSubview(pw1Field)
        pw1Field.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pw1Field.topAnchor.constraint(equalTo: topAnchor),
            pw1Field.leadingAnchor.constraint(equalTo: leadingAnchor),
            pw1Field.trailingAnchor.constraint(equalTo: trailingAnchor),
            pw1Field.heightAnchor.constraint(equalToConstant: 26),
        ])
    }
}

// MARK: - 헬퍼

@MainActor
private func makeField(placeholder: String) -> NSSecureTextField {
    let field = NSSecureTextField()
    field.placeholderString = placeholder
    field.bezelStyle = .roundedBezel
    return field
}
