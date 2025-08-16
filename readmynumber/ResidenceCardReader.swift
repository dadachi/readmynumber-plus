import CoreNFC
import CryptoKit
import CommonCrypto

// MARK: - 在留カードリーダー
class ResidenceCardReader: NSObject, ObservableObject {
    
    // MARK: - Constants
    private enum Command {
        static let selectFile: UInt8 = 0xA4
        static let verify: UInt8 = 0x20
        static let getChallenge: UInt8 = 0x84
        static let mutualAuthenticate: UInt8 = 0x82
        static let readBinary: UInt8 = 0xB0
    }
    
    private enum AID {
        static let df1 = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x02, 0x00, 0x00, 
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        static let df2 = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x03, 0x00, 0x00, 
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        static let df3 = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x04, 0x00, 0x00, 
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
    
    // MARK: - Properties
    private var session: NFCTagReaderSession?
    private var cardNumber: String = ""
    private var sessionKey: Data?
    private var readCompletion: ((Result<ResidenceCardData, Error>) -> Void)?
    @Published var isReadingInProgress: Bool = false
    
    // MARK: - Public Methods
    func startReading(cardNumber: String, completion: @escaping (Result<ResidenceCardData, Error>) -> Void) {
        self.cardNumber = cardNumber
        self.readCompletion = completion
        
        // Check if we're in test environment by looking for test bundle
        if Bundle.main.bundlePath.hasSuffix(".xctest") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            completion(.failure(CardReaderError.nfcNotAvailable))
            return
        }
        
        // Check if we're in test environment (no real NFC or simulator)
        guard NFCTagReaderSession.readingAvailable else {
            completion(.failure(CardReaderError.nfcNotAvailable))
            return
        }
        
        DispatchQueue.main.async {
            self.isReadingInProgress = true
        }
        
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        session?.alertMessage = "在留カードをiPhoneに近づけてください"
        session?.begin()
    }
    
    // MARK: - Private Methods
    
    // MFの選択
    private func selectMF(tag: NFCISO7816Tag) async throws {
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.selectFile,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data([0x3F, 0x00]),
            expectedResponseLength: -1
        )
        
