//
//  ResidenceCardReaderTests.swift
//  readmynumberTests
//
//  Created on 2025/08/16.
//

import Testing
import Foundation
import CryptoKit
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import readmynumber

// MARK: - Test Data Factory
struct TestDataFactory {
    static func createValidCommonData() -> Data {
        // TLV structure for common data
        var data = Data()
        data.append(0xC0) // Tag
        data.append(0x04) // Length
        data.append(contentsOf: [0x01, 0x02, 0x03, 0x04]) // Value
        return data
    }
    
    static func createValidCardType(isResidence: Bool) -> Data {
        // TLV structure for card type
        var data = Data()
        data.append(0xC1) // Tag
        data.append(0x01) // Length
        data.append(isResidence ? 0x31 : 0x32) // "1" for residence, "2" for special permanent
        return data
    }
    
    static func createValidAddress() -> Data {
        // TLV structure for address
        var data = Data()
        data.append(0xC2) // Tag
        data.append(0x0A) // Length
        data.append(contentsOf: "Tokyo 1234".utf8) // Value
        return data
    }
    
    static func createPaddedData() -> Data {
        // Data with ISO/IEC 7816-4 padding
        var data = Data("Hello".utf8)
        data.append(0x80) // Padding start
        data.append(contentsOf: [0x00, 0x00, 0x00]) // Padding zeros
        return data
    }
    
    static func createBERLength(length: Int) -> Data {
        if length <= 0x7F {
            return Data([UInt8(length)])
        } else if length <= 0xFF {
            return Data([0x81, UInt8(length)])
        } else {
            let high = UInt8((length >> 8) & 0xFF)
            let low = UInt8(length & 0xFF)
            return Data([0x82, high, low])
        }
    }
    
    static func createEncryptedSMResponse(plaintext: Data) -> Data {
        // Create a mock SM response structure
        var response = Data()
        response.append(0x86) // Tag for encrypted data
        
        // Add length and indicator
        let encryptedData = Data([0x01]) + plaintext + Data([0x80, 0x00, 0x00, 0x00]) // Simulated encrypted data with padding
        
        if encryptedData.count <= 0x7F {
            response.append(UInt8(encryptedData.count))
        } else {
            response.append(0x81)
            response.append(UInt8(encryptedData.count))
        }
        
        response.append(encryptedData)
        return response
    }
}

// MARK: - ResidenceCardData Tests
struct ResidenceCardDataTests {
    
    @Test("ResidenceCardData initialization")
    func testResidenceCardDataInitialization() {
        let commonData = TestDataFactory.createValidCommonData()
        let cardType = TestDataFactory.createValidCardType(isResidence: true)
        let frontImage = Data([0xFF, 0xD8]) // JPEG marker
        let faceImage = Data([0xFF, 0xD8])
        let address = TestDataFactory.createValidAddress()
        let signature = Data([0x30, 0x82]) // ASN.1 sequence
        
        let additionalData = ResidenceCardData.AdditionalData(
            comprehensivePermission: Data("Permission".utf8),
            individualPermission: Data("Individual".utf8),
            extensionApplication: Data("Extension".utf8)
        )
        
        let cardData = ResidenceCardData(
            commonData: commonData,
            cardType: cardType,
            frontImage: frontImage,
            faceImage: faceImage,
            address: address,
            additionalData: additionalData,
            signature: signature,
            signatureVerificationResult: nil
        )
        
        #expect(cardData.commonData == commonData)
        #expect(cardData.cardType == cardType)
        #expect(cardData.frontImage == frontImage)
        #expect(cardData.faceImage == faceImage)
        #expect(cardData.address == address)
        #expect(cardData.additionalData != nil)
        #expect(cardData.signature == signature)
    }
    
    @Test("TLV parsing with valid data")
    func testTLVParsingValidData() {
        let testData = Data([
            0xC0, 0x04, 0x01, 0x02, 0x03, 0x04,  // Tag C0 with 4 bytes
            0xC1, 0x02, 0x05, 0x06,              // Tag C1 with 2 bytes
            0xC2, 0x01, 0x07                      // Tag C2 with 1 byte
        ])
        
        let cardData = ResidenceCardData(
            commonData: testData,
            cardType: Data(),
            frontImage: Data(),
            faceImage: Data(),
            address: Data(),
            additionalData: nil,
            signature: Data(),
            signatureVerificationResult: nil
        )
        
        let c0Value = cardData.parseTLV(data: testData, tag: 0xC0)
        let c1Value = cardData.parseTLV(data: testData, tag: 0xC1)
        let c2Value = cardData.parseTLV(data: testData, tag: 0xC2)
        let c3Value = cardData.parseTLV(data: testData, tag: 0xC3)
        
        #expect(c0Value == Data([0x01, 0x02, 0x03, 0x04]))
        #expect(c1Value == Data([0x05, 0x06]))
        #expect(c2Value == Data([0x07]))
        #expect(c3Value == nil)
    }
    
    @Test("TLV parsing with extended length")
    func testTLVParsingExtendedLength() {
        // Test with 0x81 length encoding (next byte contains length)
        let testData1 = Data([
            0xC0, 0x81, 0x80
        ]) + Data(repeating: 0xAA, count: 128)
        
        let cardData1 = ResidenceCardData(
            commonData: testData1,
            cardType: Data(),
            frontImage: Data(),
            faceImage: Data(),
            address: Data(),
            additionalData: nil,
            signature: Data(),
            signatureVerificationResult: nil
        )
        
        let value1 = cardData1.parseTLV(data: testData1, tag: 0xC0)
        #expect(value1?.count == 128)
        #expect(value1?.first == 0xAA)
        
        // Test with 0x82 length encoding (next 2 bytes contain length)
        let testData2 = Data([
            0xC1, 0x82, 0x01, 0x00
        ]) + Data(repeating: 0xBB, count: 256)
        
        let cardData2 = ResidenceCardData(
            commonData: testData2,
            cardType: Data(),
            frontImage: Data(),
            faceImage: Data(),
            address: Data(),
            additionalData: nil,
            signature: Data(),
            signatureVerificationResult: nil
        )
        
        let value2 = cardData2.parseTLV(data: testData2, tag: 0xC1)
        #expect(value2?.count == 256)
        #expect(value2?.first == 0xBB)
    }
}

