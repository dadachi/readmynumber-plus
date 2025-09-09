//
//  PlainBinaryReader.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation
import CoreNFC

/// Handles plain (non-encrypted) READ BINARY operations
class PlainBinaryReader {
    
    private let commandExecutor: NFCCommandExecutor
    private static let maxAPDUResponseLength: Int = 1694
    
    /// Initialize with an NFC command executor
    /// - Parameter commandExecutor: The executor for sending NFC commands
    init(commandExecutor: NFCCommandExecutor) {
        self.commandExecutor = commandExecutor
    }
    
    /// Read binary data without encryption
    /// - Parameters:
    ///   - p1: Parameter 1 (offset high byte or file identifier)
    ///   - p2: Parameter 2 (offset low byte)
    /// - Returns: Plain binary data
    func readBinaryPlain(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        // Read entire file content with maximum response length
        // All residence card files fit within 1693 bytes, so no chunking needed
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0, // READ BINARY
            p1Parameter: p1,
            p2Parameter: p2,
            data: Data(),
            expectedResponseLength: Self.maxAPDUResponseLength
        )
        
        let (data, sw1, sw2) = try await commandExecutor.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        return data
    }
    
    /// Read binary data in chunks (for large files)
    /// - Parameters:
    ///   - p1: Parameter 1 (file identifier)
    ///   - p2: Parameter 2 (initial offset)
    ///   - maxChunkSize: Maximum bytes per chunk
    /// - Returns: All data combined
    func readBinaryChunked(p1: UInt8, p2: UInt8 = 0x00, maxChunkSize: Int = 256) async throws -> Data {
        var allData = Data()
        var currentOffset: UInt16 = 0
        var isFirstRead = true
        
        while true {
            // Calculate offset parameters
            let offsetP1 = isFirstRead ? p1 : UInt8((currentOffset >> 8) & 0x7F)
            let offsetP2 = isFirstRead ? p2 : UInt8(currentOffset & 0xFF)
            
            let command = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0xB0, // READ BINARY
                p1Parameter: offsetP1,
                p2Parameter: offsetP2,
                data: Data(),
                expectedResponseLength: maxChunkSize
            )
            
            let (chunkData, sw1, sw2) = try await commandExecutor.sendCommand(apdu: command)
            
            // Check for end of file
            if sw1 == 0x62 && sw2 == 0x82 {
                // End of file reached
                break
            }
            
            try checkStatusWord(sw1: sw1, sw2: sw2)
            
            if chunkData.isEmpty {
                break
            }
            
            allData.append(chunkData)
            currentOffset += UInt16(chunkData.count)
            isFirstRead = false
            
            // If we got less than requested, we've reached the end
            if chunkData.count < maxChunkSize {
                break
            }
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
}

// MARK: - Mock for Testing

/// Mock Plain Binary Reader for testing
class MockPlainBinaryReader: PlainBinaryReader {
    var mockData: Data?
    var shouldThrowError = false
    var errorToThrow: Error = CardReaderError.invalidResponse
    
    override func readBinaryPlain(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        if shouldThrowError {
            throw errorToThrow
        }
        
        if let mockData = mockData {
            return mockData
        }
        
        // Return default mock data
        return Data(repeating: 0xFF, count: 256)
    }
    
    override func readBinaryChunked(p1: UInt8, p2: UInt8 = 0x00, maxChunkSize: Int = 256) async throws -> Data {
        if shouldThrowError {
            throw errorToThrow
        }
        
        if let mockData = mockData {
            return mockData
        }
        
        // Return default mock data
        return Data(repeating: 0xAA, count: 512)
    }
}