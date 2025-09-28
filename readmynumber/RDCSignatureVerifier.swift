import Foundation
import CryptoKit
import Security

// MARK: - Verification Result Types

/// Result of signature verification with detailed information
public struct RDCVerificationResult {
    public let isValid: Bool
    public let error: RDCVerificationError?
    public let details: RDCVerificationDetails?

    public init(isValid: Bool, error: RDCVerificationError?, details: RDCVerificationDetails?) {
        self.isValid = isValid
        self.error = error
        self.details = details
    }
}

/// Detailed information about the verification process
public struct RDCVerificationDetails {
    public let checkCodeHash: String?
    public let calculatedHash: String?
    public let certificateSubject: String?
    public let certificateIssuer: String?
    public let certificateNotBefore: Date?
    public let certificateNotAfter: Date?

    public init(checkCodeHash: String?, calculatedHash: String?, certificateSubject: String?, certificateIssuer: String?, certificateNotBefore: Date?, certificateNotAfter: Date?) {
        self.checkCodeHash = checkCodeHash
        self.calculatedHash = calculatedHash
        self.certificateSubject = certificateSubject
        self.certificateIssuer = certificateIssuer
        self.certificateNotBefore = certificateNotBefore
        self.certificateNotAfter = certificateNotAfter
    }
}

/// Errors that can occur during signature verification
public enum RDCVerificationError: LocalizedError {
    case missingCheckCode
    case missingCertificate
    case invalidCertificate
    case invalidCheckCodeLength
    case publicKeyExtractionFailed
    case rsaDecryptionFailed
    case hashMismatch
    case invalidPaddingFormat
    case missingImageData

    public var errorDescription: String? {
        switch self {
        case .missingCheckCode:
            return "チェックコードが見つかりません"
        case .missingCertificate:
            return "公開鍵証明書が見つかりません"
        case .invalidCertificate:
            return "無効な公開鍵証明書です"
        case .invalidCheckCodeLength:
            return "チェックコードの長さが不正です"
        case .publicKeyExtractionFailed:
            return "公開鍵の抽出に失敗しました"
        case .rsaDecryptionFailed:
            return "RSA復号に失敗しました"
        case .hashMismatch:
            return "ハッシュ値が一致しません"
        case .invalidPaddingFormat:
            return "パディング形式が不正です"
        case .missingImageData:
            return "画像データが見つかりません"
        }
    }
}

// MARK: - Signature Verifier Protocol

/// Protocol for residence card signature verification
protocol RDCSignatureVerifier {
    /// Verify the digital signature of residence card data
    /// - Parameters:
    ///   - checkCode: The check code (tag 0xDA) - 256 bytes encrypted hash
    ///   - certificate: The X.509 certificate (tag 0xDB)
    ///   - frontImageData: The front image data from DF1/EF01
    ///   - faceImageData: The face image data from DF1/EF02
    /// - Returns: Verification result
    func verifySignature(
        checkCode: Data,
        certificate: Data,
        frontImageData: Data,
        faceImageData: Data
    ) -> RDCVerificationResult
}

// MARK: - Mock Signature Verifier

/// Mock implementation for testing
class MockRDCSignatureVerifier: RDCSignatureVerifier {
    var shouldReturnValid = true
    var mockError: RDCVerificationError?
    var verificationCalls: [(signatureData: Data, frontImageData: Data, faceImageData: Data)] = []

    func verifySignature(
        checkCode: Data,
        certificate: Data,
        frontImageData: Data,
        faceImageData: Data
    ) -> RDCVerificationResult {
        // Store simple combined data for backwards compatibility
        let combinedData = checkCode + certificate
        verificationCalls.append((combinedData, frontImageData, faceImageData))

        if shouldReturnValid {
            return RDCVerificationResult(isValid: true, error: nil, details: nil)
        } else {
            return RDCVerificationResult(
                isValid: false,
                error: mockError ?? RDCVerificationError.invalidCertificate,
                details: nil
            )
        }
    }
    
