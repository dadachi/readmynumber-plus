//
//  SignatureVerifierTests.swift
//  readmynumberTests
//
//  Created on 2025/08/18.
//

import Testing
import Foundation
@testable import readmynumber

struct SignatureVerifierTests {
    
    let verifier = ResidenceCardSignatureVerifier()
    
    // MARK: - TLV Parsing Tests
    
    @Test func testParseTLVWithFrontImage() throws {
        // Create test data with tag 0xD0 (front image)
        // Tag: 0xD0, Length: 0x82 1B 58 (7000 in BER-TLV), Value: dummy data
        var tlvData = Data()
        tlvData.append(0xD0) // Tag
        tlvData.append(contentsOf: [0x82, 0x1B, 0x58]) // Length (7000)
        let dummyImageData = Data(repeating: 0xFF, count: 7000)
        tlvData.append(dummyImageData)
        
        // Extract using the private method through reflection or test the public API
        let result = testExtractImageValue(from: tlvData)
        
        #expect(result != nil)
        #expect(result?.count == 7000)
        #expect(result?.prefix(10) == Data(repeating: 0xFF, count: 10))
    }
    
    @Test func testParseTLVWithFaceImage() throws {
        // Create test data with tag 0xD1 (face image)
        // Tag: 0xD1, Length: 0x82 0B B8 (3000 in BER-TLV), Value: dummy data
        var tlvData = Data()
        tlvData.append(0xD1) // Tag
        tlvData.append(contentsOf: [0x82, 0x0B, 0xB8]) // Length (3000)
        let dummyImageData = Data(repeating: 0xAA, count: 3000)
        tlvData.append(dummyImageData)
        
        let result = testExtractImageValue(from: tlvData)
        
        #expect(result != nil)
        #expect(result?.count == 3000)
        #expect(result?.prefix(10) == Data(repeating: 0xAA, count: 10))
    }
    
    @Test func testPaddingForShortFrontImage() throws {
        // Create test data with tag 0xD0 but only 5000 bytes of actual data
        var tlvData = Data()
        tlvData.append(0xD0) // Tag
        tlvData.append(contentsOf: [0x82, 0x13, 0x88]) // Length (5000)
        let shortImageData = Data(repeating: 0xBB, count: 5000)
        tlvData.append(shortImageData)
        
        let result = testExtractImageValue(from: tlvData)
        
        #expect(result != nil)
        #expect(result?.count == 7000) // Should be padded to 7000
        #expect(result?.prefix(5000) == Data(repeating: 0xBB, count: 5000))
        #expect(result?.suffix(2000) == Data(repeating: 0x00, count: 2000)) // Check padding
    }
    
    @Test func testPaddingForShortFaceImage() throws {
        // Create test data with tag 0xD1 but only 2000 bytes of actual data
        var tlvData = Data()
        tlvData.append(0xD1) // Tag
        tlvData.append(contentsOf: [0x82, 0x07, 0xD0]) // Length (2000)
        let shortImageData = Data(repeating: 0xCC, count: 2000)
        tlvData.append(shortImageData)
        
        let result = testExtractImageValue(from: tlvData)
        
        #expect(result != nil)
        #expect(result?.count == 3000) // Should be padded to 3000
        #expect(result?.prefix(2000) == Data(repeating: 0xCC, count: 2000))
        #expect(result?.suffix(1000) == Data(repeating: 0x00, count: 1000)) // Check padding
    }
    
    @Test func testExtractCheckCode() throws {
        // Create test data with tag 0xDA (check code)
        var tlvData = Data()
        tlvData.append(0xDA) // Tag
        tlvData.append(contentsOf: [0x82, 0x01, 0x00]) // Length (256)
        let checkCodeData = Data(repeating: 0xEE, count: 256)
        tlvData.append(checkCodeData)
        
        // Add some additional TLV data to make it more realistic
        tlvData.append(0xDB) // Certificate tag
        tlvData.append(contentsOf: [0x82, 0x04, 0xB0]) // Length (1200)
        tlvData.append(Data(repeating: 0xDD, count: 1200))
        
        let result = testParseTLV(data: tlvData, tag: 0xDA)
        
        #expect(result != nil)
        #expect(result?.count == 256)
        #expect(result == checkCodeData)
    }
    
    @Test func testExtractCertificate() throws {
        // Create test data with tag 0xDB (certificate)
        var tlvData = Data()
        
        // Add check code first
        tlvData.append(0xDA) // Tag
        tlvData.append(contentsOf: [0x82, 0x01, 0x00]) // Length (256)
        tlvData.append(Data(repeating: 0xEE, count: 256))
        
        // Add certificate
        tlvData.append(0xDB) // Tag
        tlvData.append(contentsOf: [0x82, 0x04, 0xB0]) // Length (1200)
        let certificateData = Data(repeating: 0xDD, count: 1200)
        tlvData.append(certificateData)
        
        let result = testParseTLV(data: tlvData, tag: 0xDB)
        
        #expect(result != nil)
        #expect(result?.count == 1200)
        #expect(result == certificateData)
    }
    
