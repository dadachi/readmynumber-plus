import Foundation
import CommonCrypto

enum AuthenticationError: Error {
    case invalidCardNumber
}

protocol AuthenticationProvider {
    func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data)
    func generateAuthenticationData(rndICC: Data, kEnc: Data, kMac: Data) throws -> (eIFD: Data, mIFD: Data, rndIFD: Data, kIFD: Data)
}

class AuthenticationProviderImpl: AuthenticationProvider {
    private let tdesCryptography: TDESCryptography
    private let cryptoProvider: CryptoProvider

    init(tdesCryptography: TDESCryptography = TDESCryptography(),
         cryptoProvider: CryptoProvider = CryptoProviderImpl()) {
        self.tdesCryptography = tdesCryptography
        self.cryptoProvider = cryptoProvider
    }

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

    func generateAuthenticationData(rndICC: Data, kEnc: Data, kMac: Data) throws -> (eIFD: Data, mIFD: Data, rndIFD: Data, kIFD: Data) {
        // STEP 1: 端末側ランダム数生成（8バイト）
        // 暗号学的に安全な乱数を生成してリプレイ攻撃を防止
        let rndIFD = Data((0..<8).map { _ in UInt8.random(in: 0...255) })

        // STEP 2: 端末セッション鍵素材生成（16バイト）
        // この鍵はカードの K.ICC と XOR されて最終セッション鍵になる
        let kIFD = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

        // STEP 3: 認証データ連結
        // 在留カード等仕様書で規定された順序: RND.IFD || RND.ICC || K.IFD
        let plaintext = rndIFD + rndICC + kIFD

        // STEP 4: Triple-DES暗号化
        // CBCモードでPKCS#7パディングを使用（32バイト → 32バイト）
        let eIFD = try tdesCryptography.performTDES(data: plaintext, key: kEnc, encrypt: true)

        // STEP 5: Retail MAC計算（ISO/IEC 9797-1 Algorithm 3）
        // 暗号化データの完全性を保護するため8バイトMACを計算
        let mIFD: Data
        do {
            mIFD = try cryptoProvider.calculateRetailMAC(data: eIFD, key: kMac)
        } catch let error as CryptoProviderImpl.CryptoError {
            throw AuthenticationError.invalidCardNumber // Convert to AuthenticationError
        }

        return (eIFD: eIFD, mIFD: mIFD, rndIFD: rndIFD, kIFD: kIFD)
    }
}