    func reset() {
        shouldReturnValid = true
        mockError = nil
        verificationCalls.removeAll()
    }
}

// MARK: - Residence Card Signature Verifier
// Implementation of section 3.4.3.1 (署名検証方法) from 在留カード等仕様書
//
// This class implements the digital signature verification process for Japanese Residence Cards
// according to the technical specification document. The verification process follows the
// standardized data reading procedures and authentication sequence defined in sections 3.5
// and 3.5.2 of the specification.
//
// Data Reading Procedure (3.5 データの読み出し手順):
// The residence card IC chip contains multiple data files (DF/EF) that must be read in a
// specific sequence:
// 1. DF1/EF01 - 券面（表）イメージ (Front card image data)
// 2. DF1/EF02 - 顔画像 (Face photo image data)  
// 3. DF3/EF01 - 署名用データ (Digital signature data)
//
// Authentication Sequence (3.5.2 認証シーケンス):
// The signature verification follows this standardized sequence:
// 1. Read signature data from DF3/EF01 containing:
//    - チェックコード (Check code - encrypted hash, tag 0xDA, 256 bytes)
//    - 公開鍵証明書 (Public key certificate - X.509 format, tag 0xDB)
// 2. Extract RSA-2048 public key from X.509 certificate
// 3. Decrypt check code using RSA public key (signature verification operation)
// 4. Extract SHA-256 hash from decrypted data (remove PKCS#1 v1.5 padding)
// 5. Read and process image data from DF1/EF01 and DF1/EF02
// 6. Apply fixed-length padding (7000 bytes for front, 3000 bytes for face)
// 7. Concatenate padded image data and calculate SHA-256 hash
// 8. Compare calculated hash with extracted hash for verification
//
// APDU Command Sequence Context:
// This verification process works with data obtained through NFC APDU commands:
// 1. SELECT DF1 (00 A4 01 0C 02 00 01) - Select DF1 directory
// 2. SELECT EF01 (00 A4 02 0C 02 00 01) - Select front image file
// 3. READ BINARY (00 B0 xx xx Le) - Read front image data in blocks
// 4. SELECT EF02 (00 A4 02 0C 02 00 02) - Select face image file  
// 5. READ BINARY (00 B0 xx xx Le) - Read face image data in blocks
// 6. SELECT DF3 (00 A4 01 0C 02 00 03) - Select DF3 directory
// 7. SELECT EF01 (00 A4 02 0C 02 00 01) - Select signature data file
// 8. READ BINARY (00 B0 xx xx Le) - Read signature data in blocks
//
// The APDU responses contain the TLV-structured data that this verifier processes.
public class ResidenceCardSignatureVerifier: RDCSignatureVerifier {

    // MARK: - Constants
    // These constants are defined according to 在留カード等仕様書 specifications
    private enum Constants {
        // TLV Tags for signature data extraction (section 3.5.2 認証シーケンス)
        static let checkCodeTag: UInt8 = 0xDA      // チェックコード (encrypted hash)
        static let certificateTag: UInt8 = 0xDB    // 公開鍵証明書 (X.509 certificate)
        
        // Cryptographic parameters for RSA-2048 with SHA-256
        static let checkCodeLength = 256           // RSA-2048 signature length (2048 bits = 256 bytes)
        static let hashLength = 32                 // SHA-256 output length (256 bits = 32 bytes)
        static let rsaKeySize = 2048               // RSA key size for signature verification
        
        // Fixed-length requirements for image data (sections 3.3.4.3 and 3.3.4.4)
        // These lengths ensure consistent hash calculation during signature verification
        static let frontImageFixedLength = 7000   // 券面（表）イメージ fixed length
        static let faceImageFixedLength = 3000    // 顔画像 fixed length
    }
    