        let (_, sw1, sw2) = try await tag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
    }
    
    // DFの選択
    private func selectDF(tag: NFCISO7816Tag, aid: Data) async throws {
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.selectFile,
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: aid,
            expectedResponseLength: -1
        )
        
        let (_, sw1, sw2) = try await tag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
    }
    
    // 認証処理
    private func performAuthentication(tag: NFCISO7816Tag) async throws {
        // 1. Get Challenge
        let challengeCommand = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.getChallenge,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 8
        )
        
        let (rndICC, sw1, sw2) = try await tag.sendCommand(apdu: challengeCommand)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        // 2. セッション鍵交換
        let (kEnc, kMac) = try generateKeys(from: cardNumber)
        let (eIFD, mIFD, kIFD) = try generateAuthenticationData(rndICC: rndICC, kEnc: kEnc, kMac: kMac)
        
        let mutualAuthCommand = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.mutualAuthenticate,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: eIFD + mIFD,
            expectedResponseLength: 40
        )
        
        let (response, sw1Auth, sw2Auth) = try await tag.sendCommand(apdu: mutualAuthCommand)
        try checkStatusWord(sw1: sw1Auth, sw2: sw2Auth)
        
        // 3. セッション鍵生成
        let eICC = response.prefix(32)
        let mICC = response.suffix(8)
        
        // 検証とセッション鍵生成
        let kICC = try verifyAndExtractKICC(eICC: eICC, mICC: mICC, rndICC: rndICC, kEnc: kEnc, kMac: kMac)
        sessionKey = try generateSessionKey(kIFD: kIFD, kICC: kICC)
        
        // 4. Verify（在留カード番号による認証）
        let encryptedCardNumber = try encryptCardNumber(cardNumber: cardNumber, sessionKey: sessionKey!)
        let verifyData = Data([0x86, 0x11, 0x01]) + encryptedCardNumber
        
        let verifyCommand = NFCISO7816APDU(
            instructionClass: 0x08, // SMコマンド
            instructionCode: Command.verify,
            p1Parameter: 0x00,
            p2Parameter: 0x86,
            data: verifyData,
            expectedResponseLength: -1
        )
        
        let (_, sw1Verify, sw2Verify) = try await tag.sendCommand(apdu: verifyCommand)
        try checkStatusWord(sw1: sw1Verify, sw2: sw2Verify)
    }
    
    // バイナリ読み出し（SMあり）
    private func readBinaryWithSM(tag: NFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let leData = Data([0x96, 0x02, 0x00, 0x00])
        
        let command = NFCISO7816APDU(
            instructionClass: 0x08, // SMコマンド
            instructionCode: Command.readBinary,
            p1Parameter: p1,
            p2Parameter: p2,
            data: leData,
            expectedResponseLength: 65536
        )
        
        let (encryptedData, sw1, sw2) = try await tag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        // 復号化
        return try decryptSMResponse(encryptedData: encryptedData)
    }
    
    // バイナリ読み出し（平文）
    private func readBinaryPlain(tag: NFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.readBinary,
            p1Parameter: p1,
            p2Parameter: p2,
            data: Data(),
            expectedResponseLength: 65536
        )
        
        let (data, sw1, sw2) = try await tag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        return data
    }
    
    // 暗号化・復号化処理
    private func encryptCardNumber(cardNumber: String, sessionKey: Data) throws -> Data {
        guard let cardNumberData = cardNumber.data(using: .ascii),
              cardNumberData.count == 12 else {
            throw CardReaderError.invalidCardNumber
        }
        
        // パディング追加
        let paddedData = cardNumberData + Data([0x80, 0x00, 0x00, 0x00])
        
        // TDES 2key CBC暗号化
        return try performTDES(data: paddedData, key: sessionKey, encrypt: true)
    }
    
    private func decryptSMResponse(encryptedData: Data) throws -> Data {
        // TLV構造から暗号化データを取り出す
        guard encryptedData.count > 3,
              encryptedData[0] == 0x86 else {
            throw CardReaderError.invalidResponse
        }
        
        let (length, offset) = try parseBERLength(data: encryptedData, offset: 1)
        guard encryptedData.count >= offset + length,
              length > 1,
              encryptedData[offset] == 0x01 else {
            throw CardReaderError.invalidResponse
        }
        
        let ciphertext = encryptedData.subdata(in: (offset + 1)..<(offset + length))
        
        // 復号化
        let decrypted = try performTDES(data: ciphertext, key: sessionKey!, encrypt: false)
        
        // パディング除去
        return try removePadding(data: decrypted)
    }
    
    // ステータスワードチェック
    internal func checkStatusWord(sw1: UInt8, sw2: UInt8) throws {
        guard sw1 == 0x90 && sw2 == 0x00 else {
            throw CardReaderError.cardError(sw1: sw1, sw2: sw2)
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate
extension ResidenceCardReader: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // セッション開始
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isReadingInProgress = false
        }
        readCompletion?(.failure(error))
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first,
              case .iso7816(let iso7816Tag) = tag else {
            session.invalidate(errorMessage: "対応していないカードです")
            return
        }
        
        Task {
            do {
                try await session.connect(to: tag)
                
                // カード読み取り処理
                let cardData = try await readCard(tag: iso7816Tag)
                
                await MainActor.run {
                    session.invalidate()
                    self.isReadingInProgress = false
                    readCompletion?(.success(cardData))
                }
            } catch {
                await MainActor.run {
                    session.invalidate(errorMessage: "読み取りに失敗しました")
                    self.isReadingInProgress = false
                    readCompletion?(.failure(error))
                }
            }
        }
    }
    
    private func readCard(tag: NFCISO7816Tag) async throws -> ResidenceCardData {
        // 1. MF選択
        try await selectMF(tag: tag)
        
        // 2. 共通データ要素とカード種別の読み取り
        let commonData = try await readBinaryPlain(tag: tag, p1: 0x8B)
        let cardType = try await readBinaryPlain(tag: tag, p1: 0x8A)
        
        // 3. 認証処理
        try await performAuthentication(tag: tag)
        
        // 4. DF1選択と券面情報読み取り
        try await selectDF(tag: tag, aid: AID.df1)
        let frontImage = try await readBinaryWithSM(tag: tag, p1: 0x85)
        let faceImage = try await readBinaryWithSM(tag: tag, p1: 0x86)
        
        // 5. DF2選択と裏面情報読み取り
        try await selectDF(tag: tag, aid: AID.df2)
        let address = try await readBinaryPlain(tag: tag, p1: 0x81)
        
        // 在留カードの場合は追加フィールドを読み取り
        var additionalData: ResidenceCardData.AdditionalData?
        if isResidenceCard(cardType: cardType) {
            let comprehensivePermission = try await readBinaryPlain(tag: tag, p1: 0x82)
            let individualPermission = try await readBinaryPlain(tag: tag, p1: 0x83)
            let extensionApplication = try await readBinaryPlain(tag: tag, p1: 0x84)
            
            additionalData = ResidenceCardData.AdditionalData(
                comprehensivePermission: comprehensivePermission,
                individualPermission: individualPermission,
                extensionApplication: extensionApplication
            )
        }
        
        // 6. DF3選択と電子署名読み取り
        try await selectDF(tag: tag, aid: AID.df3)
        let signature = try await readBinaryPlain(tag: tag, p1: 0x82)
        
        // 7. 署名検証 (3.4.3.1 署名検証方法)
        let verifier = ResidenceCardSignatureVerifier()
        let verificationResult = verifier.verifySignature(
            signatureData: signature,
            frontImageData: frontImage,
            faceImageData: faceImage
        )
        
        var cardData = ResidenceCardData(
            commonData: commonData,
            cardType: cardType,
            frontImage: frontImage,
            faceImage: faceImage,
            address: address,
            additionalData: additionalData,
            signature: signature,
            signatureVerificationResult: verificationResult
        )
        
        return cardData
    }
}

