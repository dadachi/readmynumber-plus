import Foundation
import CommonCrypto

enum AuthenticationError: Error {
    case invalidCardNumber
}

protocol AuthenticationProvider {
    func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data)
}

class AuthenticationProviderImpl: AuthenticationProvider {
    func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data) {
        guard let cardNumberData = cardNumber.data(using: .ascii) else {
            throw AuthenticationError.invalidCardNumber
        }

        // SHA-1ハッシュ化（在留カード等仕様書 3.5.2.1 準拠）
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        cardNumberData.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(cardNumberData.count), &hash)
        }

        // 先頭16バイトを暗号化鍵およびMAC鍵として使用
        // 注: 仕様書では同一鍵を両方の目的に使用することが規定されている
        let key = Data(hash.prefix(16))
        return (kEnc: key, kMac: key)
    }
}