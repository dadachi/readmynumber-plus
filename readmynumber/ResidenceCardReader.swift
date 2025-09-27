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

    // MARK: - APDU Response Limits
    // iOS NFC APDU response limitation remains active as of 2025
    // Reference: https://developer.apple.com/forums/thread/120496
    // Using global maxAPDUResponseLength constant (1693 bytes)

    // MARK: - Properties
    internal var cardNumber: String = "" // Made internal for testing
    internal var sessionKey: Data? // Made internal for testing
    internal var readCompletion: ((Result<ResidenceCardData, Error>) -> Void)? // Made internal for testing
    @Published var isReadingInProgress: Bool = false

    // Store the last exported image URLs for sharing
    private var lastExportedImageURLs: [URL]?

    // Dependency injection for testability
    private var commandExecutor: RDCNFCCommandExecutor?
    private var sessionManager: NFCSessionManager
    private var threadDispatcher: ThreadDispatcher
    private var signatureVerifier: SignatureVerifier
    private var authenticationProvider: RDCAuthenticationProvider
    internal var tdesCryptography: TDESCryptography
    private var cryptoProvider: RDCCryptoProvider

    // MARK: - Initialization

    /// Initialize with default implementations
    override init() {
        self.sessionManager = NFCSessionManagerImpl()
        self.threadDispatcher = SystemThreadDispatcher()
        self.signatureVerifier = ResidenceCardSignatureVerifier()
        self.authenticationProvider = RDCAuthenticationProviderImpl()
        self.tdesCryptography = TDESCryptography()
        self.cryptoProvider = RDCCryptoProviderImpl()
        super.init()
    }

    /// Initialize with custom dependencies for testing
    init(
        sessionManager: NFCSessionManager,
        threadDispatcher: ThreadDispatcher,
        signatureVerifier: SignatureVerifier,
        authenticationProvider: RDCAuthenticationProvider = RDCAuthenticationProviderImpl(),
        tdesCryptography: TDESCryptography = TDESCryptography(),
        cryptoProvider: RDCCryptoProvider = RDCCryptoProviderImpl()
    ) {
        self.sessionManager = sessionManager
        self.threadDispatcher = threadDispatcher
        self.signatureVerifier = signatureVerifier
        self.authenticationProvider = authenticationProvider
        self.tdesCryptography = tdesCryptography
        self.cryptoProvider = cryptoProvider
        super.init()
    }

    // MARK: - Public Methods

    /// Set a custom command executor for testing
    func setCommandExecutor(_ executor: RDCNFCCommandExecutor) {
        self.commandExecutor = executor
    }

    /// Set dependencies for testing
    func setDependencies(
        sessionManager: NFCSessionManager? = nil,
        threadDispatcher: ThreadDispatcher? = nil,
        signatureVerifier: SignatureVerifier? = nil,
        tdesCryptography: TDESCryptography? = nil
    ) {
        if let sessionManager = sessionManager {
            self.sessionManager = sessionManager
        }
        if let threadDispatcher = threadDispatcher {
            self.threadDispatcher = threadDispatcher
        }
        if let signatureVerifier = signatureVerifier {
            self.signatureVerifier = signatureVerifier
        }
        if let tdesCryptography = tdesCryptography {
            self.tdesCryptography = tdesCryptography
        }
    }

    func startReading(cardNumber: String, completion: @escaping (Result<ResidenceCardData, Error>) -> Void) {
        self.readCompletion = completion

        // Enhanced card number validation
        do {
            let validatedCardNumber = try validateCardNumber(cardNumber)
            self.cardNumber = validatedCardNumber
        } catch {
            completion(.failure(error))
            return
        }

        // Check if we're in test environment by looking for test bundle
        if Bundle.main.bundlePath.hasSuffix(".xctest") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            completion(.failure(ResidenceCardReaderError.nfcNotAvailable))
            return
        }

        // Check if we're in test environment (no real NFC or simulator)
        guard sessionManager.isReadingAvailable else {
            completion(.failure(ResidenceCardReaderError.nfcNotAvailable))
            return
        }

        threadDispatcher.dispatchToMain {
            self.isReadingInProgress = true
        }

        sessionManager.startSession(
            pollingOption: .iso14443,
            delegate: self,
            alertMessage: "在留カードをiPhoneに近づけてください"
        )
    }

    // MARK: - Private Methods

    // MFの選択
    internal func selectMF(executor: RDCNFCCommandExecutor) async throws {
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.selectFile,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data([0x3F, 0x00]),
            expectedResponseLength: -1
        )

        let (_, sw1, sw2) = try await executor.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
    }

    // DFの選択
    internal func selectDF(executor: RDCNFCCommandExecutor, aid: Data) async throws {
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.selectFile,
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: aid,
            expectedResponseLength: -1
        )

        let (_, sw1, sw2) = try await executor.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
    }

    /// 認証処理 - 在留カード等仕様書 3.5.2 認証シーケンスの実装
    ///
    /// この処理は在留カード等仕様書の「3.5.2 認証シーケンス」に従って実装されています。
    /// セキュアメッセージング（SM）を使用した暗号化通信を確立するための手順:
    ///
    /// 1. GET CHALLENGE: ICCから8バイトの乱数（RND.ICC）を取得
    /// 2. MUTUAL AUTHENTICATE: 相互認証による鍵交換
    /// 3. SESSION KEY生成: 通信用セッション鍵を確立
    /// 4. VERIFY: 在留カード番号による認証実行
    ///
    /// セキュリティ機能:
    /// - Triple-DES（3DES）暗号化による機密性確保
    /// - Retail MAC（ISO/IEC 9797-1）による改ざん検知
    /// - Challenge-Response認証による再送攻撃防止
    /// - セッション鍵による通信暗号化
    ///
    /// 参考仕様:
    /// - 在留カード等仕様書 3.5.2 認証シーケンス
    /// - ISO/IEC 7816-4 セキュアメッセージング
    /// - FIPS 46-3 Triple-DES暗号化標準
    internal func performAuthentication(executor: RDCNFCCommandExecutor) async throws -> Data {
        // STEP 1: GET CHALLENGE - ICCチャレンジ取得
        // カードから8バイトのランダムな乱数（RND.ICC）を取得します。
        // この乱数は認証プロセスでリプレイ攻撃を防ぐために使用されます。
        // コマンド: GET CHALLENGE (00 84 00 00 08)
        let challengeCommand = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.getChallenge,  // 0x84
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 8              // RND.ICC: 8バイトの乱数
        )

        let (rndICC, sw1, sw2) = try await executor.sendCommand(apdu: challengeCommand)
        try checkStatusWord(sw1: sw1, sw2: sw2)

        // STEP 2: 認証鍵生成とセッション鍵交換データ準備
        // 在留カード番号からSHA-1ハッシュ化により暗号化鍵（K.Enc）と
        // MAC鍵（K.Mac）を生成します（在留カード等仕様書 3.5.2.1）
        let (kEnc, kMac) = try authenticationProvider.generateKeys(from: cardNumber)

        // IFD（端末）側の認証データを生成:
        // - RND.IFD（端末乱数8バイト）+ RND.ICC（カード乱数8バイト）+ K.IFD（端末鍵16バイト）
        // - この32バイトデータを3DES暗号化してE.IFDを作成
        // - E.IFDのRetail MACを計算してM.IFDを作成
        let (eIFD, mIFD, rndIFD, kIFD) = try authenticationProvider.generateAuthenticationData(rndICC: rndICC, kEnc: kEnc, kMac: kMac)

        // STEP 3: MUTUAL AUTHENTICATE - 相互認証実行
        // E.IFD（32バイト暗号化データ）+ M.IFD（8バイトMAC）を送信
        // カードからE.ICC（32バイト）+ M.ICC（8バイト）を受信
        // コマンド: MUTUAL AUTHENTICATE (00 82 00 00 28 [E.IFD + M.IFD] 28)
        let mutualAuthCommand = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Command.mutualAuthenticate,  // 0x82
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: eIFD + mIFD,                           // 40バイト（32+8）
            expectedResponseLength: 40                    // E.ICC + M.ICC
        )

        let (response, sw1Auth, sw2Auth) = try await executor.sendCommand(apdu: mutualAuthCommand)
        try checkStatusWord(sw1: sw1Auth, sw2: sw2Auth)

        // STEP 4: カード認証データの検証とセッション鍵生成
        // カードからの応答を分解: E.ICC（32バイト）+ M.ICC（8バイト）
        let eICC = response.prefix(32)   // カードの暗号化認証データ
        let mICC = response.suffix(8)    // カードのMAC

        // ICC（カード）側認証の検証:
        // 1. M.ICCを検証してE.ICCの完全性を確認
        // 2. E.ICCを復号してRND.ICCの一致を確認（リプレイ攻撃防止）
        // 3. K.ICC（カード鍵16バイト）を抽出
        let kICC = try verifyAndExtractKICC(eICC: eICC, mICC: mICC, rndICC: rndICC, rndIFD: rndIFD, kEnc: kEnc, kMac: kMac)

        // セッション鍵生成: K.Session = SHA-1((K.IFD ⊕ K.ICC) || 00000001)[0..15]
        // この鍵は以降のセキュアメッセージング通信で使用されます
        let generatedSessionKey = try generateSessionKey(kIFD: kIFD, kICC: kICC)
        sessionKey = generatedSessionKey

        // STEP 5: VERIFY - 在留カード番号による認証実行
        // セッション鍵を使って在留カード番号を暗号化し、カードに送信して認証を行います。
        // これにより、正しい在留カード番号を知っている端末のみがカードにアクセス可能になります。

        // 在留カード番号（12バイト）をセッション鍵で3DES暗号化
        // パディング: カード番号 + 0x80 + 0x00（16バイトブロック境界まで）
        let encryptedCardNumber = try encryptCardNumber(cardNumber: cardNumber, sessionKey: sessionKey!)

        // セキュアメッセージング用TLVデータ構造:
        // 0x86: 暗号化されたデータオブジェクト
        // 0x11: 長さ（17バイト = 暗号化パディング指示子1バイト + 暗号化データ16バイト）
        // 0x01: パディング指示子（暗号化されたデータの先頭バイト）
        let verifyData = Data([0x86, 0x11, 0x01]) + encryptedCardNumber

        // VERIFY コマンド実行（セキュアメッセージング）
        // コマンド: VERIFY (08 20 00 86 14 [セキュアメッセージング TLVデータ])
        let verifyCommand = NFCISO7816APDU(
            instructionClass: 0x08,                      // SMコマンドクラス
            instructionCode: Command.verify,             // 0x20 - VERIFY命令
            p1Parameter: 0x00,
            p2Parameter: 0x86,                          // 在留カード番号認証
            data: verifyData,                           // セキュアメッセージング データ
            expectedResponseLength: -1
        )

        let (_, sw1Verify, sw2Verify) = try await executor.sendCommand(apdu: verifyCommand)
        try checkStatusWord(sw1: sw1Verify, sw2: sw2Verify)

        // 認証完了 - セッション鍵によるセキュアメッセージング通信が確立されました
        return generatedSessionKey
    }

    // バイナリ読み出し（SMあり）
    internal func readBinaryWithSM(executor: RDCNFCCommandExecutor, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let smReader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
        return try await smReader.readBinaryWithSM(p1: p1, p2: p2)
    }

    // バイナリ読み出し（平文）
    internal func readBinaryPlain(executor: RDCNFCCommandExecutor, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let plainReader = PlainBinaryReader(commandExecutor: executor)
        return try await plainReader.readBinaryPlain(p1: p1, p2: p2)
    }

    // 暗号化・復号化処理
    internal func encryptCardNumber(cardNumber: String, sessionKey: Data) throws -> Data {
        guard let cardNumberData = cardNumber.data(using: .ascii),
              cardNumberData.count == 12 else {
            throw ResidenceCardReaderError.invalidCardNumber
        }

        // パディング追加
        let paddedData = cardNumberData + Data([0x80, 0x00, 0x00, 0x00])

        // TDES 2key CBC暗号化
        return try tdesCryptography.performTDES(data: paddedData, key: sessionKey, encrypt: true)
    }

    /// Decrypt Secure Messaging response
    ///
    /// セキュアメッセージング応答の復号化処理を SecureMessagingReader に委任します。
    /// テスト用に公開されているメソッドです。
    ///
    /// - Parameter encryptedData: TLV形式の暗号化データ
    /// - Returns: 復号化されたデータ（パディング除去済み）
    /// - Throws: ResidenceCardReaderError セッションキーがない、データ形式が不正、復号化失敗時
    internal func decryptSMResponse(encryptedData: Data) throws -> Data {
        let smReader = SecureMessagingReader(
            commandExecutor: MockRDCNFCCommandExecutor(), // Tests don't need real executor
            sessionKey: sessionKey,
            tdesCryptography: tdesCryptography
        )
        return try smReader.decryptSMResponse(encryptedData: encryptedData)
    }

    // MARK: - Testing Methods (delegated to SecureMessagingReader)

    /// Parse BER/DER length encoding - delegated to SecureMessagingReader for testing
    internal func parseBERLength(data: Data, offset: Int) throws -> (length: Int, nextOffset: Int) {
        let smReader = SecureMessagingReader(
            commandExecutor: MockRDCNFCCommandExecutor(),
            sessionKey: sessionKey,
            tdesCryptography: tdesCryptography
        )
        return try smReader.parseBERLength(data: data, offset: offset)
    }

    /// Remove padding from decrypted data - delegated to SecureMessagingReader for testing
    internal func removePadding(data: Data) throws -> Data {
        let smReader = SecureMessagingReader(
            commandExecutor: MockRDCNFCCommandExecutor(),
            sessionKey: sessionKey,
            tdesCryptography: tdesCryptography
        )
        return try smReader.removePadding(data: data)
    }

    /// Remove PKCS#7 padding from data - delegated to SecureMessagingReader for testing
    internal func removePKCS7Padding(data: Data) throws -> Data {
        let smReader = SecureMessagingReader(
            commandExecutor: MockRDCNFCCommandExecutor(),
            sessionKey: sessionKey,
            tdesCryptography: tdesCryptography
        )
        return try smReader.removePKCS7Padding(data: data)
    }

    // ステータスワードチェック
    internal func checkStatusWord(sw1: UInt8, sw2: UInt8) throws {
        guard sw1 == 0x90 && sw2 == 0x00 else {
            throw ResidenceCardReaderError.cardError(sw1: sw1, sw2: sw2)
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate
extension ResidenceCardReader: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // セッション開始
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        threadDispatcher.dispatchToMain {
            self.isReadingInProgress = false
        }
        readCompletion?(.failure(error))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first,
              case .iso7816(let iso7816Tag) = tag else {
            sessionManager.invalidate(errorMessage: "対応していないカードです")
            return
        }

        Task {
            do {
                try await sessionManager.connect(to: tag)

                // カード読み取り処理
                let cardData = try await readCard(tag: iso7816Tag)

                // Log successful card read
                print("✅ Card read completed successfully")
                print("   Card data retrieved and logged above")

                await threadDispatcher.dispatchToMainActor {
                    self.sessionManager.invalidate()
                    self.isReadingInProgress = false
                    self.readCompletion?(.success(cardData))
                }
            } catch {
                await threadDispatcher.dispatchToMainActor {
                    self.sessionManager.invalidate(errorMessage: "読み取りに失敗しました")
                    self.isReadingInProgress = false
                    self.readCompletion?(.failure(error))
                }
            }
        }
    }

    // Helper function to create hex dump with ASCII representation
    private func hexDump(_ data: Data, bytesPerLine: Int = 16) -> String {
        var result = ""
        var offset = 0

        while offset < data.count {
            let lineEnd = min(offset + bytesPerLine, data.count)
            let lineData = data.subdata(in: offset..<lineEnd)

            // Offset
            result += String(format: "%08X: ", offset)

            // Hex bytes
            for byte in lineData {
                result += String(format: "%02X ", byte)
            }

            // Padding for incomplete lines
            if lineData.count < bytesPerLine {
                for _ in lineData.count..<bytesPerLine {
                    result += "   "
                }
            }

            result += " |"

            // ASCII representation
            for byte in lineData {
                if byte >= 0x20 && byte < 0x7F {
                    result += String(Character(UnicodeScalar(byte)))
                } else {
                    result += "."
                }
            }

            result += "|\n"
            offset += bytesPerLine
        }

        return result
    }

    // Helper function to save raw image files for sharing
    func saveRawImagesToFiles(_ cardData: ResidenceCardData) -> [URL]? {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory

        // Create a timestamp for unique filenames
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        do {
            // Save raw front image
            let frontImageURL = tempDirectory.appendingPathComponent("front_image_\(timestamp).jpg")
            try cardData.frontImage.write(to: frontImageURL)
            print("✅ Saved raw front image: \(frontImageURL.lastPathComponent) (\(cardData.frontImage.count) bytes)")

            // Save raw face image
            let faceImageURL = tempDirectory.appendingPathComponent("face_image_\(timestamp).jpg")
            try cardData.faceImage.write(to: faceImageURL)
            print("✅ Saved raw face image: \(faceImageURL.lastPathComponent) (\(cardData.faceImage.count) bytes)")

            // Store the file URLs for sharing
            let imageFiles = [frontImageURL, faceImageURL]
            self.lastExportedImageURLs = imageFiles

            print("📦 Raw image files ready for sharing:")
            for url in imageFiles {
                print("   - \(url.lastPathComponent)")
            }

            return imageFiles

        } catch {
            print("❌ Error saving raw image files: \(error)")
            return nil
        }
    }

    // Public method to get the last exported image URLs for sharing
    func getLastExportedImageURLs() -> [URL]? {
        return lastExportedImageURLs
    }

    // Create test data with specified sizes for testing share functionality
    func createTestResidenceCardData() -> ResidenceCardData {
        // Create test front image data (7000 bytes)
        // Start with JPEG header and fill with test pattern
        var frontImageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        frontImageData.append(contentsOf: Array(repeating: 0xAB, count: 7000 - 4))

        // Create test face image data (3000 bytes)
        // Start with JPEG header and fill with test pattern
        var faceImageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        faceImageData.append(contentsOf: Array(repeating: 0xCD, count: 3000 - 4))

        // Create test common data (TLV format)
        let commonData = Data([
            0xC0, 0x02, 0x31, 0x30, // Version "10"
            0xC1, 0x01, 0x31,       // Card type "1" (residence card)
            0xC2, 0x08, 0x32, 0x30, 0x32, 0x34, 0x30, 0x39, 0x31, 0x33 // Date "20240913"
        ])

        // Create test card type data
        let cardTypeData = Data([0xC1, 0x01, 0x31]) // "1" for residence card

        // Create test address data (TLV format with Japanese text)
        let addressText = "東京都新宿区西新宿2-8-1"
        let addressData = Data([0xD4, UInt8(addressText.utf8.count)]) + addressText.data(using: .utf8)!

        // Create test additional data for residence card
        let comprehensivePermission = Data([0x12, 0x10]) + "就労制限なし".data(using: .utf8)!
        let individualPermission = Data([0x13, 0x08]) + "永住者".data(using: .utf8)!
        let extensionApplication = Data([0x14, 0x06]) + "なし".data(using: .utf8)!

        let additionalData = ResidenceCardData.AdditionalData(
            comprehensivePermission: comprehensivePermission,
            individualPermission: individualPermission,
            extensionApplication: extensionApplication
        )

        // Create test check code (256 bytes - RSA-2048 encrypted hash)
        let checkCodeData = Data(Array(0..<256).map { UInt8($0) })

        // Create test certificate data (typical X.509 certificate size)
        let certificateData = Data(Array(0..<1200).map { UInt8($0 % 256) })

        // Create test verification result
        let verificationDetails = ResidenceCardSignatureVerifier.VerificationDetails(
            checkCodeHash: "ABCDEF123456789",
            calculatedHash: "ABCDEF123456789",
            certificateSubject: "Test Certificate Subject",
            certificateIssuer: "Test Certificate Issuer",
            certificateNotBefore: Date(),
            certificateNotAfter: Date().addingTimeInterval(365 * 24 * 60 * 60)
        )

        let verificationResult = ResidenceCardSignatureVerifier.VerificationResult(
            isValid: true,
            error: nil,
            details: verificationDetails
        )

        // Set test card number and session key
        self.cardNumber = "AB12345678CD"
        self.sessionKey = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
                                0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10])

        let testCardData = ResidenceCardData(
            commonData: commonData,
            cardType: cardTypeData,
            frontImage: frontImageData,
            faceImage: faceImageData,
            address: addressData,
            additionalData: additionalData,
            checkCode: checkCodeData,
            certificate: certificateData,
            signatureVerificationResult: verificationResult
        )

        return testCardData
    }

    // Detailed logging function for full hex dump
    private func logDetailedCardData(_ cardData: ResidenceCardData) {
        print("\n")
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║           DETAILED RESIDENCE CARD DATA - FULL HEX DUMP            ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        // Common Data - Full Hex Dump
        print("\n┌─── COMMON DATA (\(cardData.commonData.count) bytes) ───────────────────────────────┐")
        print(hexDump(cardData.commonData))

        // Card Type - Full Hex Dump
        print("\n┌─── CARD TYPE (\(cardData.cardType.count) bytes) ─────────────────────────────────┐")
        print(hexDump(cardData.cardType))
        if let cardTypeString = parseCardType(from: cardData.cardType) {
            print("Parsed Type: \(cardTypeString) (\(cardTypeString == "1" ? "在留カード" : "特別永住者証明書"))")
        }

        // Address - Full Hex Dump
        print("\n┌─── ADDRESS DATA (\(cardData.address.count) bytes) ───────────────────────────────┐")
        print(hexDump(cardData.address))

        // Additional Data (if present) - Full Hex Dump
        if let additional = cardData.additionalData {
            print("\n┌─── COMPREHENSIVE PERMISSION (\(additional.comprehensivePermission.count) bytes) ──────┐")
            print(hexDump(additional.comprehensivePermission))

            print("\n┌─── INDIVIDUAL PERMISSION (\(additional.individualPermission.count) bytes) ────────┐")
            print(hexDump(additional.individualPermission))

            print("\n┌─── EXTENSION APPLICATION (\(additional.extensionApplication.count) bytes) ────────┐")
            print(hexDump(additional.extensionApplication))
        }

        // Front Image - FULL HEX DUMP
        print("\n┌─── FRONT IMAGE - FULL DATA (\(cardData.frontImage.count) bytes) ─────────────────┐")
        print("WARNING: Large data output - \(cardData.frontImage.count) bytes")
        print(hexDump(cardData.frontImage))

        // Face Image - FULL HEX DUMP
        print("\n┌─── FACE IMAGE - FULL DATA (\(cardData.faceImage.count) bytes) ───────────────────┐")
        print("WARNING: Large data output - \(cardData.faceImage.count) bytes")
        print(hexDump(cardData.faceImage))

        // Check Code - Full Hex Dump
        print("\n┌─── CHECK CODE (\(cardData.checkCode.count) bytes) ───────────────────────────────┐")
        print(hexDump(cardData.checkCode))

        // Certificate - Full Hex Dump
        print("\n┌─── CERTIFICATE (\(cardData.certificate.count) bytes) ─────────────────────────────┐")
        print(hexDump(cardData.certificate))

        // Session Key (if available)
        if let sessionKey = self.sessionKey {
            print("\n┌─── SESSION KEY (\(sessionKey.count) bytes) ──────────────────────────────────┐")
            print(hexDump(sessionKey))
        }

        print("\n╔════════════════════════════════════════════════════════════════════╗")
        print("║                    END OF DETAILED HEX DUMP                       ║")
        print("╚════════════════════════════════════════════════════════════════════╝")
        print("\n")
    }

    internal func readCard(tag: NFCISO7816Tag) async throws -> ResidenceCardData {
        // 1. MF選択
        try await selectMF(executor: commandExecutor!)

        // 2. 共通データ要素とカード種別の読み取り
        let commonData = try await readBinaryPlain(executor: commandExecutor!, p1: 0x8B)
        let cardType = try await readBinaryPlain(executor: commandExecutor!, p1: 0x8A)

        // 3. 認証処理
        let sessionKey = try await performAuthentication(executor: commandExecutor!)

        // 4. DF1選択と券面情報読み取り
        try await selectDF(executor: commandExecutor!, aid: AID.df1)
        let frontImage = try await readBinaryWithSM(executor: commandExecutor!, p1: 0x85)
        let faceImage = try await readBinaryWithSM(executor: commandExecutor!, p1: 0x86)

        // 5. DF2選択と裏面情報読み取り
        try await selectDF(executor: commandExecutor!, aid: AID.df2)
        let address = try await readBinaryPlain(executor: commandExecutor!, p1: 0x81)

        // 在留カードの場合は追加フィールドを読み取り
        var additionalData: ResidenceCardData.AdditionalData?
        if isResidenceCard(cardType: cardType) {
            let comprehensivePermission = try await readBinaryPlain(executor: commandExecutor!, p1: 0x82)
            let individualPermission = try await readBinaryPlain(executor: commandExecutor!, p1: 0x83)
            let extensionApplication = try await readBinaryPlain(executor: commandExecutor!, p1: 0x84)

            additionalData = ResidenceCardData.AdditionalData(
                comprehensivePermission: comprehensivePermission,
                individualPermission: individualPermission,
                extensionApplication: extensionApplication
            )
        }

        // 6. DF3選択と電子署名読み取り
        try await selectDF(executor: commandExecutor!, aid: AID.df3)
        let signatureData = try await readBinaryPlain(executor: commandExecutor!, p1: 0x82)

        // 7. 署名データからチェックコードと証明書を抽出
        // Tag 0xDA: チェックコード (256 bytes encrypted hash)
        // Tag 0xDB: 公開鍵証明書 (X.509 certificate)
        guard let checkCode = parseTLV(data: signatureData, tag: 0xDA) else {
            throw ResidenceCardReaderError.invalidResponse
        }
        guard let certificate = parseTLV(data: signatureData, tag: 0xDB) else {
            throw ResidenceCardReaderError.invalidResponse
        }

        // 8. 署名検証 (3.4.3.1 署名検証方法)
        let verificationResult = signatureVerifier.verifySignature(
            checkCode: checkCode,
            certificate: certificate,
            frontImageData: frontImage,
            faceImageData: faceImage
        )

        let cardData = ResidenceCardData(
            commonData: commonData,
            cardType: cardType,
            frontImage: frontImage,
            faceImage: faceImage,
            address: address,
            additionalData: additionalData,
            checkCode: checkCode,
            certificate: certificate,
            signatureVerificationResult: verificationResult
        )

        // Log ResidenceCardData to Xcode console (Summary)
        print("========== ResidenceCardData Output ==========")
        print("📋 Common Data: \(commonData.count) bytes")
        print("   Hex: \(commonData.prefix(50).map { String(format: "%02X", $0) }.joined(separator: " "))\(commonData.count > 50 ? "..." : "")")

        print("\n🎴 Card Type: \(cardType.count) bytes")
        if let cardTypeString = parseCardType(from: cardType) {
            print("   Type: \(cardTypeString) (\(cardTypeString == "1" ? "在留カード" : "特別永住者証明書"))")
        }
        print("   Hex: \(cardType.map { String(format: "%02X", $0) }.joined(separator: " "))")

        print("\n🖼️ Front Image: \(frontImage.count) bytes")
        print("   Format: \(frontImage.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " "))")

        print("\n👤 Face Image: \(faceImage.count) bytes")
        print("   Format: \(faceImage.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " "))")

        print("\n🏠 Address: \(address.count) bytes")
        print("   Hex (first 50): \(address.prefix(50).map { String(format: "%02X", $0) }.joined(separator: " "))\(address.count > 50 ? "..." : "")")

        if let additional = additionalData {
            print("\n📝 Additional Data (在留カード):")
            print("   Comprehensive Permission: \(additional.comprehensivePermission.count) bytes")
            print("   Individual Permission: \(additional.individualPermission.count) bytes")
            print("   Extension Application: \(additional.extensionApplication.count) bytes")
        } else {
            print("\n📝 Additional Data: None (特別永住者証明書)")
        }

        print("\n✍️ Check Code: \(checkCode.count) bytes")
        print("   Hex (first 50): \(checkCode.prefix(50).map { String(format: "%02X", $0) }.joined(separator: " "))\(checkCode.count > 50 ? "..." : "")")

        print("\n🔑 Certificate: \(certificate.count) bytes")
        print("   Hex (first 50): \(certificate.prefix(50).map { String(format: "%02X", $0) }.joined(separator: " "))\(certificate.count > 50 ? "..." : "")")

        if let verificationResult = cardData.signatureVerificationResult {
            print("\n🔐 Signature Verification:")
            print("   Status: \(verificationResult.isValid ? "✅ Valid" : "❌ Invalid")")
            if let details = verificationResult.details {
                print("   Details: \(details)")
            }
        } else {
            print("\n🔐 Signature Verification: Not performed")
        }

        print("\n📊 Summary:")
        let totalSize = commonData.count + cardType.count + frontImage.count + faceImage.count + address.count + checkCode.count + certificate.count
        print("   Total data size: \(totalSize) bytes")
        print("   Card Number: \(cardNumber)")
        print("   Session Key: \(sessionKey.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("===============================================\n")

        // DETAILED FULL HEX DUMP LOG
        logDetailedCardData(cardData)

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
    let checkCode: Data      // Tag 0xDA - 256 bytes encrypted hash
    let certificate: Data    // Tag 0xDB - X.509 public key certificate

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
        lhs.checkCode == rhs.checkCode &&
        lhs.certificate == rhs.certificate
        // Note: signatureVerificationResult is not included in equality check
    }
}