// MARK: - Data Models
struct ResidenceCardData: Equatable {
    let commonData: Data
    let cardType: Data
    let frontImage: Data
    let faceImage: Data
    let address: Data
    let additionalData: AdditionalData?
    let signature: Data
    
    // Signature verification status
    var signatureVerificationResult: ResidenceCardSignatureVerifier.VerificationResult?
    
    struct AdditionalData: Equatable {
        let comprehensivePermission: Data
        let individualPermission: Data
        let extensionApplication: Data
    }
    
    // Custom Equatable implementation to handle optional verification result
    static func == (lhs: ResidenceCardData, rhs: ResidenceCardData) -> Bool {
        return lhs.commonData == rhs.commonData &&
               lhs.cardType == rhs.cardType &&
               lhs.frontImage == rhs.frontImage &&
               lhs.faceImage == rhs.faceImage &&
               lhs.address == rhs.address &&
               lhs.additionalData == rhs.additionalData &&
               lhs.signature == rhs.signature
        // Note: signatureVerificationResult is not included in equality check
    }
}

// MARK: - Error Types
enum CardReaderError: LocalizedError, Equatable {
    case nfcNotAvailable
    case invalidCardNumber
    case invalidResponse
    case cardError(sw1: UInt8, sw2: UInt8)
    case cryptographyError(String)
    
    var errorDescription: String? {
        switch self {
        case .nfcNotAvailable:
            return "NFCが利用できません"
        case .invalidCardNumber:
            return "無効な在留カード番号です"
        case .invalidResponse:
            return "カードからの応答が不正です"
        case .cardError(let sw1, let sw2):
            return String(format: "カードエラー: SW1=%02X, SW2=%02X", sw1, sw2)
        case .cryptographyError(let message):
            return "暗号処理エラー: \(message)"
        }
    }
}