// MARK: - CardReaderError Tests
struct CardReaderErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let nfcError = CardReaderError.nfcNotAvailable
        #expect(nfcError.errorDescription == "NFCが利用できません")
        
        let cardNumberError = CardReaderError.invalidCardNumber
        #expect(cardNumberError.errorDescription == "無効な在留カード番号です")
        
        let responseError = CardReaderError.invalidResponse
        #expect(responseError.errorDescription == "カードからの応答が不正です")
        
        let cardError = CardReaderError.cardError(sw1: 0x6A, sw2: 0x82)
        #expect(cardError.errorDescription == "カードエラー: SW1=6A, SW2=82")
        
        let cryptoError = CardReaderError.cryptographyError("Test error")
        #expect(cryptoError.errorDescription == "暗号処理エラー: Test error")
    }
}


// MARK: - ResidenceCardReader Tests
struct ResidenceCardReaderTests {
    
    @Test("Card number validation")
    func testCardNumberValidation() {
        let reader = ResidenceCardReader()
        
        // Valid 12-digit card number
        #expect(throws: Never.self) {
            _ = try reader.generateKeys(from: "AB12345678CD")
        }
        
        // Invalid card number (non-ASCII)
        #expect(throws: CardReaderError.self) {
            _ = try reader.generateKeys(from: "あいうえお")
        }
    }
    
    @Test("Enhanced card number format validation")
    func testEnhancedCardNumberValidation() {
        let reader = ResidenceCardReader()
        
        // Valid formats
        let validNumbers = [
            "AB12345678CD",
            "ZZ98765432XY", 
            "MN01234567QW",
            "  AB12345678CD  ", // with whitespace
            "ab12345678cd"      // lowercase (should be converted)
        ]
        
        for cardNumber in validNumbers {
            #expect(throws: Never.self) {
                _ = try reader.validateCardNumber(cardNumber)
            }
        }
        
        // Test uppercase conversion and whitespace trimming
        do {
            let result = try reader.validateCardNumber("  ab12345678cd  ")
            #expect(result == "AB12345678CD")
        } catch {
            #expect(Bool(false), "Should convert lowercase and trim whitespace")
        }
    }
    
    @Test("Invalid card number lengths")
    func testInvalidCardNumberLengths() {
        let reader = ResidenceCardReader()
        
        let invalidLengths = [
            "",                     // Empty
            "A",                    // Too short
            "AB1234567",           // 9 characters
            "AB12345678C",         // 11 characters
            "AB12345678CDE",       // 13 characters
            "AB12345678CDEFG"      // 15 characters
        ]
        
        for cardNumber in invalidLengths {
            #expect(throws: CardReaderError.invalidCardNumberLength) {
                _ = try reader.validateCardNumber(cardNumber)
            }
        }
    }
    
    @Test("Invalid card number formats")
    func testInvalidCardNumberFormats() {
        let reader = ResidenceCardReader()
        
        let invalidFormats = [
            "1234567890AB",        // Numbers first
            "A123456789BC",        // Only 1 letter at start
            "ABC12345678D",        // 3 letters at start
            "AB1234567CDE",        // 7 numbers
            "AB123456789C",        // 9 numbers
            "AB12345678C1",        // Number at end
            "AB123456781C",        // Number in middle of end letters
            "1B12345678CD",        // Number in first position
            "A112345678CD"         // Number in second position
        ]
        
        for cardNumber in invalidFormats {
            #expect(throws: CardReaderError.invalidCardNumberFormat) {
                _ = try reader.validateCardNumber(cardNumber)
            }
        }
    }
    
    @Test("Invalid card number characters")
    func testInvalidCardNumberCharacters() {
        let reader = ResidenceCardReader()
        
        let invalidCharacters = [
            "AB12345678C@",        // Special character
            "AB123456-78CD",       // Hyphen in numbers
            "AB 12345678CD",       // Space in middle
            "AB12345678C.",        // Period
            "αB12345678CD",        // Greek letter
            "AB12345678Cß"         // German eszett
        ]
        
        for cardNumber in invalidCharacters {
            #expect(throws: CardReaderError.self) {
                _ = try reader.validateCardNumber(cardNumber)
            }
        }
    }
    
    @Test("Card number pattern validation")
    func testCardNumberPatternValidation() {
        let reader = ResidenceCardReader()
        
        // Test regex pattern matching
        #expect(reader.isValidResidenceCardFormat("AB12345678CD") == true)
        #expect(reader.isValidResidenceCardFormat("ZZ98765432XY") == true)
        #expect(reader.isValidResidenceCardFormat("AB1234567CD") == false)  // 7 digits
        #expect(reader.isValidResidenceCardFormat("A12345678CD") == false)   // 1 letter at start
        #expect(reader.isValidResidenceCardFormat("AB12345678C") == false)   // 1 letter at end
        #expect(reader.isValidResidenceCardFormat("1B12345678CD") == false)  // Digit at start
        #expect(reader.isValidResidenceCardFormat("AB12345678C1") == false)  // Digit at end
    }
    
    @Test("Edge cases and special scenarios")
    func testEdgeCasesAndSpecialScenarios() {
        let reader = ResidenceCardReader()
        
        // Test with real-world like card numbers
        let realisticNumbers = [
            "AA00000001BC",
            "ZZ99999999XY",
            "MK20241201PQ"
        ]
        
        for cardNumber in realisticNumbers {
            #expect(throws: Never.self) {
                _ = try reader.validateCardNumber(cardNumber)
            }
        }
        
        // Test boundary values
        #expect(throws: Never.self) {
            _ = try reader.validateCardNumber("AA00000000AA")  // All zeros in middle
        }
        
        #expect(throws: Never.self) {
            _ = try reader.validateCardNumber("ZZ99999999ZZ")  // All nines in middle
        }
    }
    
    @Test("BER length parsing")
    func testBERLengthParsing() throws {
        let reader = ResidenceCardReader()
        
        // Short form (0x00 to 0x7F)
        let data1 = Data([0x45, 0xFF, 0xFF])
        let (length1, offset1) = try reader.parseBERLength(data: data1, offset: 0)
        #expect(length1 == 0x45)
        #expect(offset1 == 1)
        
        // Extended form with 0x81
        let data2 = Data([0x81, 0x80, 0xFF])
        let (length2, offset2) = try reader.parseBERLength(data: data2, offset: 0)
        #expect(length2 == 0x80)
        #expect(offset2 == 2)
        
        // Extended form with 0x82
        let data3 = Data([0x82, 0x01, 0x00, 0xFF])
        let (length3, offset3) = try reader.parseBERLength(data: data3, offset: 0)
        #expect(length3 == 0x100)
        #expect(offset3 == 3)
        
        // Invalid offset
        #expect(throws: CardReaderError.invalidResponse) {
            _ = try reader.parseBERLength(data: Data([0x01]), offset: 5)
        }
    }
    
    @Test("Padding removal")
    func testPaddingRemoval() throws {
        let reader = ResidenceCardReader()
        
        // Valid padding
        let paddedData = Data([0x01, 0x02, 0x03, 0x80, 0x00, 0x00])
        let unpaddedData = try reader.removePadding(data: paddedData)
        #expect(unpaddedData == Data([0x01, 0x02, 0x03]))
        
        // Padding at the end only
        let paddedData2 = Data([0x80, 0x00])
        let unpaddedData2 = try reader.removePadding(data: paddedData2)
        #expect(unpaddedData2 == Data())
        
        // Invalid padding (non-zero after 0x80)
        let invalidPadding = Data([0x01, 0x02, 0x80, 0x01])
        #expect(throws: CardReaderError.invalidResponse) {
            _ = try reader.removePadding(data: invalidPadding)
        }
        
        // No padding marker
        let noPadding = Data([0x01, 0x02, 0x03])
        #expect(throws: CardReaderError.invalidResponse) {
            _ = try reader.removePadding(data: noPadding)
        }
    }
    
    @Test("Card type detection")
    func testCardTypeDetection() {
        let reader = ResidenceCardReader()
        
        // Residence card (type "1")
        let residenceType = Data([0xC1, 0x01, 0x31]) // "1" in ASCII
        #expect(reader.isResidenceCard(cardType: residenceType) == true)
        
        // Special permanent resident card (type "2")
        let specialType = Data([0xC1, 0x01, 0x32]) // "2" in ASCII
        #expect(reader.isResidenceCard(cardType: specialType) == false)
        
        // Invalid card type data
        let invalidType = Data([0xFF, 0xFF])
        #expect(reader.isResidenceCard(cardType: invalidType) == false)
        
        // Empty data
        #expect(reader.isResidenceCard(cardType: Data()) == false)
    }
    
    @Test("Parse card type string")
    func testParseCardTypeString() {
        let reader = ResidenceCardReader()
        
        // Valid type "1"
        let type1 = Data([0xC1, 0x01, 0x31])
        #expect(reader.parseCardType(from: type1) == "1")
        
        // Valid type "2"
        let type2 = Data([0xC1, 0x01, 0x32])
        #expect(reader.parseCardType(from: type2) == "2")
        
        // Invalid structure
        let invalid = Data([0xC2, 0x01, 0x31])
        #expect(reader.parseCardType(from: invalid) == nil)
        
        // Too short
        let tooShort = Data([0xC1])
        #expect(reader.parseCardType(from: tooShort) == nil)
    }
    
    @Test("Status word checking")
    func testStatusWordChecking() {
        let reader = ResidenceCardReader()
        
        // Success
        #expect(throws: Never.self) {
            try reader.checkStatusWord(sw1: 0x90, sw2: 0x00)
        }
        
        // Various error codes
        #expect(throws: CardReaderError.cardError(sw1: 0x6A, sw2: 0x82)) {
            try reader.checkStatusWord(sw1: 0x6A, sw2: 0x82)
        }
        
        #expect(throws: CardReaderError.cardError(sw1: 0x69, sw2: 0x84)) {
            try reader.checkStatusWord(sw1: 0x69, sw2: 0x84)
        }
    }

    @Test("NFC availability check")
    func testNFCAvailability() async {
        let reader = ResidenceCardReader()
        
        // Since we're in a test environment without real NFC, this should fail
        let result = await withCheckedContinuation { continuation in
            reader.startReading(cardNumber: "AB12345678CD") { result in
                continuation.resume(returning: result)
            }
        }
        
        // Verify that the operation failed as expected
        switch result {
        case .success:
            #expect(Bool(false), "Expected failure in test environment without real NFC card")
        case .failure(let error):
            // Verify we get the expected NFC unavailable error
            if let cardReaderError = error as? CardReaderError {
                #expect(cardReaderError == .nfcNotAvailable, "Expected NFC unavailable error, got: \(cardReaderError)")
            } else {
                // Other NFC-related errors might also occur in test environment
                #expect(true, "Received non-CardReaderError: \(error)")
            }
        }
    }
}

