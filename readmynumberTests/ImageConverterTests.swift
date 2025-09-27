//
//  ImageConverterTests.swift
//  readmynumberTests
//
//  Created on 2025/09/09.
//

import Testing
import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import readmynumber

struct RDCImageConverterTests {
    
    // MARK: - Test Helpers
    
    /// Create a valid TIFF image data for testing
    private func createTestTIFFData() -> Data {
        // Create a simple 2x2 red image
        let size = CGSize(width: 2, height: 2)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = image.cgImage else {
            return Data()
        }
        
        // Convert to TIFF format
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        
        return mutableData as Data
    }
    
    /// Create a valid JPEG data for testing (simulating JPEG2000)
    private func createTestJPEGData() -> Data {
        // Create a simple 2x2 blue image
        let size = CGSize(width: 2, height: 2)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            return Data()
        }
        
        // Convert to JPEG format (as JPEG2000 is not easily creatable in tests)
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
    
    /// Create invalid/corrupted image data
    private func createInvalidImageData() -> Data {
        return Data([0xFF, 0xFF, 0xFF, 0xFF])
    }
    
    /// Create empty data
    private func createEmptyData() -> Data {
        return Data()
    }
    
    /// Create small but potentially valid-looking data
    private func createSmallData() -> Data {
        // Less than 100 bytes but with some structure
        return Data(repeating: 0x00, count: 50)
    }
    
    // MARK: - TIFF Conversion Tests
    
    @Test("Convert valid TIFF data to UIImage")
    func testConvertValidTIFFToUIImage() {
        let tiffData = createTestTIFFData()
        let result = RDCImageConverter.convertTIFFToUIImage(data: tiffData)
        
        #expect(result != nil, "Should successfully convert valid TIFF data")
        #expect(result?.size.width == 2, "Image width should be 2")
        #expect(result?.size.height == 2, "Image height should be 2")
    }
    
    @Test("Convert empty TIFF data returns nil")
    func testConvertEmptyTIFFData() {
        let emptyData = createEmptyData()
        let result = RDCImageConverter.convertTIFFToUIImage(data: emptyData)
        
        #expect(result == nil, "Should return nil for empty data")
    }
    
    @Test("Convert small TIFF data returns nil")
    func testConvertSmallTIFFData() {
        let smallData = createSmallData()
        let result = RDCImageConverter.convertTIFFToUIImage(data: smallData)
        
        #expect(result == nil, "Should return nil for data smaller than 100 bytes")
    }
    
    @Test("Convert invalid TIFF data returns nil")
    func testConvertInvalidTIFFData() {
        let invalidData = createInvalidImageData()
        let result = RDCImageConverter.convertTIFFToUIImage(data: invalidData)
        
        #expect(result == nil, "Should return nil for invalid TIFF data")
    }
    
    // MARK: - JPEG2000 Conversion Tests
    
    @Test("Convert valid JPEG data to UIImage")
    func testConvertValidJPEGToUIImage() {
        let jpegData = createTestJPEGData()
        let result = RDCImageConverter.convertJPEG2000ToUIImage(data: jpegData)
        
        #expect(result != nil, "Should successfully convert valid JPEG data")
        #expect(result?.size.width == 2, "Image width should be 2")
        #expect(result?.size.height == 2, "Image height should be 2")
    }
    
    @Test("Convert empty JPEG2000 data returns nil")
    func testConvertEmptyJPEG2000Data() {
        let emptyData = createEmptyData()
        let result = RDCImageConverter.convertJPEG2000ToUIImage(data: emptyData)
        
        #expect(result == nil, "Should return nil for empty data")
    }
    
    @Test("Convert small JPEG2000 data returns nil")
    func testConvertSmallJPEG2000Data() {
        let smallData = createSmallData()
        let result = RDCImageConverter.convertJPEG2000ToUIImage(data: smallData)
        
        #expect(result == nil, "Should return nil for data smaller than 100 bytes")
    }
    
    @Test("Convert invalid JPEG2000 data returns nil")
    func testConvertInvalidJPEG2000Data() {
        let invalidData = createInvalidImageData()
        let result = RDCImageConverter.convertJPEG2000ToUIImage(data: invalidData)
        
        #expect(result == nil, "Should return nil for invalid JPEG2000 data")
    }
    
    // MARK: - Generic Image Conversion Tests
    
    @Test("Convert generic valid image data")
    func testConvertGenericImageData() {
        let jpegData = createTestJPEGData()
        let result = RDCImageConverter.convertImageDataToUIImage(data: jpegData)
        
        #expect(result != nil, "Should successfully convert valid image data")
    }
    
    @Test("Convert generic empty data returns nil")
    func testConvertGenericEmptyData() {
        let emptyData = createEmptyData()
        let result = RDCImageConverter.convertImageDataToUIImage(data: emptyData)
        
        #expect(result == nil, "Should return nil for empty data")
    }
    