// MARK: - Cryptography Extensions
extension ResidenceCardReader {
    
    internal func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data) {
        guard let cardNumberData = cardNumber.data(using: .ascii) else {
            throw CardReaderError.invalidCardNumber
        }
        
        // SHA-1ハッシュ化
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        cardNumberData.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(cardNumberData.count), &hash)
        }
        
        // 先頭16バイトを取得
        let key = Data(hash.prefix(16))
        return (key, key)
    }
    
    private func generateAuthenticationData(rndICC: Data, kEnc: Data, kMac: Data) throws -> (eIFD: Data, mIFD: Data, kIFD: Data) {
        // 乱数生成
        let rndIFD = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        let kIFD = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        // 連結
        let plaintext = rndIFD + rndICC + kIFD
        
        // 暗号化
        let eIFD = try performTDES(data: plaintext, key: kEnc, encrypt: true)
        
        // MAC計算
        let mIFD = try calculateRetailMAC(data: eIFD, key: kMac)
        
        return (eIFD, mIFD, kIFD)
    }
    
    private func performTDES(data: Data, key: Data, encrypt: Bool) throws -> Data {
        guard key.count == 16 else {
            throw CardReaderError.cryptographyError("Invalid key length")
        }
        
        // TDES 2-key implementation
        var result = Data(count: data.count + kCCBlockSize3DES)
        var numBytesProcessed: size_t = 0
        
        let operation = encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt)
        
        let resultCount = result.count
        let keyCount = key.count
        let dataCount = data.count
        
        let status = data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                result.withUnsafeMutableBytes { resultBytes in
                    CCCrypt(operation,
                           CCAlgorithm(kCCAlgorithm3DES),
                           CCOptions(kCCOptionPKCS7Padding),
                           keyBytes.bindMemory(to: UInt8.self).baseAddress, keyCount,
                           nil, // IV (zeros for CBC)
                           dataBytes.bindMemory(to: UInt8.self).baseAddress, dataCount,
                           resultBytes.bindMemory(to: UInt8.self).baseAddress, resultCount,
                           &numBytesProcessed)
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CardReaderError.cryptographyError("TDES operation failed")
        }
        
        result.count = numBytesProcessed
        return result
    }
    
    private func calculateRetailMAC(data: Data, key: Data) throws -> Data {
        // Retail MAC (ISO/IEC 9797-1 Algorithm 3) の簡易実装
        let mac = try performTDES(data: data, key: key, encrypt: true)
        return mac.suffix(8)
    }
    
    private func generateSessionKey(kIFD: Data, kICC: Data) throws -> Data {
        // K.IFD ⊕ K.ICC
        let xorData = Data(zip(kIFD, kICC).map { $0 ^ $1 })
        
        // 連結
        let input = xorData + Data([0x00, 0x00, 0x00, 0x01])
        
        // SHA-1ハッシュ化
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        input.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(input.count), &hash)
        }
        
        // 先頭16バイトを取得
        return Data(hash.prefix(16))
    }
    
    private func verifyAndExtractKICC(eICC: Data, mICC: Data, rndICC: Data, kEnc: Data, kMac: Data) throws -> Data {
        // MAC検証
        let calculatedMAC = try calculateRetailMAC(data: eICC, key: kMac)
        guard calculatedMAC == mICC else {
            throw CardReaderError.cryptographyError("MAC verification failed")
        }
        
        // 復号化
        let decrypted = try performTDES(data: eICC, key: kEnc, encrypt: false)
        
        // RND.ICCの検証と K.ICCの抽出
        guard decrypted.prefix(8) == rndICC else {
            throw CardReaderError.cryptographyError("RND.ICC verification failed")
        }
        
        return decrypted.suffix(16)
    }
    
    internal func parseBERLength(data: Data, offset: Int) throws -> (length: Int, nextOffset: Int) {
        guard offset < data.count else {
            throw CardReaderError.invalidResponse
        }
        
        let firstByte = data[offset]
        
        if firstByte <= 0x7F {
            return (Int(firstByte), offset + 1)
        } else if firstByte == 0x81 {
            guard offset + 1 < data.count else {
                throw CardReaderError.invalidResponse
            }
            return (Int(data[offset + 1]), offset + 2)
        } else if firstByte == 0x82 {
            guard offset + 2 < data.count else {
                throw CardReaderError.invalidResponse
            }
            let length = (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
            return (length, offset + 3)
        } else {
            throw CardReaderError.invalidResponse
        }
    }
    
    internal func removePadding(data: Data) throws -> Data {
        // ISO/IEC 7816-4 パディング除去
        guard let lastPaddingIndex = data.lastIndex(of: 0x80) else {
            throw CardReaderError.invalidResponse
        }
        
        // 0x80以降がすべて0x00であることを確認
        for i in (lastPaddingIndex + 1)..<data.count {
            guard data[i] == 0x00 else {
                throw CardReaderError.invalidResponse
            }
        }
        
        return data.prefix(lastPaddingIndex)
    }
    
    internal func isResidenceCard(cardType: Data) -> Bool {
        // カード種別の判定（C1タグの値が"1"なら在留カード）
        if let typeValue = parseCardType(from: cardType) {
            return typeValue == "1"
        }
        return false
    }
    
    internal func parseCardType(from data: Data) -> String? {
        // TLV構造からカード種別を取得
        guard data.count >= 3,
              data[0] == 0xC1,
              data[1] == 0x01 else {
            return nil
        }
        return String(data: data.subdata(in: 2..<3), encoding: .utf8)
    }
}