// MARK: - Card Number Validation
extension ResidenceCardReader {

    /// Enhanced validation for residence card number format
    /// Format: 英字2桁 + 数字8桁 + 英字2桁 (Total: 12 characters)
    /// Example: AB12345678CD
    internal func validateCardNumber(_ cardNumber: String) throws -> String {
        // Remove any whitespace and convert to uppercase
        let trimmedCardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Check length (must be exactly 12 characters)
        guard trimmedCardNumber.count == 12 else {
            throw ResidenceCardReaderError.invalidCardNumberLength
        }

        // Check format: 英字2桁 + 数字8桁 + 英字2桁
        guard isValidResidenceCardFormat(trimmedCardNumber) else {
            throw ResidenceCardReaderError.invalidCardNumberFormat
        }

        // Check character validity
        guard isValidCharacters(trimmedCardNumber) else {
            throw ResidenceCardReaderError.invalidCardNumberCharacters
        }

        return trimmedCardNumber
    }

    /// Check if the card number follows the correct format pattern
    internal func isValidResidenceCardFormat(_ cardNumber: String) -> Bool {
        // Pattern: ^[A-Z]{2}[0-9]{8}[A-Z]{2}$
        let pattern = "^[A-Z]{2}[0-9]{8}[A-Z]{2}$"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: cardNumber.utf16.count)
            return regex.firstMatch(in: cardNumber, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    /// Validate individual characters in the card number
    internal func isValidCharacters(_ cardNumber: String) -> Bool {
        let characters = Array(cardNumber)

        // First 2 characters: uppercase letters A-Z
        for i in 0..<2 {
            guard characters[i].isLetter && characters[i].isUppercase else {
                return false
            }
        }

        // Middle 8 characters: digits 0-9
        for i in 2..<10 {
            guard characters[i].isNumber else {
                return false
            }
        }

        // Last 2 characters: uppercase letters A-Z
        for i in 10..<12 {
            guard characters[i].isLetter && characters[i].isUppercase else {
                return false
            }
        }

        return true
    }

    /// Additional validation for known invalid patterns
    internal func hasInvalidPatterns(_ cardNumber: String) -> Bool {
        // Check for obviously invalid patterns like all same characters
        let uniqueChars = Set(cardNumber)
        if uniqueChars.count == 1 {
            return true // All same character is invalid
        }

        // Check for repetitive patterns in the numeric part
        let numericPart = String(cardNumber.dropFirst(2).dropLast(2))
        let numericUniqueChars = Set(numericPart)
        if numericUniqueChars.count == 1 {
            return true // All same digit in numeric part is invalid
        }

        // Check for sequential patterns in the numeric part
        if isSequentialPattern(numericPart) {
            return true
        }

        return false
    }

    /// Check if numeric part contains obvious sequential patterns
    internal func isSequentialPattern(_ numericString: String) -> Bool {
        guard numericString.count >= 3 else { return false }

        let digits = numericString.compactMap { $0.wholeNumberValue }
        guard digits.count == numericString.count else { return false }

        // Check for ascending sequence (e.g., 12345678)
        var isAscending = true
        for i in 1..<digits.count {
            if digits[i] != digits[i-1] + 1 {
                isAscending = false
                break
            }
        }

        // Check for descending sequence (e.g., 87654321)
        var isDescending = true
        for i in 1..<digits.count {
            if digits[i] != digits[i-1] - 1 {
                isDescending = false
                break
            }
        }

        return isAscending || isDescending
    }
}

// MARK: - Cryptography Extensions
extension ResidenceCardReader {




