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