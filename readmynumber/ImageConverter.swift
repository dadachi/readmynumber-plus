//
//  ImageConverter.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import UIKit
import ImageIO
import CoreGraphics

/// A utility class for converting various image formats to UIImage
class ImageConverter {
    
    // MARK: - Public Methods
    
    /// Convert both front and face images from ResidenceCardData
    /// - Parameter cardData: The residence card data containing raw image data
    /// - Returns: Tuple containing optional UIImages for front and face
    static func convertResidenceCardImages(cardData: ResidenceCardData) -> (front: UIImage?, face: UIImage?) {
        let frontImage = convertTIFFToUIImage(data: cardData.frontImage)
        let faceImage = convertJPEG2000ToUIImage(data: cardData.faceImage)
        return (front: frontImage, face: faceImage)
    }
    
    /// Convert TIFF data to UIImage
    /// - Parameter data: Raw TIFF image data
    /// - Returns: UIImage if conversion successful, nil otherwise
    static func convertTIFFToUIImage(data: Data) -> UIImage? {
        // First try direct UIImage loading
        if let image = UIImage(data: data) {
            print("Successfully loaded TIFF image as UIImage")
            return image
        }
        
        // Validate data size
        guard data.count > 100 else {
            print("TIFF data too small or invalid: \(data.count) bytes")
            return nil
        }
        
        // Try CGImageSource for TIFF format
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            print("Successfully loaded TIFF image via CGImageSource")
            return UIImage(cgImage: cgImage)
        }
        
        print("Failed to load TIFF image, data size: \(data.count)")
        return nil
    }
    
    /// Convert JPEG2000 data to UIImage
    /// - Parameter data: Raw JPEG2000 image data
    /// - Returns: UIImage if conversion successful, nil otherwise
    static func convertJPEG2000ToUIImage(data: Data) -> UIImage? {
        // First try direct UIImage loading
        if let image = UIImage(data: data) {
            print("Successfully loaded JPEG2000 image as UIImage")
            return image
        }
        
        // Validate data size
        guard data.count > 100 else {
            print("JPEG2000 data too small or invalid: \(data.count) bytes")
            return nil
        }
        
        // Try CGImageSource for JPEG2000 format
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            print("Successfully loaded JPEG2000 image via CGImageSource")
            return UIImage(cgImage: cgImage)
        }
        
        print("Failed to load JPEG2000 image, data size: \(data.count)")
        return nil
    }
    
    // MARK: - Generic Conversion Method
    
    /// Convert generic image data to UIImage (supports multiple formats)
    /// - Parameter data: Raw image data in any supported format
    /// - Returns: UIImage if conversion successful, nil otherwise
    static func convertImageDataToUIImage(data: Data) -> UIImage? {
        // First try direct UIImage loading
        if let image = UIImage(data: data) {
            return image
        }
        
        // Validate data size
        guard data.count > 100 else {
            print("Image data too small or invalid: \(data.count) bytes")
            return nil
        }
        
        // Try CGImageSource for various formats
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            return UIImage(cgImage: cgImage)
        }
        
        print("Failed to convert image data, size: \(data.count)")
        return nil
    }
}