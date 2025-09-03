//
//  NFCMocks.swift
//  readmynumberTests
//
//  Mock objects for NFC testing
//

import Foundation
import CoreNFC
@testable import readmynumber

// MARK: - Test Helpers

// Simple mock for testing without actual NFC protocols
class MockNFCCardTag {
    var shouldSucceed = true
    var mockResponses: [Data: (Data, UInt8, UInt8)] = [:] // Command -> (response, sw1, sw2)
    var commandHistory: [Data] = []
    
    func sendCommand(data: Data) -> (Data, UInt8, UInt8) {
        commandHistory.append(data)
        
        // Return mock response if configured
        if let response = mockResponses[data] {
            return response
        }
        
        // Default response
        if shouldSucceed {
            return (Data(), 0x90, 0x00) // Success
        } else {
            return (Data(), 0x6A, 0x82) // File not found
        }
    }
}

// Mock for testing NFC operations without actual NFCISO7816Tag protocol
class MockNFCISO7816Tag {
    var shouldSucceed = true
    var errorSW1: UInt8 = 0x6A
    var errorSW2: UInt8 = 0x82
    var commandHistory: [MockAPDUCommand] = []
    var lastCommand: MockAPDUCommand?
    var mockResponses: [Data: (Data, UInt8, UInt8)] = [:]
    
    func sendCommand(apdu: MockAPDUCommand) async throws -> (Data, UInt8, UInt8) {
        commandHistory.append(apdu)
        lastCommand = apdu
        
        // Check for mock response based on command data
        if let commandData = apdu.data,
           let response = mockResponses[commandData] {
            return response
        }
        
        // Special handling for READ BINARY commands
        if apdu.instructionCode == 0xB0 { // READ BINARY
            if shouldSucceed {
                let offset = (UInt16(apdu.p1Parameter) << 8) | UInt16(apdu.p2Parameter)
                
                if apdu.instructionClass == 0x08 { // Secure Messaging READ BINARY
                    // Return encrypted SM response - create mock TLV structure
                    let plainData = Data(repeating: UInt8(offset & 0xFF), count: 100) // 100 bytes of plain data
                    let encryptedResponse = MockTestUtils.createMockEncryptedSMResponse(plaintext: plainData)
                    return (encryptedResponse, 0x90, 0x00)
                } else {
                    // Plain READ BINARY
                    let mockData = Data(repeating: UInt8(offset & 0xFF), count: 256) // 256 bytes of data
                    return (mockData, 0x90, 0x00)
                }
            } else {
                throw CardReaderError.cardError(sw1: errorSW1, sw2: errorSW2)
            }
        }
        
        // Return success or error based on configuration
        if shouldSucceed {
            return (Data(), 0x90, 0x00)
        } else {
            // Simulate CardReaderError.cardError
            throw CardReaderError.cardError(sw1: errorSW1, sw2: errorSW2)
        }
    }
}

// Mock APDU command structure for testing
struct MockAPDUCommand {
    let instructionClass: UInt8
    let instructionCode: UInt8
    let p1Parameter: UInt8
    let p2Parameter: UInt8
    let data: Data?
    let expectedResponseLength: Int
    
    init(instructionClass: UInt8, instructionCode: UInt8, p1Parameter: UInt8, p2Parameter: UInt8, data: Data?, expectedResponseLength: Int) {
        self.instructionClass = instructionClass
        self.instructionCode = instructionCode
        self.p1Parameter = p1Parameter
        self.p2Parameter = p2Parameter
        self.data = data
        self.expectedResponseLength = expectedResponseLength
    }
}

// Test-specific extension to ResidenceCardReader for testing internal methods
extension ResidenceCardReader {
    
    // Test helper for NFC delegate methods
    func testTagReaderSessionDidBecomeActive() {
        // Just test that the method exists and doesn't crash
        // The actual method is empty
    }
    
    func testTagReaderSessionDidInvalidateWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.isReadingInProgress = false
        }
        readCompletion?(.failure(error))
    }
    
    // Test helper for validation methods
    func testCardValidationMethods() {
        // These methods are now internal and can be tested directly
        // This helper is for completeness
    }
    
    // Test helper for selectMF that works with mock objects
    func testSelectMF(mockTag: MockNFCISO7816Tag) async throws {
        let command = MockAPDUCommand(
            instructionClass: 0x00,
            instructionCode: 0xA4,  // SELECT FILE
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data([0x3F, 0x00]),  // MF identifier
            expectedResponseLength: -1
        )
        
        let (_, sw1, sw2) = try await mockTag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
    }
    
    // Test helper for selectDF that works with mock objects
    func testSelectDF(mockTag: MockNFCISO7816Tag, aid: Data) async throws {
        let command = MockAPDUCommand(
            instructionClass: 0x00,
            instructionCode: 0xA4,  // SELECT FILE
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: aid,
            expectedResponseLength: -1
        )
        
        let (_, sw1, sw2) = try await mockTag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
    }
    
    // Test helper for readBinaryPlain that works with mock objects
    func testReadBinaryPlain(mockTag: MockNFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let command = MockAPDUCommand(
            instructionClass: 0x00,
            instructionCode: 0xB0,  // READ BINARY
            p1Parameter: p1,
            p2Parameter: p2,
            data: Data(),
            expectedResponseLength: 65536
        )
        
        let (data, sw1, sw2) = try await mockTag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        return data
    }
    
    // Test helper for readBinaryWithSM that works with mock objects
    func testReadBinaryWithSM(mockTag: MockNFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        let leData = Data([0x96, 0x02, 0x00, 0x00])
        
        let command = MockAPDUCommand(
            instructionClass: 0x08, // SM command class
            instructionCode: 0xB0,  // READ BINARY
            p1Parameter: p1,
            p2Parameter: p2,
            data: leData,
            expectedResponseLength: 65536
        )
        
        let (encryptedData, sw1, sw2) = try await mockTag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        // Decrypt the SM response
        return try decryptSMResponse(encryptedData: encryptedData)
    }
    
    // Test wrapper for chunked reading that simulates the internal chunked logic
    func testReadBinaryChunkedPlainWrapper(mockTag: MockNFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        // Simulate the chunked reading logic with mock objects
        var allData = Data()
        var currentOffset: UInt16 = (UInt16(p1) << 8) | UInt16(p2)
        var isFirstRead = true
        let maxChunkSize = 1694 // ResidenceCardReader.maxAPDUResponseLength
        
        while true {
            let chunkSize = isFirstRead ? min(maxChunkSize, 512) : maxChunkSize
            
            let command = MockAPDUCommand(
                instructionClass: 0x00,
                instructionCode: 0xB0,
                p1Parameter: UInt8((currentOffset >> 8) & 0xFF),
                p2Parameter: UInt8(currentOffset & 0xFF),
                data: Data(),
                expectedResponseLength: chunkSize
            )
            
            let (chunkData, sw1, sw2) = try await mockTag.sendCommand(apdu: command)
            try checkStatusWord(sw1: sw1, sw2: sw2)
            
            if isFirstRead {
                allData = chunkData
                isFirstRead = false
                
                // Check if we need more data by parsing TLV structure (simple simulation)
                if chunkData.count >= 3 {
                    let tag = chunkData[0]
                    if chunkData[1] == 0x82 && chunkData.count >= 4 { // Long form BER
                        let lengthBytes = Int(chunkData[2]) * 256 + Int(chunkData[3])
                        let totalExpected = 1 + 3 + lengthBytes // tag + length bytes + data
                        
                        if totalExpected > chunkData.count {
                            currentOffset += UInt16(chunkData.count)
                            continue // Need more data
                        }
                    } else if chunkData[1] <= 0x7F { // Short form BER
                        let totalExpected = 1 + 1 + Int(chunkData[1])
                        
                        if totalExpected > chunkData.count {
                            currentOffset += UInt16(chunkData.count)
                            continue // Need more data
                        }
                    }
                }
                break // We have all the data
            } else {
                allData.append(chunkData)
                currentOffset += UInt16(chunkData.count)
                
                if chunkData.isEmpty || chunkData.count < chunkSize {
                    break // No more data
                }
            }
        }
        
        return allData
    }
    
    // Test wrapper for SM chunked reading
    func testReadBinaryChunkedWithSMWrapper(mockTag: MockNFCISO7816Tag, p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        // For SM, we simulate reading encrypted data and decrypting it
        let leData = Data([0x96, 0x02, 0x00, 0x00])
        
        let command = MockAPDUCommand(
            instructionClass: 0x08,
            instructionCode: 0xB0,
            p1Parameter: p1,
            p2Parameter: p2,
            data: leData,
            expectedResponseLength: 65536
        )
        
        let (encryptedData, sw1, sw2) = try await mockTag.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        // Simulate SM decryption
        return try decryptSMResponse(encryptedData: encryptedData)
    }
}

// MARK: - Test Utilities

struct MockTestUtils {
    static func createMockEncryptedSMResponse(plaintext: Data) -> Data {
        // Create a mock secure messaging response
        var response = Data()
        response.append(0x86) // Tag for encrypted data
        response.append(UInt8(plaintext.count + 1)) // Length
        response.append(0x01) // Padding indicator
        response.append(plaintext)
        return response
    }
}

// MARK: - Test Constants

struct TestConstants {
    static let validCardNumbers = [
        "ABC123456789", // Basic format
        "XYZ987654321", // Different letters
        "DEF135792468"  // Mixed pattern
    ]
    
    static let invalidCardNumbers = [
        "ABC12345678",   // Too short
        "ABC1234567890", // Too long
        "abc123456789",  // Lowercase
        "ABC12345678@",  // Special character
        "ABC123456789",  // Sequential (might be considered invalid)
        "ABC000000000"   // All zeros
    ]
    
    static let testKeys = [
        Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
              0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]),
        Data(repeating: 0xAA, count: 16),
        Data(repeating: 0x55, count: 16)
    ]
    
    static let df1AID = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x02, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let df2AID = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x03, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let df3AID = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x04, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
}