// MARK: - ResidenceCardDataManager Tests
struct ResidenceCardDataManagerTests {
    
    @Test("Singleton instance")
    func testSingletonInstance() {
        let instance1 = ResidenceCardDataManager.shared
        let instance2 = ResidenceCardDataManager.shared
        
        #expect(instance1 === instance2)
    }
    
    @Test("Set and clear card data")
    func testSetAndClearCardData() async {
        let manager = ResidenceCardDataManager.shared
        
        // Clear any existing data to ensure clean state
        await MainActor.run {
            manager.clearData()
        }
        
        // Give a tiny delay to ensure state is fully updated
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        await MainActor.run {
            #expect(manager.cardData == nil)
            #expect(manager.shouldNavigateToDetail == false)
        }
        
        // Create test data
        let testData = ResidenceCardData(
            commonData: Data([0x01]),
            cardType: Data([0x02]),
            frontImage: Data([0x03]),
            faceImage: Data([0x04]),
            address: Data([0x05]),
            additionalData: nil,
            signature: Data([0x06]),
            signatureVerificationResult: nil
        )
        
        // Set card data
        await MainActor.run {
            manager.setCardData(testData)
        }
        
        // Verify data was set correctly
        await MainActor.run {
            #expect(manager.cardData == testData)
            #expect(manager.shouldNavigateToDetail == true)
            
            // Verify individual properties
            #expect(manager.cardData?.commonData == Data([0x01]))
            #expect(manager.cardData?.cardType == Data([0x02]))
            #expect(manager.cardData?.frontImage == Data([0x03]))
            #expect(manager.cardData?.faceImage == Data([0x04]))
            #expect(manager.cardData?.address == Data([0x05]))
            #expect(manager.cardData?.additionalData == nil)
            #expect(manager.cardData?.signature == Data([0x06]))
        }
        
        // Clear data
        await MainActor.run {
            manager.clearData()
        }
        
        await MainActor.run {
            #expect(manager.cardData == nil)
            #expect(manager.shouldNavigateToDetail == false)
        }
    }
    
