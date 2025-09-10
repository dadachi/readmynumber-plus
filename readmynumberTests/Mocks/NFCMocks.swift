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
    
    static func createRealEncryptedSMResponse(plaintext: Data, sessionKey: Data) throws -> Data {
        // Create real encrypted secure messaging response using TDES
        let realTDES = TDESCryptography()
        let encryptedData = try realTDES.performTDES(data: plaintext, key: sessionKey, encrypt: true)
        
        var response = Data()
        response.append(0x86) // Tag for encrypted data
        response.append(UInt8(encryptedData.count + 1)) // Length including 0x01 prefix
        response.append(0x01) // Padding indicator
        response.append(encryptedData)
        return response
    }
    
    static func createChunkedTestData(plaintext: Data, sessionKey: Data, firstChunkSize: Int) throws -> (firstChunk: Data, secondChunk: Data, offsetP1: UInt8, offsetP2: UInt8) {
        // Create real encrypted data
        let realTDES = TDESCryptography()
        let encryptedData = try realTDES.performTDES(data: plaintext, key: sessionKey, encrypt: true)
        
        // Create TLV structure indicating large total size
        let totalSize = encryptedData.count + 1 // +1 for the 0x01 prefix
        let tlvHeader = Data([0x86, 0x82, UInt8((totalSize >> 8) & 0xFF), UInt8(totalSize & 0xFF)])
        
        // Calculate how much encrypted data can fit in the first chunk
        let availableSpaceInFirstChunk = firstChunkSize - tlvHeader.count - 1 // -1 for the 0x01 prefix
        
        // Ensure we don't try to read more data than we have
        let firstPartSize = min(availableSpaceInFirstChunk, encryptedData.count)
        guard firstPartSize > 0 else {
            throw CardReaderError.invalidResponse
        }
        
        // First chunk: TLV header + prefix + partial encrypted data
        let firstPartEncrypted = encryptedData.prefix(firstPartSize)
        let firstChunk = tlvHeader + Data([0x01]) + firstPartEncrypted
        
        // Second chunk: remaining encrypted data (if any)
        let secondChunk = firstPartSize < encryptedData.count ? 
            encryptedData.suffix(from: firstPartSize) : Data()
        
        // Calculate offset parameters for second chunk
        let offsetP1 = UInt8((firstChunkSize >> 8) & 0x7F)
        let offsetP2 = UInt8(firstChunkSize & 0xFF)
        
        return (firstChunk, secondChunk, offsetP1, offsetP2)
    }
    
    static func createSingleChunkTestData(plaintext: Data, sessionKey: Data) throws -> Data {
        // Create small TLV data that fits in a single chunk
        let realTDES = TDESCryptography()
        let encryptedData = try realTDES.performTDES(data: plaintext, key: sessionKey, encrypt: true)
        
        // Create proper TLV structure: Tag (0x86) + Length + Value (0x01 + encrypted data)
        let valueData = Data([0x01]) + encryptedData // 0x01 prefix + encrypted data
        let valueLength = valueData.count
        
        var response = Data()
        response.append(0x86) // Tag for encrypted data
        
        // Use appropriate length encoding
        if valueLength <= 0x7F {
            // Short form length encoding
            response.append(UInt8(valueLength))
        } else if valueLength <= 0xFF {
            // Long form length encoding with 1 byte
            response.append(0x81)
            response.append(UInt8(valueLength))
        } else {
            // Long form length encoding with 2 bytes
            response.append(0x82)
            response.append(UInt8((valueLength >> 8) & 0xFF))
            response.append(UInt8(valueLength & 0xFF))
        }
        
        response.append(valueData)
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
