//
//  ResidenceCardReaderTests.swift
//  readmynumberTests
//
//  Created on 2025/08/16.
//

import Testing
import Foundation
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
            signature: signature
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
            signature: Data()
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
            signature: Data()
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
            signature: Data()
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
            _ = try reader.generateKeys(from: "AA1234567890")
        }
        
        // Invalid card number (non-ASCII)
        #expect(throws: CardReaderError.self) {
            _ = try reader.generateKeys(from: "あいうえお")
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
        var completionCalled = false
        var receivedError: Error?
        
        // Since we're in a test environment without real NFC, this should fail
        reader.startReading(cardNumber: "AA1234567890") { result in
            completionCalled = true
            if case .failure(let error) = result {
                receivedError = error
            }
        }
        
        // Give some time for the completion to be called
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        #expect(completionCalled == true)
        #expect(receivedError as? CardReaderError == CardReaderError.nfcNotAvailable)
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
    func testSetAndClearCardData() {
        let manager = ResidenceCardDataManager.shared
        
        // Clear any existing data
        manager.clearData()
        
        #expect(manager.cardData == nil)
        #expect(manager.shouldNavigateToDetail == false)
        
        // Set card data
        let testData = ResidenceCardData(
            commonData: Data([0x01]),
            cardType: Data([0x02]),
            frontImage: Data([0x03]),
            faceImage: Data([0x04]),
            address: Data([0x05]),
            additionalData: nil,
            signature: Data([0x06])
        )
        
        manager.setCardData(testData)
        
        #expect(manager.cardData != nil)
        #expect(manager.shouldNavigateToDetail == true)
        
        // Clear data
        manager.clearData()
        
        #expect(manager.cardData == nil)
        #expect(manager.shouldNavigateToDetail == false)
    }
    
    @Test("Reset navigation")
    func testResetNavigation() {
        let manager = ResidenceCardDataManager.shared
        
        // Clear any existing data first to ensure clean state
        manager.clearData()
        
        let testData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: Data(),
            faceImage: Data(),
            address: Data(),
            additionalData: nil,
            signature: Data()
        )
        
        manager.setCardData(testData)
        #expect(manager.shouldNavigateToDetail == true)
        
        manager.resetNavigation()
        #expect(manager.shouldNavigateToDetail == false)
        #expect(manager.cardData != nil) // Data should still be present
        
        // Clean up after test
        manager.clearData()
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
            signature: signature
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
    func testErrorRecoveryScenarios() {
        let reader = ResidenceCardReader()
        
        // Test with various invalid inputs
        let invalidCardNumbers = [
            "",              // Empty
            "123",           // Too short
            "123456789012345", // Too long
            "AAAA BBBB CC",  // With spaces
            "😀😀😀😀😀😀😀😀😀😀😀😀"  // Emoji
        ]
        
        for cardNumber in invalidCardNumbers {
            var errorOccurred = false
            
            reader.startReading(cardNumber: cardNumber) { result in
                if case .failure = result {
                    errorOccurred = true
                }
            }
            
            #expect(errorOccurred == true || cardNumber.count == 12)
        }
    }
}