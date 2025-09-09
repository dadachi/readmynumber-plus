//
//  SecureMessagingReader.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation
import CoreNFC
import CryptoKit

/// Handles Secure Messaging READ BINARY operations for residence cards
class SecureMessagingReader {
    
    private let commandExecutor: NFCCommandExecutor
    private let sessionKey: Data?
    
    /// Initialize with an NFC command executor and optional session key
    /// - Parameters:
    ///   - commandExecutor: The executor for sending NFC commands
    ///   - sessionKey: The session key for decryption (if available)
    init(commandExecutor: NFCCommandExecutor, sessionKey: Data? = nil) {
        self.commandExecutor = commandExecutor
        self.sessionKey = sessionKey
    }
    
    /// Read binary data with Secure Messaging
    /// - Parameters:
    ///   - p1: Parameter 1 (offset high byte)
    ///   - p2: Parameter 2 (offset low byte)
    /// - Returns: Decrypted data
    func readBinaryWithSM(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let leData = Data([0x96, 0x02, 0x00, 0x00])
        
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
        
        // Decrypt the SM response
        return try decryptSMResponse(encryptedData: encryptedData)
    }
    
    /// Read binary data in chunks with Secure Messaging
    /// - Parameters:
    ///   - p1: Parameter 1 (offset high byte) 
    ///   - p2: Parameter 2 (offset low byte)
    ///   - maxChunkSize: Maximum bytes per chunk (default 100 for SM)
    /// - Returns: All decrypted data combined
    func readBinaryChunkedWithSM(p1: UInt8, p2: UInt8 = 0x00, maxChunkSize: Int = 100) async throws -> Data {
        let leData = Data([0x96, 0x02, 0x00, 0x00])
        
        // Read initial data
        let initialCommand = NFCISO7816APDU(
            instructionClass: 0x08, // SM command class
            instructionCode: 0xB0,  // READ BINARY
            p1Parameter: p1,
            p2Parameter: p2,
            data: leData,
            expectedResponseLength: 65536
        )
        
        let (initialResponse, sw1, sw2) = try await commandExecutor.sendCommand(apdu: initialCommand)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        // Decrypt initial response
        let decryptedData = try decryptSMResponse(encryptedData: initialResponse)
        
        // Check if we got the full expected size
        guard decryptedData.count >= 4 else {
            throw CardReaderError.invalidResponse
        }
        
        // Parse TLV to get expected data size
        let dataSize = Int(decryptedData[2]) << 8 | Int(decryptedData[3])
        
        // If initial response contains all data, return it
        if decryptedData.count >= dataSize + 4 {
            return decryptedData
        }
        
        // Need to read more chunks
        var allData = decryptedData
        var currentOffset = decryptedData.count
        
        while currentOffset < dataSize + 4 {
            let remainingBytes = (dataSize + 4) - currentOffset
            let chunkSize = min(remainingBytes, maxChunkSize)
            
            // Calculate offset parameters
            let offsetHigh = UInt8((currentOffset >> 8) & 0xFF)
            let offsetLow = UInt8(currentOffset & 0xFF)
            
            let chunkCommand = NFCISO7816APDU(
                instructionClass: 0x08, // SM command class
                instructionCode: 0xB0,  // READ BINARY
                p1Parameter: offsetHigh,
                p2Parameter: offsetLow,
                data: leData,
                expectedResponseLength: 65536
            )
            
            let (chunkData, chunkSW1, chunkSW2) = try await commandExecutor.sendCommand(apdu: chunkCommand)
            try checkStatusWord(sw1: chunkSW1, sw2: chunkSW2)
            
            let decryptedChunk = try decryptSMResponse(encryptedData: chunkData)
            allData.append(decryptedChunk)
            currentOffset += decryptedChunk.count
        }
        
        return allData
    }
    
    // MARK: - Private Methods
    
    /// Check status words for errors
    private func checkStatusWord(sw1: UInt8, sw2: UInt8) throws {
        guard sw1 == 0x90 && sw2 == 0x00 else {
            throw CardReaderError.cardError(sw1: sw1, sw2: sw2)
        }
    }
    
    /// Decrypt Secure Messaging response
    private func decryptSMResponse(encryptedData: Data) throws -> Data {
        // Check if we have encrypted data (tag 0x86)
        guard encryptedData.count > 2,
              encryptedData[0] == 0x86 else {
            throw CardReaderError.invalidResponse
        }
        
        // Get length
        let length = Int(encryptedData[1])
        guard encryptedData.count >= 2 + length else {
            throw CardReaderError.invalidResponse
        }
        
        // Extract encrypted portion (skip tag and length)
        let encryptedPortion = encryptedData[2..<(2 + length)]
        
        // If no session key is available, return the encrypted portion as-is
        // (for testing or when decryption is handled elsewhere)
        guard let sessionKey = sessionKey else {
            return Data(encryptedPortion)
        }
        
        // Decrypt using session key (simplified - actual implementation would use proper crypto)
        // This is a placeholder for the actual decryption logic
        return try performDecryption(encryptedData: Data(encryptedPortion), key: sessionKey)
    }
    
    /// Perform actual decryption (placeholder - implement actual crypto as needed)
    private func performDecryption(encryptedData: Data, key: Data) throws -> Data {
        // For now, just return the data minus the first padding byte if present
        if encryptedData.count > 1 && encryptedData[0] == 0x01 {
            return encryptedData[1...]
        }
        return encryptedData
    }
}

// MARK: - Mock for Testing

/// Mock Secure Messaging Reader for testing
class MockSecureMessagingReader: SecureMessagingReader {
    var mockDecryptedData: Data?
    var shouldThrowError = false
    var errorToThrow: Error = CardReaderError.invalidResponse
    
    override func readBinaryWithSM(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        if shouldThrowError {
            throw errorToThrow
        }
        
        if let mockData = mockDecryptedData {
            return mockData
        }
        
        // Return default mock data based on offset
        let offset = (UInt16(p1) << 8) | UInt16(p2)
        return Data(repeating: UInt8(offset & 0xFF), count: 100)
    }
    
    override func readBinaryChunkedWithSM(p1: UInt8, p2: UInt8 = 0x00, maxChunkSize: Int = 100) async throws -> Data {
        if shouldThrowError {
            throw errorToThrow
        }
        
        if let mockData = mockDecryptedData {
            return mockData
        }
        
        // Create mock TLV data
        var tlvData = Data()
        tlvData.append(0x5F) // Tag byte 1
        tlvData.append(0x01) // Tag byte 2
        tlvData.append(0x00) // Length high
        tlvData.append(0x64) // Length low (100 bytes)
        tlvData.append(Data(repeating: 0xAA, count: 100)) // Mock data
        return tlvData
    }
}