// MARK: - Data Manager for ResidenceCard
class ResidenceCardDataManager: ObservableObject {
    static let shared = ResidenceCardDataManager()
    
    @Published var cardData: ResidenceCardData?
    @Published var shouldNavigateToDetail: Bool = false
    
    private init() {}
    
    func setCardData(_ data: ResidenceCardData) {
        cardData = data
        shouldNavigateToDetail = true
    }
    
    func resetNavigation() {
        shouldNavigateToDetail = false
    }
    
    func clearData() {
        cardData = nil
        shouldNavigateToDetail = false
    }
}

// MARK: - TLV Parser Helper
extension ResidenceCardData {
    func parseTLV(data: Data, tag: UInt8) -> Data? {
        var offset = 0
        
        while offset < data.count {
            guard offset + 2 <= data.count else { break }
            
            let currentTag = data[offset]
            var length = 0
            var lengthFieldSize = 1
            
            // Parse length according to BER-TLV encoding rules
            let lengthByte = data[offset + 1]
            
            if lengthByte <= 0x7F {
                // Short form: length is directly encoded in one byte (0x00 to 0x7F)
                length = Int(lengthByte)
                lengthFieldSize = 1
            } else if lengthByte == 0x81 {
                // Extended form: next byte contains length (0x00 to 0xFF)
                guard offset + 3 <= data.count else { break }
                length = Int(data[offset + 2])
                lengthFieldSize = 2
            } else if lengthByte == 0x82 {
                // Extended form: next 2 bytes contain length (big-endian)
                guard offset + 4 <= data.count else { break }
                length = Int(data[offset + 2]) * 256 + Int(data[offset + 3])
                lengthFieldSize = 3
            } else {
                // Unsupported length encoding
                break
            }
            
            let valueStart = offset + 1 + lengthFieldSize
            guard valueStart + length <= data.count else { break }
            
            if currentTag == tag {
                return data.subdata(in: valueStart..<(valueStart + length))
            }
            
            offset = valueStart + length
        }
        
        return nil
    }
}