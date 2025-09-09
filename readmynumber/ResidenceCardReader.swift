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
  private static let maxAPDUResponseLength: Int = 1694
  
  // MARK: - Properties
  private var cardNumber: String = ""
  internal var sessionKey: Data? // Made internal for testing
  internal var readCompletion: ((Result<ResidenceCardData, Error>) -> Void)? // Made internal for testing
  @Published var isReadingInProgress: Bool = false
  
  // Dependency injection for testability
  private var commandExecutor: NFCCommandExecutor?
  private var sessionManager: NFCSessionManager
  private var threadDispatcher: ThreadDispatcher
  private var signatureVerifier: SignatureVerifier
  internal var tdesCryptography: TDESCryptography
  
  // MARK: - Initialization
  
  /// Initialize with default implementations
  override init() {
    self.sessionManager = NFCSessionManagerImpl()
    self.threadDispatcher = SystemThreadDispatcher()
    self.signatureVerifier = ResidenceCardSignatureVerifier()
    self.tdesCryptography = TDESCryptography()
    super.init()
  }
  
  /// Initialize with custom dependencies for testing
  init(
    sessionManager: NFCSessionManager,
    threadDispatcher: ThreadDispatcher,
    signatureVerifier: SignatureVerifier,
    tdesCryptography: TDESCryptography = TDESCryptography()
  ) {
    self.sessionManager = sessionManager
    self.threadDispatcher = threadDispatcher
    self.signatureVerifier = signatureVerifier
    self.tdesCryptography = tdesCryptography
    super.init()
  }
  
  // MARK: - Public Methods
  
  /// Set a custom command executor for testing
  func setCommandExecutor(_ executor: NFCCommandExecutor) {
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
      completion(.failure(CardReaderError.nfcNotAvailable))
      return
    }
    
    // Check if we're in test environment (no real NFC or simulator)
    guard sessionManager.isReadingAvailable else {
      completion(.failure(CardReaderError.nfcNotAvailable))
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
  internal func selectMF(tag: NFCISO7816Tag) async throws {
    let executor = commandExecutor ?? NFCCommandExecutorImpl(tag: tag)
    try await selectMF(executor: executor)
  }
  
  internal func selectMF(executor: NFCCommandExecutor) async throws {
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
  internal func selectDF(tag: NFCISO7816Tag, aid: Data) async throws {
    let executor = commandExecutor ?? NFCCommandExecutorImpl(tag: tag)
    try await selectDF(executor: executor, aid: aid)
  }
  
  internal func selectDF(executor: NFCCommandExecutor, aid: Data) async throws {
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
  internal func performAuthentication(tag: NFCISO7816Tag) async throws {
    let executor = commandExecutor ?? NFCCommandExecutorImpl(tag: tag)
    try await performAuthentication(executor: executor)
  }
  
  internal func performAuthentication(executor: NFCCommandExecutor) async throws {
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
    let (kEnc, kMac) = try generateKeys(from: cardNumber)
    
    // IFD（端末）側の認証データを生成:
    // - RND.IFD（端末乱数8バイト）+ RND.ICC（カード乱数8バイト）+ K.IFD（端末鍵16バイト）
    // - この32バイトデータを3DES暗号化してE.IFDを作成
    // - E.IFDのRetail MACを計算してM.IFDを作成
    let (eIFD, mIFD, rndIFD, kIFD) = try generateAuthenticationData(rndICC: rndICC, kEnc: kEnc, kMac: kMac)
    
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
    sessionKey = try generateSessionKey(kIFD: kIFD, kICC: kICC)
    
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
  }
  
  // バイナリ読み出し（SMあり）
  internal func readBinaryWithSM(tag: NFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
    let executor = commandExecutor ?? NFCCommandExecutorImpl(tag: tag)
    let smReader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
    return try await smReader.readBinaryWithSM(p1: p1, p2: p2)
  }
  
  // バイナリ読み出し（SMあり、チャンク対応）
  internal func readBinaryChunkedWithSM(tag: NFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
    let executor = commandExecutor ?? NFCCommandExecutorImpl(tag: tag)
    let smReader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
    return try await smReader.readBinaryChunkedWithSM(p1: p1, p2: p2)
  }
  
  
  // バイナリ読み出し（平文）
  internal func readBinaryPlain(tag: NFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
    let executor = commandExecutor ?? NFCCommandExecutorImpl(tag: tag)
    let plainReader = PlainBinaryReader(commandExecutor: executor)
    return try await plainReader.readBinaryPlain(p1: p1, p2: p2)
  }
  
  // 暗号化・復号化処理
  internal func encryptCardNumber(cardNumber: String, sessionKey: Data) throws -> Data {
    guard let cardNumberData = cardNumber.data(using: .ascii),
          cardNumberData.count == 12 else {
      throw CardReaderError.invalidCardNumber
    }
    
    // パディング追加
    let paddedData = cardNumberData + Data([0x80, 0x00, 0x00, 0x00])
    
    // TDES 2key CBC暗号化
    return try tdesCryptography.performTDES(data: paddedData, key: sessionKey, encrypt: true)
  }
  
  internal func decryptSMResponse(encryptedData: Data) throws -> Data {
    // セッションキーの存在確認
    guard let sessionKey = sessionKey else {
      throw CardReaderError.cryptographyError("Session key not available")
    }
    
    // TLV構造から暗号化データを取り出す
    guard encryptedData.count > 3,
          encryptedData[0] == 0x86 else {
      throw CardReaderError.invalidResponse
    }
    
    let (length, nextOffset) = try parseBERLength(data: encryptedData, offset: 1)
    guard encryptedData.count >= nextOffset + length,
          length > 1,
          encryptedData[nextOffset] == 0x01 else {
      throw CardReaderError.invalidResponse
    }
    
    let ciphertext = encryptedData.subdata(in: (nextOffset + 1)..<(nextOffset + length))
    
    // 復号化
    let decrypted = try tdesCryptography.performTDES(data: ciphertext, key: sessionKey, encrypt: false)
    
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
  
  internal func readCard(tag: NFCISO7816Tag) async throws -> ResidenceCardData {
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
    let verificationResult = signatureVerifier.verifySignature(
      signatureData: signature,
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
  case invalidCardNumberFormat
  case invalidCardNumberLength
  case invalidCardNumberCharacters
  case invalidResponse
  case cardError(sw1: UInt8, sw2: UInt8)
  case cryptographyError(String)
  
  var errorDescription: String? {
    switch self {
    case .nfcNotAvailable:
      return "NFCが利用できません"
    case .invalidCardNumber:
      return "無効な在留カード番号です"
    case .invalidCardNumberFormat:
      return "在留カード番号の形式が正しくありません（英字2桁+数字8桁+英字2桁）"
    case .invalidCardNumberLength:
      return "在留カード番号は12桁で入力してください"
    case .invalidCardNumberCharacters:
      return "在留カード番号に無効な文字が含まれています"
    case .invalidResponse:
      return "カードからの応答が不正です"
    case .cardError(let sw1, let sw2):
      return String(format: "カードエラー: SW1=%02X, SW2=%02X", sw1, sw2)
    case .cryptographyError(let message):
      return "暗号処理エラー: \(message)"
    }
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
      throw CardReaderError.invalidCardNumberLength
    }
    
    // Check format: 英字2桁 + 数字8桁 + 英字2桁
    guard isValidResidenceCardFormat(trimmedCardNumber) else {
      throw CardReaderError.invalidCardNumberFormat
    }
    
    // Check character validity
    guard isValidCharacters(trimmedCardNumber) else {
      throw CardReaderError.invalidCardNumberCharacters
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
  
  /// 在留カード番号から認証鍵を生成
  /// 
  /// 在留カード等仕様書 3.5.2.1 に従って、在留カード番号から認証に使用する
  /// 暗号化鍵（K.Enc）とMAC鍵（K.Mac）を生成します。
  /// 
  /// 処理手順:
  /// 1. 在留カード番号（12文字ASCII）をSHA-1でハッシュ化（20バイト出力）
  /// 2. ハッシュの先頭16バイトを暗号化鍵とMAC鍵の両方に使用
  /// 
  /// セキュリティ考慮事項:
  /// - SHA-1を使用するのは仕様書の要求による（レガシー仕様）
  /// - 同一鍵を暗号化とMACに使用（仕様書準拠）
  /// - カード番号の秘匿性がセキュリティの基盤となる
  /// 
  /// - Parameter cardNumber: 12文字の在留カード番号（英数字）
  /// - Returns: 暗号化鍵とMAC鍵のタプル（両方とも16バイト）
  /// - Throws: CardReaderError.invalidCardNumber カード番号が無効な場合
  internal func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data) {
    guard let cardNumberData = cardNumber.data(using: .ascii) else {
      throw CardReaderError.invalidCardNumber
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
  
  /// IFD（端末）側の相互認証データ生成
  /// 
  /// 在留カード等仕様書 3.5.2.2 の相互認証プロトコルに従って、
  /// 端末側の認証データ（E.IFD, M.IFD）を生成します。
  /// 
  /// データ構造:
  /// 1. RND.IFD（8バイト）: 端末が生成するランダム数
  /// 2. RND.ICC（8バイト）: カードから受信したランダム数
  /// 3. K.IFD（16バイト）: 端末が生成するセッション鍵素材
  /// 
  /// 暗号化プロセス:
  /// 1. 平文 = RND.IFD || RND.ICC || K.IFD （32バイト）
  /// 2. E.IFD = 3DES_Encrypt(平文, K.Enc) （32バイト）
  /// 3. M.IFD = RetailMAC(E.IFD, K.Mac) （8バイト）
  /// 
  /// セキュリティ機能:
  /// - Challenge-Response認証によるリプレイ攻撃防止
  /// - MAC による完全性保護
  /// - セッション鍵の安全な交換
  /// 
  /// - Parameters:
  ///   - rndICC: カードから受信した8バイトのランダム数
  ///   - kEnc: 暗号化に使用する16バイト鍵
  ///   - kMac: MAC計算に使用する16バイト鍵
  /// - Returns: 暗号化データ、MAC、端末鍵のタプル
  /// - Throws: CardReaderError.cryptographyError 暗号化処理失敗時
  internal func generateAuthenticationData(rndICC: Data, kEnc: Data, kMac: Data) throws -> (eIFD: Data, mIFD: Data, rndIFD: Data, kIFD: Data) {
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
    let mIFD = try calculateRetailMAC(data: eIFD, key: kMac)
    
    return (eIFD: eIFD, mIFD: mIFD, rndIFD: rndIFD, kIFD: kIFD)
  }
  
  
  /// Retail MAC計算（ISO/IEC 9797-1 Algorithm 3）
  /// 
  /// 在留カード等仕様書で規定されたRetail MAC（リテールMAC）を計算します。
  /// これはデータの完全性を保護するためのメッセージ認証コードです。
  /// 
  /// アルゴリズム（ISO/IEC 9797-1 Algorithm 3準拠）:
  /// 1. Padding Method 2適用: 0x80を追加し、必要に応じて0x00でパディング
  /// 2. 初期変換: 最後のブロック以外をDES（K1）で処理
  /// 3. 最終変換: 最後のブロックを3DES（K1,K2,K1）で処理
  /// 4. 最終ブロック（8バイト）をMACとして返す
  /// 
  /// 仕様準拠:
  /// - ISO/IEC 9797-1 Algorithm 3（Retail MAC）
  /// - ISO/IEC 9797-1 Padding Method 2
  /// - 2-key Triple-DES
  /// - 出力長: 8バイト
  /// 
  /// セキュリティ機能:
  /// - データ改ざん検知
  /// - 完全性保護
  /// - 認証機能（鍵を知る者のみが正しいMACを生成可能）
  /// 
  /// - Parameters:
  ///   - data: MAC計算対象データ
  ///   - key: 16バイトのMAC鍵（K1||K2）
  /// - Returns: 8バイトのMAC値
  /// - Throws: CardReaderError.cryptographyError MAC計算失敗時
  internal func calculateRetailMAC(data: Data, key: Data) throws -> Data {
    guard key.count == 16 else {
      throw CardReaderError.cryptographyError("Invalid key length for Retail MAC")
    }
    
    // ISO/IEC 9797-1 Padding Method 2: Add 0x80 followed by 0x00s
    var paddedData = data
    paddedData.append(0x80)
    while paddedData.count % 8 != 0 {
      paddedData.append(0x00)
    }
    
    // Split the key for DES operations
    let k1 = key.prefix(8)
    let k2 = key.suffix(8)
    
    // Process data in 8-byte blocks
    let numBlocks = paddedData.count / 8
    var mac = Data(repeating: 0, count: 8) // Initialize with zeros (IV)
    
    for i in 0..<numBlocks {
      let blockStart = i * 8
      let block = paddedData.subdata(in: blockStart..<(blockStart + 8))
      
      // XOR with previous MAC result (CBC mode)
      let xorBlock = Data(zip(block, mac).map { $0 ^ $1 })
      
      if i < numBlocks - 1 {
        // Initial transformation: Single DES with K1 for all blocks except the last
        mac = try performSingleDES(data: xorBlock, key: k1, encrypt: true)
      } else {
        // Final transformation: Triple DES for the last block
        // DES-EDE3: Encrypt with K1, Decrypt with K2, Encrypt with K1
        let step1 = try performSingleDES(data: xorBlock, key: k1, encrypt: true)
        let step2 = try performSingleDES(data: step1, key: k2, encrypt: false)
        mac = try performSingleDES(data: step2, key: k1, encrypt: true)
      }
    }
    
    return mac
  }
  
  /// Single DES operation helper for Retail MAC
  internal func performSingleDES(data: Data, key: Data, encrypt: Bool) throws -> Data {
    guard key.count == 8 && data.count == 8 else {
      throw CardReaderError.cryptographyError("Invalid data or key length for single DES")
    }
    
    var result = Data(repeating: 0, count: 8)
    var numBytesProcessed: size_t = 0
    
    let status = result.withUnsafeMutableBytes { resultBytes in
      data.withUnsafeBytes { dataBytes in
        key.withUnsafeBytes { keyBytes in
          CCCrypt(
            encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmDES),
            CCOptions(kCCOptionECBMode), // ECB mode for single block
            keyBytes.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeDES,
            nil, // No IV for ECB mode
            dataBytes.bindMemory(to: UInt8.self).baseAddress, 8,
            resultBytes.bindMemory(to: UInt8.self).baseAddress, 8,
            &numBytesProcessed
          )
        }
      }
    }
    
    guard status == kCCSuccess else {
      throw CardReaderError.cryptographyError("Single DES operation failed")
    }
    
    return result
  }
  
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
  /// - Throws: CardReaderError.cryptographyError 検証失敗時
  internal func verifyAndExtractKICC(eICC: Data, mICC: Data, rndICC: Data, rndIFD: Data, kEnc: Data, kMac: Data) throws -> Data {
    // STEP 1: MAC検証 - データ完全性の確認
    // カードから受信したM.ICCと、E.ICCから計算したMACを比較
    let calculatedMAC = try calculateRetailMAC(data: eICC, key: kMac)
    guard calculatedMAC == mICC else {
      throw CardReaderError.cryptographyError("MAC verification failed")
    }
    
    // STEP 2: 認証データの復号化
    // E.ICCを3DES復号して32バイトの平文認証データを取得
    let decrypted = try tdesCryptography.performTDES(data: eICC, key: kEnc, encrypt: false)
    
    // STEP 3: チャレンジ・レスポンス検証
    // 復号データの先頭8バイトが最初のRND.ICCと一致することを確認
    // これによりリプレイ攻撃を防止し、カードの正当性を確認
    guard decrypted.prefix(8) == rndICC else {
      throw CardReaderError.cryptographyError("RND.ICC verification failed")
    }
    
    // STEP 4: 端末乱数による相互性の検証
    // 復号データの8バイト目から16バイト目までが端末のRND.IFDと一致することを確認
    guard decrypted.subdata(in: 8..<16) == rndIFD else {
      throw CardReaderError.cryptographyError("RND.IFD verification failed")
    }
    
    // STEP 5: カード鍵K.ICCの抽出
    // 復号データの最後16バイトがK.ICC（カードセッション鍵素材）
    // この鍵はK.IFDとXORされて最終セッション鍵を生成
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
    guard !data.isEmpty else {
      throw CardReaderError.invalidResponse
    }
    
    // Try ISO/IEC 7816-4 padding first (0x80 format)
    if let paddingIndex = data.lastIndex(of: 0x80) {
      // Check that all bytes after 0x80 are 0x00
      for i in (paddingIndex + 1)..<data.count {
        guard data[i] == 0x00 else {
          // Invalid ISO 7816-4 padding - has non-zero bytes after 0x80
          // Don't fallback to PKCS#7 if 0x80 is present but invalid
          throw CardReaderError.invalidResponse
        }
      }
      return data.prefix(paddingIndex)
    }
    
    // No 0x80 found, try PKCS#7 padding
    return try removePKCS7Padding(data: data)
  }
  
  internal func removePKCS7Padding(data: Data) throws -> Data {
    guard !data.isEmpty else {
      throw CardReaderError.invalidResponse
    }
    
    // PKCS#7 パディング除去
    let paddingLength = Int(data.last!)
    
    // パディング長が有効範囲内かチェック
    guard paddingLength > 0 && paddingLength <= kCCBlockSize3DES && paddingLength <= data.count else {
      throw CardReaderError.invalidResponse
    }
    
    // パディングバイトがすべて同じ値（パディング長）かチェック
    let paddingStart = data.count - paddingLength
    for i in paddingStart..<data.count {
      guard data[i] == paddingLength else {
        throw CardReaderError.invalidResponse
      }
    }
    
    return data.prefix(paddingStart)
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
