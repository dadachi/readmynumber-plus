import Foundation
import CryptoKit
import Security

// MARK: - Residence Card Signature Verifier
// Implementation of section 3.4.3.1 (署名検証方法) from 在留カード等仕様書
class ResidenceCardSignatureVerifier {
    
    // MARK: - Types
    struct VerificationResult {
        let isValid: Bool
        let error: VerificationError?
        let details: VerificationDetails?
    }
    
    struct VerificationDetails {
        let checkCodeHash: String?
        let calculatedHash: String?
        let certificateSubject: String?
        let certificateIssuer: String?
        let certificateNotBefore: Date?
        let certificateNotAfter: Date?
    }
    
    enum VerificationError: LocalizedError {
        case missingCheckCode
        case missingCertificate
        case invalidCertificate
        case invalidCheckCodeLength
        case publicKeyExtractionFailed
        case rsaDecryptionFailed
        case hashMismatch
        case invalidPaddingFormat
        case missingImageData
        
        var errorDescription: String? {
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
    
    // MARK: - Constants
    private enum Constants {
        static let checkCodeTag: UInt8 = 0xDA
        static let certificateTag: UInt8 = 0xDB
        static let checkCodeLength = 256 // 2048 bits
        static let hashLength = 32 // SHA-256 output
        static let rsaKeySize = 2048
    }
    
    // MARK: - Public Methods
    
    /// Verify the signature according to section 3.4.3.1 of 在留カード等仕様書
    /// - Parameters:
    ///   - signatureData: The signature data from DF3/EF01
    ///   - frontImageData: The front image data from DF1/EF01 (券面イメージ)
    ///   - faceImageData: The face image data from DF1/EF02 (顔画像)
    /// - Returns: Verification result with details
    func verifySignature(
        signatureData: Data,
        frontImageData: Data,
        faceImageData: Data
    ) -> VerificationResult {
        
        // Step 1: Extract check code and certificate from signature data
        guard let checkCode = extractCheckCode(from: signatureData) else {
            return VerificationResult(isValid: false, error: .missingCheckCode, details: nil)
        }
        
        guard checkCode.count == Constants.checkCodeLength else {
            return VerificationResult(isValid: false, error: .invalidCheckCodeLength, details: nil)
        }
        
        guard let certificateData = extractCertificate(from: signatureData) else {
            return VerificationResult(isValid: false, error: .missingCertificate, details: nil)
        }
        
        // Step 2: Extract public key from X.509 certificate
        guard let publicKey = extractPublicKey(from: certificateData) else {
            return VerificationResult(isValid: false, error: .publicKeyExtractionFailed, details: nil)
        }
        
        // Step 3: Decrypt check code with RSA public key (公開鍵でチェックコードを復号)
        guard let decryptedData = rsaDecrypt(checkCode: checkCode, publicKey: publicKey) else {
            return VerificationResult(isValid: false, error: .rsaDecryptionFailed, details: nil)
        }
        
        // Step 4: Extract hash from decrypted data (remove PKCS#1 v1.5 padding)
        guard let extractedHash = extractHashFromPKCS1(decryptedData) else {
            return VerificationResult(isValid: false, error: .invalidPaddingFormat, details: nil)
        }
        
        // Step 5: Extract actual image data from TLV structure
        guard let frontImageValue = extractImageValue(from: frontImageData),
              let faceImageValue = extractImageValue(from: faceImageData) else {
            return VerificationResult(isValid: false, error: .missingImageData, details: nil)
        }
        
        // Step 6: Concatenate image data (署名対象データを連結)
        let concatenatedData = frontImageValue + faceImageValue
        
        // Step 7: Calculate SHA-256 hash of concatenated data
        let calculatedHash = SHA256.hash(data: concatenatedData)
        let calculatedHashData = Data(calculatedHash)
        
        // Step 8: Compare hashes
        let isValid = extractedHash == calculatedHashData
        
        // Get certificate details for display
        let details = extractCertificateDetails(from: certificateData)
        
        var verificationDetails = VerificationDetails(
            checkCodeHash: extractedHash.hexString,
            calculatedHash: calculatedHashData.hexString,
            certificateSubject: details.subject,
            certificateIssuer: details.issuer,
            certificateNotBefore: details.notBefore,
            certificateNotAfter: details.notAfter
        )
        
        return VerificationResult(
            isValid: isValid,
            error: isValid ? nil : .hashMismatch,
            details: verificationDetails
        )
    }
    
    // MARK: - Private Methods
    
    private func extractCheckCode(from signatureData: Data) -> Data? {
        return parseTLV(data: signatureData, tag: Constants.checkCodeTag)
    }
    
    private func extractCertificate(from signatureData: Data) -> Data? {
        return parseTLV(data: signatureData, tag: Constants.certificateTag)
    }
    
    private func extractImageValue(from imageData: Data) -> Data? {
        // Extract the actual image data from TLV structure
        // Front image has tag 0xD0, face image has tag 0xD1
        if let value = parseTLV(data: imageData, tag: 0xD0) {
            return value
        } else if let value = parseTLV(data: imageData, tag: 0xD1) {
            return value
        }
        // If not in TLV format, return the whole data
        return imageData.isEmpty ? nil : imageData
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
        var offset = 0
        
        while offset < data.count {
            guard offset + 2 <= data.count else { break }
            
            let currentTag = data[offset]
            var length = 0
            var lengthFieldSize = 1
            
            let lengthByte = data[offset + 1]
            
            if lengthByte <= 0x7F {
                length = Int(lengthByte)
                lengthFieldSize = 1
            } else if lengthByte == 0x81 {
                guard offset + 3 <= data.count else { break }
                length = Int(data[offset + 2])
                lengthFieldSize = 2
            } else if lengthByte == 0x82 {
                guard offset + 4 <= data.count else { break }
                length = Int(data[offset + 2]) * 256 + Int(data[offset + 3])
                lengthFieldSize = 3
            } else {
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

// MARK: - Data Extension for Hex String
private extension Data {
    var hexString: String {
        return map { String(format: "%02X", $0) }.joined()
    }
}