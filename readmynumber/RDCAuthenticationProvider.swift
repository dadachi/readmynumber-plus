import Foundation
import CommonCrypto


protocol RDCAuthenticationProvider {
    func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data)
    func generateAuthenticationData(rndICC: Data, kEnc: Data, kMac: Data) throws -> (eIFD: Data, mIFD: Data, rndIFD: Data, kIFD: Data)
    func verifyAndExtractKICC(eICC: Data, mICC: Data, rndICC: Data, rndIFD: Data, kEnc: Data, kMac: Data) throws -> Data
    func generateSessionKey(kIFD: Data, kICC: Data) throws -> Data
    func encryptCardNumber(cardNumber: String, sessionKey: Data) throws -> Data
}

class RDCAuthenticationProviderImpl: RDCAuthenticationProvider {
    private let tdesCryptography: RDCTDESCryptography
    private let cryptoProvider: RDCCryptoProvider

    init(tdesCryptography: RDCTDESCryptography = RDCTDESCryptography(),
         cryptoProvider: RDCCryptoProvider = RDCCryptoProviderImpl()) {
        self.tdesCryptography = tdesCryptography
        self.cryptoProvider = cryptoProvider
    }

    func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data) {
        guard let cardNumberData = cardNumber.data(using: .ascii) else {
            throw RDCReaderError.invalidCardNumber
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
        let mIFD = try cryptoProvider.calculateRetailMAC(data: eIFD, key: kMac)

        return (eIFD: eIFD, mIFD: mIFD, rndIFD: rndIFD, kIFD: kIFD)
    }

    func verifyAndExtractKICC(eICC: Data, mICC: Data, rndICC: Data, rndIFD: Data, kEnc: Data, kMac: Data) throws -> Data {
        // STEP 1: MAC検証 - データ完全性の確認
        // カードから受信したM.ICCと、E.ICCから計算したMACを比較
        let calculatedMAC = try cryptoProvider.calculateRetailMAC(data: eICC, key: kMac)
        guard calculatedMAC == mICC else {
            throw RDCReaderError.cryptographyError("MAC verification failed")
        }

        // STEP 2: 認証データの復号化
        // E.ICCを3DES復号して32バイトの平文認証データを取得
        let decrypted = try tdesCryptography.performTDES(data: eICC, key: kEnc, encrypt: false)

        // STEP 3: チャレンジ・レスポンス検証
        // 復号データの先頭8バイトが最初のRND.ICCと一致することを確認
        // これによりリプレイ攻撃を防止し、カードの正当性を確認
        guard decrypted.prefix(8) == rndICC else {
            throw RDCReaderError.cryptographyError("RND.ICC verification failed")
        }

        // STEP 4: 端末乱数による相互性の検証
        // 復号データの8バイト目から16バイト目までが端末のRND.IFDと一致することを確認
        guard decrypted.subdata(in: 8..<16) == rndIFD else {
            throw RDCReaderError.cryptographyError("RND.IFD verification failed")
        }

        // STEP 5: カード鍵K.ICCの抽出
        // 復号データの最後16バイトがK.ICC（カードセッション鍵素材）
        // この鍵はK.IFDとXORされて最終セッション鍵を生成
        return decrypted.suffix(16)
    }

    func generateSessionKey(kIFD: Data, kICC: Data) throws -> Data {
        // STEP 1: XOR演算による鍵の合成
        // K.IFD ⊕ K.ICC - 両方の鍵が寄与する複合鍵を作成
        let xorData = Data(zip(kIFD, kICC).map { $0 ^ $1 })

        // STEP 2: 仕様書規定の定数追加
        // 在留カード等仕様書で規定された固定値 "00000001" を連結
        let input = xorData + Data([0x00, 0x00, 0x00, 0x01])

        // STEP 3: SHA-1ハッシュ化による鍵導出
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        input.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(input.count), &hash)
        }

        // STEP 4: 先頭16バイトをセッション鍵として採用
        // SHA-1出力（20バイト）の先頭16バイトが最終的なセッション鍵
        return Data(hash.prefix(16))
    }

    func encryptCardNumber(cardNumber: String, sessionKey: Data) throws -> Data {
        guard let cardNumberData = cardNumber.data(using: .ascii),
              cardNumberData.count == 12 else {
            throw RDCReaderError.invalidCardNumber
        }

        // パディング追加
        let paddedData = cardNumberData + Data([0x80, 0x00, 0x00, 0x00])

        // TDES 2key CBC暗号化
        return try tdesCryptography.performTDES(data: paddedData, key: sessionKey, encrypt: true)
    }
}