    // MARK: - Initializer
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Verify the digital signature according to section 3.4.3.1 of 在留カード等仕様書
    ///
    /// This method implements the complete authentication sequence (3.5.2 認証シーケンス) by:
    /// 1. Following the data reading procedure (3.5 データの読み出し手順)
    /// 2. Performing cryptographic verification using RSA-2048 and SHA-256
    /// 3. Ensuring data integrity through fixed-length padding validation
    ///
    /// The verification process validates that the image data has not been tampered with
    /// by comparing a digitally signed hash with a calculated hash of the actual image data.
    ///
    /// - Parameters:
    ///   - checkCode: The check code (tag 0xDA) - 256 bytes encrypted hash
    ///   - certificate: The X.509 certificate (tag 0xDB) in DER format
    ///   - frontImageData: The front image data from DF1/EF01 (券面イメージ) - must be exactly 7000 bytes after padding
    ///   - faceImageData: The face image data from DF1/EF02 (顔画像) - must be exactly 3000 bytes after padding
    /// - Returns: Verification result with detailed information about the verification process
    public func verifySignature(
        checkCode: Data,
        certificate: Data,
        frontImageData: Data,
        faceImageData: Data
    ) -> RDCVerificationResult {

        // STEP 1: Validate check code and certificate data
        // The check code should be exactly 256 bytes (RSA-2048 encrypted hash)
        guard checkCode.count == Constants.checkCodeLength else {
            return RDCVerificationResult(isValid: false, error: RDCVerificationError.invalidCheckCodeLength, details: nil)
        }

        // Certificate should exist and be non-empty
        guard !certificate.isEmpty else {
            return RDCVerificationResult(isValid: false, error: RDCVerificationError.missingCertificate, details: nil)
        }
        
        // STEP 2: Extract RSA-2048 public key from X.509 certificate
        // The certificate is in DER format and contains the issuer's public key
        // used for verifying the digital signature created during card personalization
        guard let publicKey = extractPublicKey(from: certificate) else {
            return RDCVerificationResult(isValid: false, error: RDCVerificationError.publicKeyExtractionFailed, details: nil)
        }
        
        // STEP 3: Decrypt (verify) check code using RSA-2048 public key
        // In RSA signature verification, we "decrypt" the signature with the public key
        // to retrieve the original hash that was encrypted with the private key during signing
        // This implements the mathematical operation: signature^e mod n = padded_hash
        guard let decryptedData = rsaDecrypt(checkCode: checkCode, publicKey: publicKey) else {
            return RDCVerificationResult(isValid: false, error: RDCVerificationError.rsaDecryptionFailed, details: nil)
        }
        
        // STEP 4: Extract SHA-256 hash from PKCS#1 v1.5 padded data
        // The decrypted data contains padding in format: 0x00 || 0x01 || PS || 0x00 || DigestInfo
        // where PS is padding string of 0xFF bytes and DigestInfo contains the SHA-256 hash
        guard let extractedHash = extractHashFromPKCS1(decryptedData) else {
            return RDCVerificationResult(isValid: false, error: RDCVerificationError.invalidPaddingFormat, details: nil)
        }
        
        // STEP 5: Process image data following 3.5 データの読み出し手順
        // Extract image values from DF1/EF01 (front) and DF1/EF02 (face) and apply fixed-length padding
        // According to sections 3.3.4.3 and 3.3.4.4: 
        // - Front image must be exactly 7000 bytes (pad with 0x00 if shorter)
        // - Face image must be exactly 3000 bytes (pad with 0x00 if shorter)
        guard let frontImageValue = extractImageValue(from: frontImageData),
              let faceImageValue = extractImageValue(from: faceImageData) else {
            return RDCVerificationResult(isValid: false, error: RDCVerificationError.missingImageData, details: nil)
        }
        
        // STEP 6: Create signature target data (署名対象データ)
        // Concatenate the fixed-length padded image data in the specified order:
        // [7000-byte front image] + [3000-byte face image] = 10000 bytes total
        // This is the exact data that was hashed during card personalization
        let concatenatedData = frontImageValue + faceImageValue
        
        // STEP 7: Calculate SHA-256 hash of the signature target data
        // This recreates the same hash calculation that was performed during card issuance
        let calculatedHash = SHA256.hash(data: concatenatedData)
        let calculatedHashData = Data(calculatedHash)
        
        // STEP 8: Compare extracted hash with calculated hash
        // If they match, the image data integrity is verified and has not been tampered with
        let isValid = extractedHash == calculatedHashData
        
        // Get certificate details for display
        let details = extractCertificateDetails(from: certificate)
        
        let verificationDetails = RDCVerificationDetails(
            checkCodeHash: extractedHash.hexString,
            calculatedHash: calculatedHashData.hexString,
            certificateSubject: details.subject,
            certificateIssuer: details.issuer,
            certificateNotBefore: details.notBefore,
            certificateNotAfter: details.notAfter
        )
        
        return RDCVerificationResult(
            isValid: isValid,
            error: isValid ? nil : RDCVerificationError.hashMismatch,
            details: verificationDetails
        )
    }

