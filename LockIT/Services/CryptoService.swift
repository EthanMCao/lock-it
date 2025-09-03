import Foundation
import CryptoKit

enum CryptoServiceError: Error {
    case keyMissing
}

final class CryptoService {
    static let shared = CryptoService()
    private init() {}

    func generateKey() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    func encrypt(plaintext: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoServiceError.keyMissing }
        return combined
    }

    func decrypt(ciphertext: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }
}