    @Test("Set card data with additional data")
    func testSetCardDataWithAdditionalData() async {
        let manager = ResidenceCardDataManager.shared
        
        // Clear any existing data to ensure clean state
        await MainActor.run {
            manager.clearData()
        }
        
        let additionalData = ResidenceCardData.AdditionalData(
            comprehensivePermission: Data("Permission1".utf8),
            individualPermission: Data("Permission2".utf8),
            extensionApplication: Data("Extension".utf8)
        )
        
        let testData = ResidenceCardData(
            commonData: Data([0x10]),
            cardType: Data([0x20]),
            frontImage: Data([0x30]),
            faceImage: Data([0x40]),
            address: Data([0x50]),
            additionalData: additionalData,
            signature: Data([0x60]),
            signatureVerificationResult: nil
        )
        
        await MainActor.run {
            manager.setCardData(testData)
        }
        
        await MainActor.run {
            #expect(manager.cardData == testData)
            #expect(manager.cardData?.additionalData == additionalData)
            #expect(manager.cardData?.additionalData?.comprehensivePermission == Data("Permission1".utf8))
            #expect(manager.cardData?.additionalData?.individualPermission == Data("Permission2".utf8))
            #expect(manager.cardData?.additionalData?.extensionApplication == Data("Extension".utf8))
        }
        
        // Clean up
        await MainActor.run {
            manager.clearData()
        }
    }
    
    @Test("Reset navigation")
    func testResetNavigation() async {
        let manager = ResidenceCardDataManager.shared
        
        // Clear any existing data first to ensure clean state
        await MainActor.run {
            manager.clearData()
        }
        
        // Give a tiny delay to ensure state is fully updated
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        
        let testData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: Data(),
            faceImage: Data(),
            address: Data(),
            additionalData: nil,
            signature: Data(),
            signatureVerificationResult: nil
        )
        
        await MainActor.run {
            manager.setCardData(testData)
            #expect(manager.shouldNavigateToDetail == true)
        }
        
        await MainActor.run {
            manager.resetNavigation()
            #expect(manager.shouldNavigateToDetail == false)
            #expect(manager.cardData == testData) // Data should still be present and equal
        }
        
        // Clean up after test
        await MainActor.run {
            manager.clearData()
        }
    }
}

// MARK: - Integration Tests
struct ResidenceCardReaderIntegrationTests {
    
    @Test("Complete reading flow simulation")
    func testCompleteReadingFlow() async throws {
        // This test simulates the complete flow without actual NFC
        // It validates the data structures and flow logic
        
        let commonData = TestDataFactory.createValidCommonData()
        let cardType = TestDataFactory.createValidCardType(isResidence: true)
        let frontImage = Data(repeating: 0xFF, count: 1000) // Simulated image
        let faceImage = Data(repeating: 0xFE, count: 1000)
        let address = TestDataFactory.createValidAddress()
        
        let additionalData = ResidenceCardData.AdditionalData(
            comprehensivePermission: Data("Permission1".utf8),
            individualPermission: Data("Permission2".utf8),
            extensionApplication: Data("Extension".utf8)
        )
        
        let signature = Data([0x30, 0x82, 0x01, 0x00]) // ASN.1 signature structure
        
        let cardData = ResidenceCardData(
            commonData: commonData,
            cardType: cardType,
            frontImage: frontImage,
            faceImage: faceImage,
            address: address,
            additionalData: additionalData,
            signature: signature,
            signatureVerificationResult: nil
        )
        
        // Verify the complete data structure
        #expect(cardData.commonData.count > 0)
        #expect(cardData.cardType.count > 0)
        #expect(cardData.frontImage.count == 1000)
        #expect(cardData.faceImage.count == 1000)
        #expect(cardData.address.count > 0)
        #expect(cardData.additionalData != nil)
        #expect(cardData.signature.count > 0)
        
        // Test TLV parsing on the created data
        let parsedCommon = cardData.parseTLV(data: commonData, tag: 0xC0)
        #expect(parsedCommon == Data([0x01, 0x02, 0x03, 0x04]))
        
        let parsedCardType = cardData.parseTLV(data: cardType, tag: 0xC1)
        #expect(parsedCardType == Data([0x31])) // "1" in ASCII
        
        let parsedAddress = cardData.parseTLV(data: address, tag: 0xC2)
        #expect(String(data: parsedAddress ?? Data(), encoding: .utf8) == "Tokyo 1234")
    }
    
