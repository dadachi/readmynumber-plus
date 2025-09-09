import Foundation
import CommonCrypto

/// TDESCryptography class for handling Triple-DES encryption and decryption operations
/// 
/// This class encapsulates Triple-DES cryptographic operations used in residence card reading.
/// It follows the specifications defined in the residence card documentation for 2-key 3DES.
class TDESCryptography {
  
  /// Triple-DES 暗号化・復号化処理
  /// 
  /// 在留カード等仕様書で規定されたTriple-DES（3DES）2-key方式による
  /// 暗号化または復号化を実行します。
  /// 
  /// アルゴリズム仕様:
  /// - 暗号化アルゴリズム: Triple-DES（3DES）
  /// - 鍵長: 128ビット（16バイト、2-key方式）
  /// - 動作モード: CBC（Cipher Block Chaining）
  /// - パディング: PKCS#7（ISO/IEC 7816-4準拠）
  /// - 初期化ベクトル: All zeros（0x00 * 8）
  /// 
  /// 2-key Triple-DES処理:
  /// - 暗号化: DES_Encrypt(K1) → DES_Decrypt(K2) → DES_Encrypt(K1)
  /// - 復号化: DES_Decrypt(K1) → DES_Encrypt(K2) → DES_Decrypt(K1)
  /// - K1 = key[0..7], K2 = key[8..15]
  /// 
  /// セキュリティレベル:
  /// - 実効鍵長: 112ビット（2-key 3DES）
  /// - レガシー暗号化方式だが在留カード仕様で必須
  /// 
  /// - Parameters:
  ///   - data: 暗号化または復号化する入力データ
  ///   - key: 16バイトの暗号化鍵（2-key 3DES用）
  ///   - encrypt: true=暗号化, false=復号化
  /// - Returns: 処理されたデータ
  /// - Throws: CardReaderError.cryptographyError 処理失敗時
  func performTDES(data: Data, key: Data, encrypt: Bool) throws -> Data {
    guard key.count == 16 else {
      throw CardReaderError.cryptographyError("Invalid key length: \(key.count), expected 16")
    }
    
    // Convert 2-key (16 bytes) to 3-key (24 bytes) for CommonCrypto
    // For 2-key 3DES: K1=key[0..7], K2=key[8..15], K3=K1
    var key3DES = Data()
    key3DES.append(key)           // K1 and K2 (16 bytes)
    key3DES.append(key.prefix(8)) // K3 = K1 (8 bytes)
    
    // TDES 3-key implementation using CommonCrypto
    // Allocate enough space for result including padding
    // For empty data, we still need at least one block
    let paddedSize = max(kCCBlockSize3DES, ((data.count + kCCBlockSize3DES - 1) / kCCBlockSize3DES) * kCCBlockSize3DES)
    let bufferSize = paddedSize + kCCBlockSize3DES
    var result = Data(count: bufferSize)
    var numBytesProcessed: size_t = 0
    
    let operation = encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt)
    
    // CommonCrypto APIを使用した3DES処理
    let status = result.withUnsafeMutableBytes { resultBytes in
      data.withUnsafeBytes { dataBytes in
        key3DES.withUnsafeBytes { keyBytes in
          CCCrypt(operation,
                  CCAlgorithm(kCCAlgorithm3DES),       // Triple-DES
                  CCOptions(data.isEmpty || data.count % 8 != 0 ? kCCOptionPKCS7Padding : 0), // 空データまたは8の倍数でない場合はパディング
                  keyBytes.bindMemory(to: UInt8.self).baseAddress, 
                  kCCKeySize3DES,                       // 24 bytes for 3DES
                  nil,                                  // IV = zeros（CBCモード）
                  dataBytes.bindMemory(to: UInt8.self).baseAddress, 
                  data.count,                           // data length
                  resultBytes.bindMemory(to: UInt8.self).baseAddress, 
                  bufferSize,                           // output buffer size
                  &numBytesProcessed)
        }
      }
    }
    
    guard status == kCCSuccess else {
      let errorMessage: String
      switch Int(status) {
      case Int(kCCParamError):
        errorMessage = "TDES parameter error"
      case Int(kCCBufferTooSmall):
        errorMessage = "TDES buffer too small"
      case Int(kCCMemoryFailure):
        errorMessage = "TDES memory failure"
      case Int(kCCAlignmentError):
        errorMessage = "TDES alignment error"
      case Int(kCCDecodeError):
        errorMessage = "TDES decode error"
      case Int(kCCUnimplemented):
        errorMessage = "TDES unimplemented"
      default:
        errorMessage = "TDES operation failed with status: \(status)"
      }
      throw CardReaderError.cryptographyError(errorMessage)
    }
    
    result.count = numBytesProcessed
    return result
  }
}