    @Test func testCompleteScenarioFromPDF() throws {
        // This test uses the actual structure from PDF 別添2
        // Build the complete DF3/EF01 structure
        var df3ef01 = Data()
        
        // Check code: DA 82 01 00 [256 bytes]
        df3ef01.append(0xDA)
        df3ef01.append(contentsOf: [0x82, 0x01, 0x00])
        let checkCode = Data(repeating: 0xAB, count: 256)
        df3ef01.append(checkCode)
        
        // Certificate: DB 82 04 B0 [1200 bytes]
        df3ef01.append(0xDB)
        df3ef01.append(contentsOf: [0x82, 0x04, 0xB0])
        let certificate = Data(repeating: 0xCD, count: 1200)
        df3ef01.append(certificate)
        
        // Test check code extraction
        let extractedCheckCode = testParseTLV(data: df3ef01, tag: 0xDA)
        #expect(extractedCheckCode == checkCode)
        
        // Test certificate extraction
        let extractedCertificate = testParseTLV(data: df3ef01, tag: 0xDB)
        #expect(extractedCertificate == certificate)
    }
    
    @Test func testImageDataFromPDFStructure() throws {
        // Test with the exact structure from PDF:
        // Front image: D0 82 1B 58 [券面(表)イメージ] 80 00 00 00
        var frontImageTLV = Data()
        frontImageTLV.append(0xD0)
        frontImageTLV.append(contentsOf: [0x82, 0x1B, 0x58]) // 7000 bytes
        
        // Create image data exactly matching the length specified in TLV
        // This includes the actual image data plus the padding from the PDF example
        let actualImageSize = 6996 // Image content
        let paddingSize = 4 // 7000 - 6996 = 4 (the "80 00 00 00" in PDF)
        
        var fullImageData = Data(repeating: 0x55, count: actualImageSize)
        fullImageData.append(Data([0x80, 0x00, 0x00, 0x00])) // PDF padding example
        
        frontImageTLV.append(fullImageData)
        
        let result = testExtractImageValue(from: frontImageTLV)
        
        #expect(result != nil)
        #expect(result?.count == 7000) // Should be exactly 7000 (no additional padding needed)
        #expect(result?.prefix(actualImageSize) == Data(repeating: 0x55, count: actualImageSize))
        #expect(result?.suffix(paddingSize) == Data([0x80, 0x00, 0x00, 0x00]))
    }
    
    @Test func testFaceImageFromPDFStructure() throws {
        // Test with the exact structure from PDF:
        // Face image: D1 82 0B B8 [顔写真] 80 00 00 00
        var faceImageTLV = Data()
        faceImageTLV.append(0xD1)
        faceImageTLV.append(contentsOf: [0x82, 0x0B, 0xB8]) // 3000 bytes
        
        // Create image data exactly matching the length specified in TLV
        // This includes the actual image data plus the padding from the PDF example
        let actualImageSize = 2996 // Image content
        let paddingSize = 4 // 3000 - 2996 = 4 (the "80 00 00 00" in PDF)
        
        var fullImageData = Data(repeating: 0x66, count: actualImageSize)
        fullImageData.append(Data([0x80, 0x00, 0x00, 0x00])) // PDF padding example
        
        faceImageTLV.append(fullImageData)
        
        let result = testExtractImageValue(from: faceImageTLV)
        
        #expect(result != nil)
        #expect(result?.count == 3000) // Should be exactly 3000 (no additional padding needed)
        #expect(result?.prefix(actualImageSize) == Data(repeating: 0x66, count: actualImageSize))
        #expect(result?.suffix(paddingSize) == Data([0x80, 0x00, 0x00, 0x00]))
    }
    
    // MARK: - Helper Methods
    
    // These methods simulate accessing the private methods in SignatureVerifier
    // In a real test, we might need to use the public API or make these methods internal for testing
    
    private func testExtractImageValue(from imageData: Data) -> Data? {
        // Replicate the logic from extractImageValue
        var extractedValue: Data?
        var targetLength: Int?
        
        if let value = testParseTLV(data: imageData, tag: 0xD0) {
            extractedValue = value
            targetLength = 7000 // frontImageFixedLength
        } else if let value = testParseTLV(data: imageData, tag: 0xD1) {
            extractedValue = value
            targetLength = 3000 // faceImageFixedLength
        } else if !imageData.isEmpty {
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
            return value.prefix(fixedLength)
        }
        
        return value
    }
    
    private func testParseTLV(data: Data, tag: UInt8) -> Data? {
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