    // MARK: - Private Methods
    
    private func extractImageValue(from imageData: Data) -> Data? {
        // Extract and process image data following the TLV structure defined in 3.5 データの読み出し手順
        // 
        // TLV Structure Analysis:
        // - Tag 0xD0: 券面（表）イメージ (Front card image)
        // - Tag 0xD1: 顔画像 (Face photo image)
        //
        // According to sections 3.3.4.3 and 3.3.4.4 of 在留カード等仕様書:
        // The signature verification requires fixed-length data to ensure consistency:
        // - Front image (0xD0): Fixed length of 7000 bytes
        // - Face image (0xD1): Fixed length of 3000 bytes
        // - If actual data is shorter, pad with 0x00 bytes at the end
        // - If actual data is longer, truncate to fixed length
        //
        // This padding is crucial for signature verification as the hash calculation
        // during card personalization used these exact fixed lengths.
        
        var extractedValue: Data?
        var targetLength: Int?
        
        if let value = parseTLV(data: imageData, tag: 0xD0) {
            extractedValue = value
            targetLength = Constants.frontImageFixedLength
        } else if let value = parseTLV(data: imageData, tag: 0xD1) {
            extractedValue = value
            targetLength = Constants.faceImageFixedLength
        } else if !imageData.isEmpty {
            // If not in TLV format, return the whole data
            return imageData
        }
        
        guard let value = extractedValue, let fixedLength = targetLength else {
            return nil
        }
        
        // Pad with 0x00 to fixed length if necessary
        if value.count < fixedLength {
            var paddedValue = value
            paddedValue.append(Data(repeating: 0x00, count: fixedLength - value.count))
            return paddedValue
        } else if value.count > fixedLength {
            // If data is longer than fixed length, truncate it
            return value.prefix(fixedLength)
        }
        
        return value
    }
    
    private func extractPublicKey(from certificateData: Data) -> SecKey? {
        // Create certificate from DER data
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            return nil
        }
        