    /// セッション鍵生成（在留カード等仕様書 3.5.2.3）
    ///
    /// 相互認証の完了後に、端末鍵（K.IFD）とカード鍵（K.ICC）から
    /// セキュアメッセージング用のセッション鍵を生成します。
    ///
    /// 鍵生成手順（在留カード等仕様書準拠）:
    /// 1. K.IFD ⊕ K.ICC （16バイト）- XOR演算による鍵の合成
    /// 2. 連結: (K.IFD ⊕ K.ICC) || 00 00 00 01 （20バイト）
    /// 3. SHA-1ハッシュ化（20バイト出力）
    /// 4. 先頭16バイトをセッション鍵として採用
    ///
    /// セキュリティ特性:
    /// - 端末とカードの両方が鍵生成に寄与（相互制御）
    /// - XOR演算により鍵の独立性を確保
    /// - SHA-1による鍵の均一分布
    /// - セッション固有の鍵（リプレイ攻撃防止）
    ///
    /// 生成される鍵の用途:
    /// - セキュアメッセージング暗号化（3DES）
    /// - データの機密性保護
    /// - 通信セッション全体で使用
    ///
    /// - Parameters:
    ///   - kIFD: 端末鍵（16バイト）
    ///   - kICC: カード鍵（16バイト）
    /// - Returns: セッション鍵（16バイト）
    /// - Throws: なし（内部処理エラーなし）
    internal func generateSessionKey(kIFD: Data, kICC: Data) throws -> Data {
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

    /// ICC（カード）認証データの検証とカード鍵抽出
    ///
    /// 在留カード等仕様書 3.5.2.2 の相互認証プロトコルにおいて、
    /// カードから受信した認証データを検証し、カード鍵（K.ICC）を抽出します。
    ///
    /// 検証手順:
    /// 1. MAC検証: M.ICCを検証してE.ICCの完全性を確認
    /// 2. 復号化: E.ICCを3DES復号してカード認証データを取得
    /// 3. チャレンジ検証: RND.ICCの一致を確認（リプレイ攻撃防止）
    /// 4. 端末乱数による相互性の検証: RND.IFDの一致を確認（エコーバック確認）
    /// 5. 鍵抽出: 復号データからK.ICC（16バイト）を抽出
    ///
    /// データ構造（復号後）:
    /// - RND.ICC（8バイト）: カードが最初に送信した乱数
    /// - RND.IFD（8バイト）: 端末が送信した乱数（エコーバック）
    /// - K.ICC（16バイト）: カードが生成したセッション鍵素材
    ///
    /// セキュリティ検証:
    /// - 完全性検証: MAC確認によりデータ改ざん検知
    /// - 認証性検証: 正しい鍵でのみMAC検証が成功
    /// - 新鮮性検証: RND.ICC確認によりリプレイ攻撃防止
    /// - 相互性検証: RND.IFDエコーバック確認
    ///
    /// - Parameters:
    ///   - eICC: カードの暗号化認証データ（32バイト）
    ///   - mICC: カードのMAC（8バイト）
    ///   - rndICC: 事前に受信したカード乱数（8バイト）
    ///   - rndIFD: 端末乱数（8バイト）
    ///   - kEnc: 復号用暗号化鍵（16バイト）
    ///   - kMac: MAC検証用鍵（16バイト）
    /// - Returns: カード鍵K.ICC（16バイト）
    /// - Throws: ResidenceCardReaderError.cryptographyError 検証失敗時
    internal func verifyAndExtractKICC(eICC: Data, mICC: Data, rndICC: Data, rndIFD: Data, kEnc: Data, kMac: Data) throws -> Data {
        // STEP 1: MAC検証 - データ完全性の確認
        // カードから受信したM.ICCと、E.ICCから計算したMACを比較
        let calculatedMAC = try cryptoProvider.calculateRetailMAC(data: eICC, key: kMac)
        guard calculatedMAC == mICC else {
            throw ResidenceCardReaderError.cryptographyError("MAC verification failed")
        }

        // STEP 2: 認証データの復号化
        // E.ICCを3DES復号して32バイトの平文認証データを取得
        let decrypted = try tdesCryptography.performTDES(data: eICC, key: kEnc, encrypt: false)

        // STEP 3: チャレンジ・レスポンス検証
        // 復号データの先頭8バイトが最初のRND.ICCと一致することを確認
        // これによりリプレイ攻撃を防止し、カードの正当性を確認
        guard decrypted.prefix(8) == rndICC else {
            throw ResidenceCardReaderError.cryptographyError("RND.ICC verification failed")
        }

        // STEP 4: 端末乱数による相互性の検証
        // 復号データの8バイト目から16バイト目までが端末のRND.IFDと一致することを確認
        guard decrypted.subdata(in: 8..<16) == rndIFD else {
            throw ResidenceCardReaderError.cryptographyError("RND.IFD verification failed")
        }

        // STEP 5: カード鍵K.ICCの抽出
        // 復号データの最後16バイトがK.ICC（カードセッション鍵素材）
        // この鍵はK.IFDとXORされて最終セッション鍵を生成
        return decrypted.suffix(16)
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

    /// Parse TLV data to extract value for a specific tag
    internal func parseTLV(data: Data, tag: UInt8) -> Data? {
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
