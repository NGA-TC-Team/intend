import CryptoKit
import CommonCrypto
import Foundation

// MARK: - 파일 포맷
// [magic 4B "MDXK"] [salt 16B] [AES-GCM combined: nonce 12B + ciphertext + tag 16B]

private let magic: [UInt8] = [0x4D, 0x44, 0x58, 0x4B]  // "MDXK"
private let saltLength  = 16
private let kdfIterations: UInt32 = 200_000
private let keyLength   = 32  // AES-256

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case invalidMagic
    case fileTooShort
    case keyDerivationFailed
    case decryptionFailed    // GCM 태그 불일치 → 잘못된 비밀번호
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidMagic:      return "암호화된 마크다운 파일이 아닙니다."
        case .fileTooShort:      return "파일이 손상되었습니다."
        case .keyDerivationFailed: return "키 유도에 실패했습니다."
        case .decryptionFailed:  return "비밀번호가 올바르지 않거나 파일이 손상되었습니다."
        case .encodingFailed:    return "텍스트 인코딩에 실패했습니다."
        }
    }
}

// MARK: - Encryptor (순수 함수)

enum MarkdownEncryptor {

    // MARK: - Encrypt

    /// 평문 Data → .mdxk 바이너리
    static func encrypt(data plaintext: Data, password: String) throws -> Data {
        let salt = generateSalt()
        let key  = try deriveKey(password: password, salt: salt)

        guard let sealed = try? AES.GCM.seal(plaintext, using: key),
              let combined = sealed.combined
        else { throw EncryptionError.keyDerivationFailed }

        var result = Data(magic)
        result.append(salt)
        result.append(combined)
        return result
    }

    // MARK: - Decrypt

    /// .mdxk 바이너리 → 평문 Data
    static func decrypt(data cipherData: Data, password: String) throws -> Data {
        // 최소 크기: magic(4) + salt(16) + nonce(12) + tag(16) = 48
        guard cipherData.count >= 48 else { throw EncryptionError.fileTooShort }

        // Magic 검증
        guard Array(cipherData.prefix(4)) == magic else { throw EncryptionError.invalidMagic }

        let salt     = cipherData[4..<(4 + saltLength)]
        let combined = cipherData[(4 + saltLength)...]
        let key      = try deriveKey(password: password, salt: Data(salt))

        do {
            let box       = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(box, using: key)
            return plaintext
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    // MARK: - isEncrypted

    /// Data가 .mdxk 매직 바이트로 시작하는지 확인.
    static func isEncrypted(_ data: Data) -> Bool {
        data.count >= 4 && Array(data.prefix(4)) == magic
    }

    // MARK: - Private helpers

    private static func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        return Data(bytes)
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedKey   = Data(repeating: 0, count: keyLength)

        let status = derivedKey.withUnsafeMutableBytes { derivedPtr in
            passwordData.withUnsafeBytes { pwdPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        kdfIterations,
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw EncryptionError.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }
}