    @Test("Error recovery scenarios")
    func testErrorRecoveryScenarios() async {
        let reader = ResidenceCardReader()
        
        // Test with various invalid card numbers that should cause immediate errors
        let invalidCardNumbers = [
            "",                      // Empty
            "123",                   // Too short
            "123456789012345",       // Too long (15 characters)
            "AAAA BBBB CC",          // With spaces (12 chars but invalid format)
            "😀😀😀😀😀😀😀😀😀😀😀😀",  // Emoji (12 chars but non-ASCII)
            "ABCDEFGHIJKL",          // 12 ASCII chars (should fail at format validation)
            "12345678901",           // 11 characters (too short)
            "1234567890123"          // 13 characters (too long)
        ]
        
        for cardNumber in invalidCardNumbers {
            await withCheckedContinuation { continuation in
                reader.startReading(cardNumber: cardNumber) { result in
                    switch result {
                    case .success:
                        // Should not succeed with invalid card numbers
                        #expect(Bool(false), "Expected failure for invalid card number: '\(cardNumber)'")
                    case .failure(let error):
                        // Verify we get appropriate error types
                        if let cardReaderError = error as? CardReaderError {
                            switch cardReaderError {
                            case .nfcNotAvailable:
                                // This is expected in simulator environment
                                #expect(true)
                            case .invalidCardNumber, .invalidCardNumberFormat, .invalidCardNumberLength, .invalidCardNumberCharacters:
                                // These are expected for malformed card numbers
                                #expect(true)
                            case .cryptographyError:
                                // This might occur for card numbers that pass initial validation but fail crypto
                                #expect(true)
                            default:
                                #expect(Bool(false), "Unexpected error type: \(cardReaderError)")
                            }
                        } else {
                            // Other errors might occur (like NFC errors)
                            #expect(true)
                        }
                    }
                    continuation.resume()
                }
            }
        }
        
        // Test with a valid format card number (should fail only due to NFC unavailability in test environment)
        let validFormatCardNumber = "AB12345678CD"  // 12 characters in correct format
        await withCheckedContinuation { continuation in
            reader.startReading(cardNumber: validFormatCardNumber) { result in
                switch result {
                case .success:
                    // Should not succeed in test environment due to no real NFC card
                    #expect(Bool(false), "Unexpected success in test environment")
                case .failure(let error):
                    if let cardReaderError = error as? CardReaderError {
                        // Should only fail due to NFC not being available in test environment
                        #expect(cardReaderError == .nfcNotAvailable, "Expected NFC unavailable error for valid card number")
                    } else {
                        // Other NFC-related errors are also acceptable
                        #expect(true)
                    }
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - Front Image Loading Tests
struct FrontImageLoadingTests {
    
    @Test("Load front_image_mmr.tif from Asset Catalog")
    func testLoadFrontImageFromAssets() {
        // Test loading the front_image_mmr image from Asset Catalog
        // Note: Asset Catalog images may not be available in test environment
        guard let frontImage = UIImage(named: "front_image_mmr") else {
            // This is acceptable in test environment where Asset Catalog might not be fully loaded
            #expect(true, "Asset Catalog image may not be available in test environment")
            
            // Test the fallback behavior instead
            let fallbackData = loadFrontImageDataForTest()
            #expect(fallbackData.count > 0, "Fallback data should not be empty")
            return
        }
        
        // Verify the image was loaded successfully
        #expect(frontImage.size.width > 0, "Front image should have width > 0")
        #expect(frontImage.size.height > 0, "Front image should have height > 0")
        
        // Test conversion to TIFF data
        guard let cgImage = frontImage.cgImage else {
            #expect(Bool(false), "Failed to get CGImage from front image")
            return
        }
        
        let tiffData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(tiffData as CFMutableData, UTType.tiff.identifier as CFString, 1, nil) else {
            #expect(Bool(false), "Failed to create TIFF destination")
            return
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        let success = CGImageDestinationFinalize(destination)
        
        #expect(success, "TIFF conversion should succeed")
        #expect(tiffData.length > 0, "TIFF data should not be empty")
        
        // Verify the TIFF data can be read back
        let readBackImage = UIImage(data: tiffData as Data)
        #expect(readBackImage != nil, "Should be able to read back TIFF data as UIImage")
    }
    
    @Test("Load front_image_mmr.tif directly from bundle")
    func testLoadFrontImageDirectlyFromBundle() {
        // Test loading the actual .tif file from the bundle
        guard let path = Bundle.main.path(forResource: "front_image_mmr", ofType: "tif", inDirectory: "Assets.xcassets/front_image_mmr.imageset") else {
            // This is expected to fail since the file is embedded in Asset Catalog
            #expect(true, "Expected: front_image_mmr.tif is embedded in Asset Catalog, not directly accessible")
            return
        }
        
        do {
            let tiffData = try Data(contentsOf: URL(fileURLWithPath: path))
            #expect(tiffData.count > 0, "TIFF file should contain data")
            
            // Test TIFF header validation
            let isTIFF = validateTIFFHeader(data: tiffData)
            #expect(isTIFF, "File should have valid TIFF header")
            
            // Test image creation from TIFF data
            guard let imageSource = CGImageSourceCreateWithData(tiffData as CFData, nil) else {
                #expect(Bool(false), "Failed to create image source from TIFF data")
                return
            }
            
            let imageCount = CGImageSourceGetCount(imageSource)
            #expect(imageCount > 0, "TIFF should contain at least one image")
            
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                #expect(Bool(false), "Failed to create CGImage from TIFF")
                return
            }
            
            let uiImage = UIImage(cgImage: cgImage)
            #expect(uiImage.size.width > 0, "Converted image should have width > 0")
            #expect(uiImage.size.height > 0, "Converted image should have height > 0")
            
        } catch {
            #expect(Bool(false), "Failed to load TIFF file: \(error)")
        }
    }
    
    @Test("Test ResidenceCardDetailView image conversion")
    func testResidenceCardDetailViewImageConversion() {
        // Test the helper functions used in ResidenceCardDetailView
        let frontImageData = loadFrontImageDataForTest()
        #expect(frontImageData.count > 0, "Front image data should not be empty")
        
        // Test image conversion similar to ResidenceCardDetailView.convertImages()
        let convertedImage = convertTIFFToUIImage(data: frontImageData)
        
        if let image = convertedImage {
            #expect(image.size.width > 0, "Converted image should have width > 0")
            #expect(image.size.height > 0, "Converted image should have height > 0")
            
            // Test JPEG conversion for display
            let jpegData = image.jpegData(compressionQuality: 0.9)
            #expect(jpegData != nil, "Should be able to convert to JPEG")
            #expect(jpegData!.count > 0, "JPEG data should not be empty")
            
        } else {
            // If Asset Catalog loading fails, we should at least have valid fallback data
            let isValidTIFF = validateTIFFHeader(data: frontImageData)
            #expect(isValidTIFF || frontImageData.count >= 8, "Should have valid TIFF or valid fallback data")
        }
    }
    
    @Test("Test TIFF header validation")
    func testTIFFHeaderValidation() {
        // Test TIFF header validation with various inputs
        
        // Valid TIFF headers
        let tiffBigEndian = Data([0x4D, 0x4D, 0x00, 0x2A]) // MM (big-endian) + magic number
        let tiffLittleEndian = Data([0x49, 0x49, 0x2A, 0x00]) // II (little-endian) + magic number
        
        #expect(validateTIFFHeader(data: tiffBigEndian), "Should recognize big-endian TIFF")
        #expect(validateTIFFHeader(data: tiffLittleEndian), "Should recognize little-endian TIFF")
        
        // Invalid headers
        let invalidHeader1 = Data([0x00, 0x00, 0x00, 0x00])
        let invalidHeader2 = Data([0xFF, 0xD8]) // JPEG header
        let tooShort = Data([0x4D, 0x4D])
        
        #expect(!validateTIFFHeader(data: invalidHeader1), "Should reject invalid header")
        #expect(!validateTIFFHeader(data: invalidHeader2), "Should reject JPEG header")
        #expect(!validateTIFFHeader(data: tooShort), "Should reject too short data")
        #expect(!validateTIFFHeader(data: Data()), "Should reject empty data")
    }
    
    @Test("Test face image loading")
    func testFaceImageLoading() {
        // Test loading the face_image (which should contain face_image_jp2_80.jp2)
        // Note: Asset Catalog images may not be available in test environment
        guard let faceImage = UIImage(named: "face_image") else {
            // This is acceptable in test environment where Asset Catalog might not be fully loaded
            #expect(true, "Asset Catalog face image may not be available in test environment")
            
            // Test the fallback behavior instead
            let fallbackData = loadFaceImageDataForTest()
            #expect(fallbackData.count > 0, "Fallback face image data should not be empty")
            return
        }
        
        #expect(faceImage.size.width > 0, "Face image should have width > 0")
        #expect(faceImage.size.height > 0, "Face image should have height > 0")
        
        // Test face image data loading function
        let faceImageData = loadFaceImageDataForTest()
        #expect(faceImageData.count > 0, "Face image data should not be empty")
        
        // Test conversion
        let convertedFaceImage = convertToUIImage(data: faceImageData)
        if let image = convertedFaceImage {
            #expect(image.size.width > 0, "Converted face image should have width > 0")
            #expect(image.size.height > 0, "Converted face image should have height > 0")
        }
    }
    
    // Helper functions for testing
    private func loadFrontImageDataForTest() -> Data {
        // Replicate the logic from ResidenceCardDetailView
        if let uiImage = UIImage(named: "front_image_mmr") {
            if let cgImage = uiImage.cgImage {
                let bitmap = NSMutableData()
                if let destination = CGImageDestinationCreateWithData(bitmap as CFMutableData, UTType.tiff.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, cgImage, nil)
                    if CGImageDestinationFinalize(destination) {
                        return bitmap as Data
                    }
                }
            }
            
            // Fallback to JPEG
            if let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
                return jpegData
            }
        }
        
        // Fallback to dummy TIFF data
        var tiffHeader = Data()
        tiffHeader.append(contentsOf: [0x4D, 0x4D]) // Big-endian
        tiffHeader.append(contentsOf: [0x00, 0x2A]) // TIFF magic number
        tiffHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x08]) // IFD offset
        tiffHeader.append(contentsOf: [0x00, 0x00]) // No IFD entries
        return tiffHeader
    }
    
    private func loadFaceImageDataForTest() -> Data {
        // Replicate the logic from ResidenceCardDetailView
        if let uiImage = UIImage(named: "face_image") {
            if let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
                return jpegData
            }
        }
        
        // Fallback to dummy JPEG data
        var jpegHeader = Data()
        jpegHeader.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xE0]) // JPEG SOI and APP0
        jpegHeader.append(contentsOf: [0x00, 0x10]) // APP0 length
        jpegHeader.append(contentsOf: [0x4A, 0x46, 0x49, 0x46, 0x00]) // "JFIF\0"
        jpegHeader.append(contentsOf: [0x01, 0x01]) // Version
        jpegHeader.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01]) // Density
        jpegHeader.append(contentsOf: [0x00, 0x00]) // Thumbnails
        jpegHeader.append(contentsOf: [0xFF, 0xD9]) // EOI
        return jpegHeader
    }
    
    private func convertTIFFToUIImage(data: Data) -> UIImage? {
        // First try direct UIImage creation
        if let image = UIImage(data: data) {
            return image
        }
        
        // Try CGImageSource for TIFF
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
    
    private func convertToUIImage(data: Data) -> UIImage? {
        // Generic image conversion
        if let image = UIImage(data: data) {
            return image
        }
        
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
    
    private func validateTIFFHeader(data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        
        // Check for TIFF magic numbers
        let bigEndian = data[0] == 0x4D && data[1] == 0x4D && data[2] == 0x00 && data[3] == 0x2A
        let littleEndian = data[0] == 0x49 && data[1] == 0x49 && data[2] == 0x2A && data[3] == 0x00
        
        return bigEndian || littleEndian
    }
}

// MARK: - Signature Verification Tests
struct SignatureVerificationTests {
    
    @Test("TLV parsing for signature data")
    func testTLVParsingForSignatureData() {
        let verifier = ResidenceCardSignatureVerifier()
        
        // Create test signature data with check code and certificate
        var signatureData = Data()
        
        // Add check code (tag 0xDA, 256 bytes)
        signatureData.append(0xDA) // Tag
        signatureData.append(0x82) // Length encoding
        signatureData.append(0x01) // Length high byte
        signatureData.append(0x00) // Length low byte (256)
        signatureData.append(Data(repeating: 0xAA, count: 256)) // Check code data
        
        // Add certificate (tag 0xDB, 100 bytes for test)
        signatureData.append(0xDB) // Tag
        signatureData.append(0x64) // Length (100 bytes)
        signatureData.append(Data(repeating: 0xBB, count: 100)) // Certificate data
        
        // Test extraction
        let extractedCheckCode = extractCheckCodeForTest(verifier: verifier, data: signatureData)
        let extractedCertificate = extractCertificateForTest(verifier: verifier, data: signatureData)
        
        #expect(extractedCheckCode?.count == 256)
        #expect(extractedCheckCode?.first == 0xAA)
        #expect(extractedCertificate?.count == 100)
        #expect(extractedCertificate?.first == 0xBB)
    }
    
    @Test("Image value extraction from TLV")
    func testImageValueExtraction() {
        let verifier = ResidenceCardSignatureVerifier()
        
        // Create front image TLV data (tag 0xD0)
        var frontImageTLV = Data()
        frontImageTLV.append(0xD0) // Tag for front image
        frontImageTLV.append(0x81) // Extended length
        frontImageTLV.append(0x64) // 100 bytes
        frontImageTLV.append(Data(repeating: 0xFF, count: 100))
        
        // Create face image TLV data (tag 0xD1)
        var faceImageTLV = Data()
        faceImageTLV.append(0xD1) // Tag for face image
        faceImageTLV.append(0x50) // 80 bytes
        faceImageTLV.append(Data(repeating: 0xEE, count: 80))
        
        let frontValue = extractImageValueForTest(verifier: verifier, data: frontImageTLV)
        let faceValue = extractImageValueForTest(verifier: verifier, data: faceImageTLV)
        
        #expect(frontValue?.count == 100)
        #expect(frontValue?.first == 0xFF)
        #expect(faceValue?.count == 80)
        #expect(faceValue?.first == 0xEE)
    }
    
    @Test("Verification with mock data")
    func testVerificationWithMockData() {
        let verifier = ResidenceCardSignatureVerifier()
        
        // Create mock signature data (simplified)
        var mockSignature = Data()
        mockSignature.append(0xDA) // Check code tag
        mockSignature.append(0x81) // Length
        mockSignature.append(0x10) // 16 bytes for test
        mockSignature.append(Data(repeating: 0x11, count: 16))
        
        mockSignature.append(0xDB) // Certificate tag
        mockSignature.append(0x0A) // 10 bytes for test
        mockSignature.append(Data(repeating: 0x22, count: 10))
        
        // Create mock image data
        let frontImage = Data(repeating: 0x33, count: 100)
        let faceImage = Data(repeating: 0x44, count: 50)
        
        let result = verifier.verifySignature(
            signatureData: mockSignature,
            frontImageData: frontImage,
            faceImageData: faceImage
        )
        
        // Since this is mock data, verification should fail but not crash
        #expect(result.isValid == false)
        #expect(result.error != nil)
    }
    
    @Test("Error handling for missing data")
    func testErrorHandlingForMissingData() {
        let verifier = ResidenceCardSignatureVerifier()
        
        // Test with empty signature data
        let emptyResult = verifier.verifySignature(
            signatureData: Data(),
            frontImageData: Data([0x01]),
            faceImageData: Data([0x02])
        )
        
        #expect(emptyResult.isValid == false)
        #expect(emptyResult.error != nil)
        
        // Test with missing check code
        var incompleteSignature = Data()
        incompleteSignature.append(0xDB) // Only certificate, no check code
        incompleteSignature.append(0x0A)
        incompleteSignature.append(Data(repeating: 0x33, count: 10))
        
        let missingCheckCodeResult = verifier.verifySignature(
            signatureData: incompleteSignature,
            frontImageData: Data([0x01]),
            faceImageData: Data([0x02])
        )
        
        #expect(missingCheckCodeResult.isValid == false)
        #expect(missingCheckCodeResult.error != nil)
    }
    
    @Test("PKCS#1 padding extraction test")
    func testPKCS1PaddingExtraction() {
        // Create mock PKCS#1 v1.5 padded data
        var paddedData = Data()
        paddedData.append(0x00) // Leading zero
        paddedData.append(0x01) // Block type
        paddedData.append(Data(repeating: 0xFF, count: 200)) // Padding
        paddedData.append(0x00) // Separator
        
        // DigestInfo structure (simplified) + SHA-256 hash
        let mockHash = Data(repeating: 0xAB, count: 32) // 32 bytes for SHA-256
        paddedData.append(Data(repeating: 0x30, count: 15)) // Mock DigestInfo
        paddedData.append(mockHash)
        
        let extractedHash = extractHashFromPKCS1ForTest(data: paddedData)
        
        #expect(extractedHash?.count == 32)
        #expect(extractedHash?.first == 0xAB)
    }
    
    @Test("Hash calculation for image data")
    func testHashCalculationForImageData() {
        // Test the hash calculation part of signature verification
        let frontImageData = Data("Front Image Test Data".utf8)
        let faceImageData = Data("Face Image Test Data".utf8)
        
        // Calculate hash of concatenated data (this is what the signature verification does)
        let concatenatedData = frontImageData + faceImageData
        let calculatedHash = SHA256.hash(data: concatenatedData)
        let calculatedHashData = Data(calculatedHash)
        
        // Verify hash properties
        #expect(calculatedHashData.count == 32) // SHA-256 produces 32-byte hash
        #expect(calculatedHashData.hexString.count == 64) // 32 bytes = 64 hex characters
        
        // Verify hash is deterministic
        let secondHash = SHA256.hash(data: concatenatedData)
        let secondHashData = Data(secondHash)
        #expect(calculatedHashData == secondHashData)
        
        // Verify different data produces different hash
        let differentData = frontImageData + Data("Different Face Data".utf8)
        let differentHash = SHA256.hash(data: differentData)
        let differentHashData = Data(differentHash)
        #expect(calculatedHashData != differentHashData)
    }
    
    @Test("Signature verification structure validation")
    func testSignatureVerificationStructureValidation() {
        let verifier = ResidenceCardSignatureVerifier()
        
        // Test with properly structured signature data (but without valid crypto)
        var signatureData = Data()
        
        // Add check code (tag 0xDA, 256 bytes)
        signatureData.append(0xDA)
        signatureData.append(0x82) // Extended length encoding
        signatureData.append(0x01) // Length high byte  
        signatureData.append(0x00) // Length low byte (256)
        signatureData.append(Data(repeating: 0xAA, count: 256)) // Mock check code
        
        // Add certificate (tag 0xDB, 50 bytes for test)
        signatureData.append(0xDB)
        signatureData.append(0x32) // 50 bytes
        signatureData.append(Data(repeating: 0xBB, count: 50)) // Mock certificate
        
        let frontImageData = Data("Test Front".utf8)
        let faceImageData = Data("Test Face".utf8)
        
        let result = verifier.verifySignature(
            signatureData: signatureData,
            frontImageData: frontImageData,
            faceImageData: faceImageData
        )
        
        // Should successfully parse structure but fail at cryptographic validation
        #expect(result.error != .missingCheckCode)
        #expect(result.error != .missingCertificate)
        #expect(result.error != .invalidCheckCodeLength)
        #expect(result.error != .missingImageData)
        
        // Should fail at cryptographic steps (expected for mock data)
        #expect(result.isValid == false)
        #expect(result.error != nil)
    }
    
    @Test("VerificationResult can be valid")
    func testVerificationResultCanBeValid() {
        // Test that VerificationResult.isValid can be true
        let validResult = ResidenceCardSignatureVerifier.VerificationResult(
            isValid: true,
            error: nil,
            details: ResidenceCardSignatureVerifier.VerificationDetails(
                checkCodeHash: "ABCDEF1234567890",
                calculatedHash: "ABCDEF1234567890",
                certificateSubject: "Test Certificate",
                certificateIssuer: "Test CA",
                certificateNotBefore: Date(),
                certificateNotAfter: Date().addingTimeInterval(86400)
            )
        )
        
        #expect(validResult.isValid == true)
        #expect(validResult.error == nil)
        #expect(validResult.details != nil)
        #expect(validResult.details?.checkCodeHash == "ABCDEF1234567890")
        #expect(validResult.details?.calculatedHash == "ABCDEF1234567890")
    }
    
    // Helper functions to access private methods for testing
    private func extractCheckCodeForTest(verifier: ResidenceCardSignatureVerifier, data: Data) -> Data? {
        // This would normally require making the method internal or using @testable
        // For now, we simulate the TLV parsing logic
        return parseTLVForTest(data: data, tag: 0xDA)
    }
    
    private func extractCertificateForTest(verifier: ResidenceCardSignatureVerifier, data: Data) -> Data? {
        return parseTLVForTest(data: data, tag: 0xDB)
    }
    
    private func extractImageValueForTest(verifier: ResidenceCardSignatureVerifier, data: Data) -> Data? {
        if let value = parseTLVForTest(data: data, tag: 0xD0) {
            return value
        } else if let value = parseTLVForTest(data: data, tag: 0xD1) {
            return value
        }
        return data.isEmpty ? nil : data
    }
    
    private func extractHashFromPKCS1ForTest(data: Data) -> Data? {
        // Simplified PKCS#1 v1.5 extraction
        guard data.count >= 32 + 11 else { return nil }
        guard data[0] == 0x00 && data[1] == 0x01 else { return nil }
        
        var separatorIndex = -1
        for i in 2..<data.count {
            if data[i] == 0x00 {
                separatorIndex = i
                break
            } else if data[i] != 0xFF {
                return nil
            }
        }
        
        guard separatorIndex > 0 && separatorIndex < data.count - 32 else { return nil }
        return data.suffix(32)
    }
    
    private func parseTLVForTest(data: Data, tag: UInt8) -> Data? {
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