        // Extract public key from certificate
        return SecCertificateCopyKey(certificate)
    }
    
    private func rsaDecrypt(checkCode: Data, publicKey: SecKey) -> Data? {
        // RSA decryption with public key (actually verification operation)
        // In RSA signature verification, we "decrypt" with the public key
        
        var error: Unmanaged<CFError>?
        
        // For signature verification, we use SecKeyVerifySignature or SecKeyCreateDecryptedData
        // Since we need the decrypted data (not just verification), we use the transform API
        
        // Create transform
        guard let transform = SecKeyCreateDecryptedData(
            publicKey,
            .rsaEncryptionRaw, // Raw RSA operation without padding
            checkCode as CFData,
            &error
        ) else {
            print("RSA decryption error: \(error?.takeRetainedValue().localizedDescription ?? "Unknown")")
            return nil
        }
        
        return transform as Data
    }
    
    private func extractHashFromPKCS1(_ data: Data) -> Data? {
        // PKCS#1 v1.5 signature format:
        // 0x00 || 0x01 || PS || 0x00 || DigestInfo
        // Where PS is padding string of 0xFF bytes
        // DigestInfo contains the hash value
        
        guard data.count >= Constants.hashLength + 11 else {
            return nil
        }
        
        // Check for proper PKCS#1 v1.5 padding structure
        guard data[0] == 0x00 && data[1] == 0x01 else {
            return nil
        }
        
        // Find the 0x00 separator after padding
        var separatorIndex = -1
        for i in 2..<data.count {
            if data[i] == 0x00 {
                separatorIndex = i
                break
            } else if data[i] != 0xFF {
                // Invalid padding byte
                return nil
            }
        }
        
        guard separatorIndex > 0 && separatorIndex < data.count - Constants.hashLength else {
            return nil
        }
        
        // The hash is in the last 32 bytes (SHA-256)
        // DigestInfo for SHA-256 includes algorithm identifier before the hash
        // We extract the last 32 bytes which should be the actual hash value
        return data.suffix(Constants.hashLength)
    }
    
    private func extractCertificateDetails(from certificateData: Data) -> (subject: String?, issuer: String?, notBefore: Date?, notAfter: Date?) {
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            return (nil, nil, nil, nil)
        }
        
        // Get certificate summary (subject)
        let subject = SecCertificateCopySubjectSummary(certificate) as String?
        
        // For more detailed parsing, we would need to parse the X.509 structure
        // For now, return basic info
        return (subject, nil, nil, nil)
    }
    
    private func parseTLV(data: Data, tag: UInt8) -> Data? {
        // Parse TLV (Tag-Length-Value) structure following BER-TLV encoding rules
        // as specified in 在留カード等仕様書 for data reading procedure (3.5 データの読み出し手順)
        //
        // TLV Structure Format:
        // [Tag: 1 byte][Length: 1-4 bytes][Value: variable length]
        //
        // Length Encoding (BER-TLV):
        // - Short form (≤ 127): Length byte directly contains the value (0x00-0x7F)
        // - Long form (> 127): 
        //   - First byte: 0x81 = next 1 byte contains length (up to 255)
        //   - First byte: 0x82 = next 2 bytes contain length (up to 65535)
        //   - Examples: 0x82 1B 58 = 7000 bytes, 0x82 0B B8 = 3000 bytes
        //
        // This parser handles the APDU response data structure from residence card IC chip
        var offset = 0
        
        while offset < data.count {
            guard offset + 2 <= data.count else { break }
            
            let currentTag = data[offset]
            var length = 0
            var lengthFieldSize = 1
            
            let lengthByte = data[offset + 1]
            
            // Parse length field according to BER-TLV encoding
            if lengthByte <= 0x7F {
                // Short form: length value fits in 7 bits
                length = Int(lengthByte)
                lengthFieldSize = 1
            } else if lengthByte == 0x81 {
                // Long form: next 1 byte contains the length
                guard offset + 3 <= data.count else { break }
                length = Int(data[offset + 2])
                lengthFieldSize = 2
            } else if lengthByte == 0x82 {
                // Long form: next 2 bytes contain the length (most common for image data)
                // Example: 0x82 1B 58 = 0x1B58 = 7000 bytes
                guard offset + 4 <= data.count else { break }
                length = Int(data[offset + 2]) * 256 + Int(data[offset + 3])
                lengthFieldSize = 3
            } else {
                // Unsupported length encoding
                break
            }
            
            let valueStart = offset + 1 + lengthFieldSize
            guard valueStart + length <= data.count else { break }
            
            // Return the value if we found the target tag
            if currentTag == tag {
                return data.subdata(in: valueStart..<(valueStart + length))
            }
            
            // Move to next TLV element
            offset = valueStart + length
        }
        
        return nil
    }
}

// MARK: - Data Extension for Hex String
extension Data {
    var hexString: String {
        return map { String(format: "%02X", $0) }.joined()
    }
}