    @Test("Convert generic small data returns nil")
    func testConvertGenericSmallData() {
        let smallData = createSmallData()
        let result = RDCImageConverter.convertImageDataToUIImage(data: smallData)
        
        #expect(result == nil, "Should return nil for small data")
    }
    
    // MARK: - ResidenceCardData Conversion Tests
    
    @Test("Convert ResidenceCardData with valid images")
    func testConvertResidenceCardDataWithValidImages() {
        let tiffData = createTestTIFFData()
        let jpegData = createTestJPEGData()
        
        let cardData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: tiffData,
            faceImage: jpegData,
            address: Data(),
            additionalData: nil,
            checkCode: Data(repeating: 0x00, count: 256),
            certificate: Data(),
            signatureVerificationResult: nil
        )
        
        let result = RDCImageConverter.convertResidenceCardImages(cardData: cardData)
        
        #expect(result.front != nil, "Should convert front image")
        #expect(result.face != nil, "Should convert face image")
        #expect(result.front?.size.width == 2, "Front image width should be 2")
        #expect(result.face?.size.width == 2, "Face image width should be 2")
    }
    
    @Test("Convert ResidenceCardData with invalid front image")
    func testConvertResidenceCardDataWithInvalidFrontImage() {
        let invalidData = createInvalidImageData()
        let jpegData = createTestJPEGData()
        
        let cardData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: invalidData,
            faceImage: jpegData,
            address: Data(),
            additionalData: nil,
            checkCode: Data(repeating: 0x00, count: 256),
            certificate: Data(),
            signatureVerificationResult: nil
        )
        
        let result = RDCImageConverter.convertResidenceCardImages(cardData: cardData)
        
        #expect(result.front == nil, "Should return nil for invalid front image")
        #expect(result.face != nil, "Should still convert valid face image")
    }
    
    @Test("Convert ResidenceCardData with invalid face image")
    func testConvertResidenceCardDataWithInvalidFaceImage() {
        let tiffData = createTestTIFFData()
        let invalidData = createInvalidImageData()
        
        let cardData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: tiffData,
            faceImage: invalidData,
            address: Data(),
            additionalData: nil,
            checkCode: Data(repeating: 0x00, count: 256),
            certificate: Data(),
            signatureVerificationResult: nil
        )
        
        let result = RDCImageConverter.convertResidenceCardImages(cardData: cardData)
        
        #expect(result.front != nil, "Should convert valid front image")
        #expect(result.face == nil, "Should return nil for invalid face image")
    }
    
    @Test("Convert ResidenceCardData with both invalid images")
    func testConvertResidenceCardDataWithBothInvalidImages() {
        let invalidData = createInvalidImageData()
        
        let cardData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: invalidData,
            faceImage: invalidData,
            address: Data(),
            additionalData: nil,
            checkCode: Data(repeating: 0x00, count: 256),
            certificate: Data(),
            signatureVerificationResult: nil
        )
        
        let result = RDCImageConverter.convertResidenceCardImages(cardData: cardData)
        
        #expect(result.front == nil, "Should return nil for invalid front image")
        #expect(result.face == nil, "Should return nil for invalid face image")
    }
    
    @Test("Convert ResidenceCardData with empty images")
    func testConvertResidenceCardDataWithEmptyImages() {
        let emptyData = createEmptyData()
        
        let cardData = ResidenceCardData(
            commonData: Data(),
            cardType: Data(),
            frontImage: emptyData,
            faceImage: emptyData,
            address: Data(),
            additionalData: nil,
            checkCode: Data(repeating: 0x00, count: 256),
            certificate: Data(),
            signatureVerificationResult: nil
        )
        
        let result = RDCImageConverter.convertResidenceCardImages(cardData: cardData)
        
        #expect(result.front == nil, "Should return nil for empty front image")
        #expect(result.face == nil, "Should return nil for empty face image")
    }
    
    // MARK: - Performance Tests
    
    @Test("Performance: Convert large TIFF data")
    func testPerformanceConvertLargeTIFF() {
        // Create a larger image for performance testing
        let size = CGSize(width: 1000, height: 1000)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.green.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = image.cgImage else {
            #expect(Bool(false), "Failed to create test image")
            return
        }
        
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            #expect(Bool(false), "Failed to create TIFF data")
            return
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        
        let tiffData = mutableData as Data
        
        // Measure conversion time
        let startTime = Date()
        let result = RDCImageConverter.convertTIFFToUIImage(data: tiffData)
        let endTime = Date()
        
        let conversionTime = endTime.timeIntervalSince(startTime)
        
        #expect(result != nil, "Should successfully convert large TIFF")
        #expect(conversionTime < 1.0, "Conversion should complete within 1 second")
        
        print("Large TIFF conversion took: \(conversionTime) seconds")
    }
}