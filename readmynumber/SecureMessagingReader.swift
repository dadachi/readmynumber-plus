//
//  SecureMessagingReader.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation
import CoreNFC
import CryptoKit

/// Maximum APDU response length for NFC card operations
let maxAPDUResponseLength: Int = 1693

/// Handles Secure Messaging READ BINARY operations for residence cards
class SecureMessagingReader {

    private let commandExecutor: NFCCommandExecutor
    private let sessionKey: Data?
    private let tdesCryptography: TDESCryptography

    /// Initialize with an NFC command executor and optional session key
    /// - Parameters:
    ///   - commandExecutor: The executor for sending NFC commands
    ///   - sessionKey: The session key for decryption (if available)
    ///   - tdesCryptography: The TDES cryptography instance for decryption
    init(commandExecutor: NFCCommandExecutor, sessionKey: Data? = nil, tdesCryptography: TDESCryptography = TDESCryptography()) {
        self.commandExecutor = commandExecutor
        self.sessionKey = sessionKey
        self.tdesCryptography = tdesCryptography
    }
    
    /// Read binary data in chunks with Secure Messaging
    /// - Parameters:
    ///   - p1: Parameter 1 (offset high byte) 
    ///   - p2: Parameter 2 (offset low byte)
    /// - Returns: All decrypted data combined
    func readBinaryWithSM(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
      let leData = Data([0x96, 0x02] + withUnsafeBytes(of: UInt16(maxAPDUResponseLength).bigEndian, Array.init))

        let command = NFCISO7816APDU(
            instructionClass: 0x08, // SM command class
            instructionCode: 0xB0,  // READ BINARY
            p1Parameter: p1,
            p2Parameter: p2,
            data: leData,
            expectedResponseLength: 65536
        )
        
      let (encryptedData, sw1, sw2) = try await commandExecutor.sendCommand(apdu: command)
      try checkStatusWord(sw1: sw1, sw2: sw2)

      if encryptedData.count >= maxAPDUResponseLength - 100 { // Allow for some overhead
        // Response might be truncated, try chunked reading
        return try await readBinaryChunkedWithSM(p1: p1, p2: p2)
      }

      let decryptedData = try decryptSMResponse(encryptedData: encryptedData)
      return decryptedData
    }

  // バイナリ読み出し（SMあり、チャンク対応）
  internal func readBinaryChunkedWithSM(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
    // First, read a small chunk to determine the actual data size from TLV structure
    let initialChunkSize = min(maxAPDUResponseLength, 512)
    let leData = Data([0x96, 0x02] + withUnsafeBytes(of: UInt16(initialChunkSize).bigEndian, Array.init))

    let initialCommand = NFCISO7816APDU(
      instructionClass: 0x08,
      instructionCode: 0xB0,  // READ BINARY
      p1Parameter: p1,
      p2Parameter: p2,
      data: leData,
      expectedResponseLength: 65536
    )

    let (initialResponse, sw1, sw2) = try await commandExecutor.sendCommand(apdu: initialCommand)
    try checkStatusWord(sw1: sw1, sw2: sw2)

    // Parse TLV to determine total data size
    guard initialResponse.count >= 3,
          initialResponse[0] == 0x86 else {
      throw CardReaderError.invalidResponse
    }

    let (totalLength, tlvHeaderSize) = try parseBERLength(data: initialResponse, offset: 1)
    let totalTLVSize = tlvHeaderSize + totalLength

    // If the total data fits in what we already read, return it
    if totalTLVSize <= initialResponse.count {
      return try decryptSMResponse(encryptedData: initialResponse)
    }

    // Calculate how many additional chunks we need
    var allData = initialResponse
    var currentOffset = initialResponse.count

    while currentOffset < totalTLVSize {
      let remainingBytes = totalTLVSize - currentOffset
      let chunkSize = min(remainingBytes, maxAPDUResponseLength)

      // Calculate P1, P2 for offset-based reading
      // Offset encoding: P1 = (offset >> 8) & 0x7F, P2 = offset & 0xFF
      let offsetP1 = UInt8((currentOffset >> 8) & 0x7F)
      let offsetP2 = UInt8(currentOffset & 0xFF)

      let chunkLeData = Data([0x96, 0x02] + withUnsafeBytes(of: UInt16(chunkSize).bigEndian, Array.init))

      let chunkCommand = NFCISO7816APDU(
        instructionClass: 0x08,
        instructionCode: 0xB0,  // READ BINARY
        p1Parameter: offsetP1,
        p2Parameter: offsetP2,
        data: chunkLeData,
        expectedResponseLength: chunkSize
      )

      let (chunkData, chunkSW1, chunkSW2) = try await commandExecutor.sendCommand(apdu: chunkCommand)
      try checkStatusWord(sw1: chunkSW1, sw2: chunkSW2)

      allData.append(chunkData)
      currentOffset += chunkData.count

      // Safety check to prevent infinite loops
      if chunkData.isEmpty {
        break
      }
    }

    // Decrypt the complete reassembled data
    return try decryptSMResponse(encryptedData: allData)
  }

    // MARK: - Private Methods
    
    /// Check status words for errors
    private func checkStatusWord(sw1: UInt8, sw2: UInt8) throws {
        guard sw1 == 0x90 && sw2 == 0x00 else {
            throw CardReaderError.cardError(sw1: sw1, sw2: sw2)
        }
    }
    
    /// Decrypt Secure Messaging response
    /// 
    /// セキュアメッセージング応答の復号化処理
    /// TLV形式の暗号化データを復号化し、パディングを除去します。
    /// 
    /// - Parameter encryptedData: TLV形式の暗号化データ
    /// - Returns: 復号化されたデータ（パディング除去済み）
    /// - Throws: CardReaderError セッションキーがない、データ形式が不正、復号化失敗時
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
    
    /// Parse BER/DER length encoding
    /// 
    /// BER/DER形式の長さフィールドを解析します。
    /// 
    /// - Parameters:
    ///   - data: 解析対象のデータ
    ///   - offset: 長さフィールドの開始位置
    /// - Returns: (解析された長さ, 次のフィールドの開始位置)
    /// - Throws: CardReaderError データが不正な場合
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
    
    /// Remove padding from decrypted data
    /// 
    /// 復号化されたデータからパディングを除去します。
    /// ISO/IEC 7816-4形式（0x80）とPKCS#7形式の両方に対応。
    /// 
    /// - Parameter data: パディング付きデータ
    /// - Returns: パディング除去後のデータ
    /// - Throws: CardReaderError パディングが不正な場合
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
    
    /// Remove PKCS#7 padding from data
    /// 
    /// PKCS#7形式のパディングを除去します。
    /// 
    /// - Parameter data: PKCS#7パディング付きデータ
    /// - Returns: パディング除去後のデータ
    /// - Throws: CardReaderError パディングが不正な場合
    internal func removePKCS7Padding(data: Data) throws -> Data {
        guard !data.isEmpty else {
            throw CardReaderError.invalidResponse
        }
        
        // PKCS#7 パディング除去
        let paddingLength = Int(data.last!)
        
        // パディング長が有効範囲内かチェック
        guard paddingLength > 0 && paddingLength <= 8 && paddingLength <= data.count else {
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
}
