import AppKit

/// NSDocument 서브클래스. 소스 문자열의 단일 소유자.
/// 모든 편집은 textStorage → document.markDirty() 경로로 흐름.
final class MarkdownDocument: NSDocument {

    // MARK: - State

    /// 문서의 raw 마크다운 소스. NSTextStorage가 이 값을 백킹.
    private(set) var source: String = ""

    /// 마지막으로 타이핑이 발생한 시각 (미저장 상태 포함).
    private(set) var lastTypedAt: Date?

    /// 마지막으로 디스크에 저장된 시각.
    var lastSavedAt: Date? {
        guard let url = fileURL else { return nil }
        let key = Preferences.Keys.lastEditedAtPrefix + "\(url.absoluteString.hashValue)"
        let interval = UserDefaults.standard.double(forKey: key)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    // MARK: - Encryption state

    /// read(from:) 에서 magic bytes 감지 시 true로 설정.
    /// makeWindowControllers() 에서 이 플래그를 확인해 비밀번호 시트를 띄움.
    private(set) var needsDecryption: Bool = false

    /// 복호화 전 원본 암호문. decrypt(with:) 호출 전까지 보관.
    private var encryptedData: Data?

    /// 이 문서가 암호화된 .mdxk 로 저장되어 있는지 여부.
    /// 저장 시 암호화를 유지할지 결정하는 데 사용.
    var isEncryptedFile: Bool = false

    /// 현재 세션의 복호화 비밀번호 (재저장 시 재사용 가능).
    var encryptionPassword: String?

    // MARK: - NSDocument overrides

    override class var autosavesInPlace: Bool { true }

    /// 파일 포맷 목록.
    /// Save As / Save To 패널에서만 두 포맷을 모두 노출.
    /// 일반 저장·자동저장은 현재 파일 타입만 반환해 암호화 시트가 불필요하게 뜨는 것을 막음.
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        switch saveOperation {
        case .saveAsOperation, .saveToOperation:
            return ["net.daringfireball.markdown", "com.intend.encrypted-markdown"]
        default:
            return isEncryptedFile
                ? ["com.intend.encrypted-markdown"]
                : ["net.daringfireball.markdown"]
        }
    }

    /// 파일 타입별 기본 확장자 명시 — macOS가 plain-text UTI에서 .txt를 쓰는 것을 방지.
    override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String {
        switch typeName {
        case "net.daringfireball.markdown", "public.plain-text": return "md"
        case "com.intend.encrypted-markdown":                    return "mdxk"
        default: return super.fileNameExtension(forType: typeName, saveOperation: saveOperation) ?? "md"
        }
    }

    override func makeWindowControllers() {
        // 기존 가시 EditorWindowController가 있으면 탭으로 추가.
        // 없으면 새 창을 생성해 첫 번째 탭으로 추가.
        if let existingWC = NSApp.windows
                .compactMap({ $0.windowController as? EditorWindowController })
                .first(where: { !($0.window?.isMiniaturized ?? true) }) {
            addWindowController(existingWC)
            if needsDecryption {
                existingWC.requestDecryption(for: self)
            } else {
                existingWC.addTab(document: self)
            }
            existingWC.window?.makeKeyAndOrderFront(nil)
        } else {
            let wc = EditorWindowController()
            addWindowController(wc)
            if needsDecryption {
                wc.showWindowAndRequestDecryption(document: self)
            } else {
                wc.addTab(document: self)
                wc.showWindow(nil)
            }
        }
    }

    // MARK: - Read

    override func read(from data: Data, ofType typeName: String) throws {
        if MarkdownEncryptor.isEncrypted(data) {
            // 암호화된 파일 — 비밀번호 없이는 아직 열 수 없음
            encryptedData  = data
            needsDecryption = true
            isEncryptedFile = true
            source = ""   // 복호화 전 빈 상태
        } else {
            guard let text = String(data: data, encoding: .utf8)
                          ?? String(data: data, encoding: .utf16) else {
                throw CocoaError(.fileReadUnknownStringEncoding)
            }
            source = normalizeLineEndings(text)
        }
    }

    // MARK: - Decryption (비밀번호 시트 결과 처리)

    /// 사용자가 입력한 비밀번호로 복호화 시도.
    /// - Returns: 성공 시 true, 비밀번호 불일치 시 false.
    func decrypt(with password: String) throws {
        guard let data = encryptedData else { return }
        let plainData = try MarkdownEncryptor.decrypt(data: data, password: password)
        guard let text = String(data: plainData, encoding: .utf8)
                      ?? String(data: plainData, encoding: .utf16) else {
            throw EncryptionError.encodingFailed
        }
        source             = normalizeLineEndings(text)
        encryptionPassword = password
        needsDecryption    = false
        encryptedData      = nil
    }

    // MARK: - Write

    /// NSDocument save 파이프라인 진입점.
    /// 암호화 타입으로 저장하되 비밀번호가 없으면 먼저 비밀번호 시트를 띄운 뒤 저장.
    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let isEncryptedType = (typeName == "com.intend.encrypted-markdown")

        if isEncryptedType, encryptionPassword == nil {
            // 비밀번호 없이 암호화 저장 시도 → 먼저 비밀번호 시트 표시
            guard let window = windowControllers.first?.window else {
                completionHandler(CocoaError(.fileWriteUnknown))
                return
            }
            PasswordSheetController.promptForEncrypt(relativeTo: window) { [weak self] password in
                guard let self else { return }
                guard let password else {
                    completionHandler(CocoaError(.userCancelled))
                    return
                }
                self.encryptionPassword = password
                self.isEncryptedFile    = true
                // super 클로저 직접 호출 불가 → 래퍼 경유
                self.performSuperSave(to: url, ofType: typeName, for: saveOperation,
                                      completionHandler: completionHandler)
            }
        } else {
            if isEncryptedType { isEncryptedFile = true }
            performSuperSave(to: url, ofType: typeName, for: saveOperation,
                             completionHandler: completionHandler)
        }
    }

    /// `super.save(...)` 를 클로저 밖에서 호출하기 위한 래퍼.
    private func performSuperSave(
        to url: URL,
        ofType typeName: String,
        for saveOperation: SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        super.save(to: url, ofType: typeName, for: saveOperation,
                   completionHandler: completionHandler)
    }

    override func data(ofType typeName: String) throws -> Data {
        let outputData: Data

        if isEncryptedFile, let password = encryptionPassword {
            // 암호화 저장
            guard let plainData = source.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            outputData = try MarkdownEncryptor.encrypt(data: plainData, password: password)
        } else {
            guard let plain = source.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            outputData = plain
        }

        // 저장 시각 기록
        if let url = fileURL {
            let key = Preferences.Keys.lastEditedAtPrefix + "\(url.absoluteString.hashValue)"
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        }
        return outputData
    }

    // MARK: - Encrypted Save As (.mdxk)

    /// 현재 문서를 암호화하여 .mdxk 파일로 저장.
    /// EditorWindowController의 "잠금…" 메뉴 항목에서 호출.
    func saveAsEncrypted(password: String, to url: URL) throws {
        guard let plainData = source.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let encrypted = try MarkdownEncryptor.encrypt(data: plainData, password: password)
        try encrypted.write(to: url, options: .atomic)
    }

    // MARK: - Edit interface (EditorViewController → Document)

    /// TextStorage 변경 시 호출. source 갱신 + dirty 마킹 + lastTypedAt 갱신.
    func update(source newSource: String) {
        source      = newSource
        lastTypedAt = Date()
        updateChangeCount(.changeDone)
    }
}

// MARK: - Pure helpers

private func normalizeLineEndings(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}
