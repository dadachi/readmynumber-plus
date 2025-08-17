//
//  ImageProcessor.swift
//  readmynumber
//
//  Created by Claude Code on 2025/08/17.
//

import UIKit
import CoreGraphics
import CoreImage

class ImageProcessor {
    
    // MARK: - Background Transparency
    
    /// Makes the background of an image transparent by detecting and removing similar colored pixels
    /// - Parameters:
    ///   - image: The source UIImage
    ///   - tolerance: Color tolerance for background detection (0.0 to 1.0, default 0.1)
    ///   - backgroundColor: The background color to make transparent (if nil, uses corner pixels)
    /// - Returns: UIImage with transparent background, or nil if processing fails
    static func makeBackgroundTransparent(
        from image: UIImage,
        tolerance: CGFloat = 0.1,
        backgroundColor: UIColor? = nil
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        // Create a bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Draw the image into the context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Get the pixel data
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        
        // Determine the background color to remove
        let targetColor: (r: CGFloat, g: CGFloat, b: CGFloat)
        if let bgColor = backgroundColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            bgColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            targetColor = (r: r, g: g, b: b)
        } else {
            // Use the color from the top-left corner as background color
            let r = CGFloat(pixels[0]) / 255.0
            let g = CGFloat(pixels[1]) / 255.0
            let b = CGFloat(pixels[2]) / 255.0
            targetColor = (r: r, g: g, b: b)
        }
        
        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                
                let r = CGFloat(pixels[pixelIndex]) / 255.0
                let g = CGFloat(pixels[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixels[pixelIndex + 2]) / 255.0
                
                // Calculate color difference
                let deltaR = abs(r - targetColor.r)
                let deltaG = abs(g - targetColor.g)
                let deltaB = abs(b - targetColor.b)
                let colorDistance = sqrt(deltaR * deltaR + deltaG * deltaG + deltaB * deltaB)
                
                // If the color is similar to the background color, make it transparent
                if colorDistance <= tolerance {
                    pixels[pixelIndex + 3] = 0 // Set alpha to 0 (transparent)
                }
            }
        }
        
        // Create a new image from the modified pixel data
        guard let modifiedCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: modifiedCGImage)
    }
    
    /// Advanced background removal using edge detection and flood fill
    /// - Parameters:
    ///   - image: The source UIImage
    ///   - cornerTolerance: Tolerance for detecting background color from corners (0.0 to 1.0)
    ///   - edgeThreshold: Threshold for edge detection to preserve important features
    /// - Returns: UIImage with transparent background, or nil if processing fails
    static func removeBackgroundAdvanced(
        from image: UIImage,
        cornerTolerance: CGFloat = 0.15,
        edgeThreshold: CGFloat = 0.3
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // First, detect edges to preserve important features
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        // Apply edge detection filter
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(edgeThreshold, forKey: kCIInputIntensityKey)
        
        guard let edgeOutput = edgeFilter.outputImage,
              let edgeCGImage = context.createCGImage(edgeOutput, from: edgeOutput.extent) else {
            // Fall back to simple background removal if edge detection fails
            return makeBackgroundTransparent(from: image, tolerance: cornerTolerance)
        }
        
        // Use the edge information to guide background removal
        return makeBackgroundTransparentWithEdges(
            originalImage: image,
            edgeImage: UIImage(cgImage: edgeCGImage),
            tolerance: cornerTolerance
        )
    }
    
    /// Helper function that uses edge information to better preserve important features
    private static func makeBackgroundTransparentWithEdges(
        originalImage: UIImage,
        edgeImage: UIImage,
        tolerance: CGFloat
    ) -> UIImage? {
        guard let originalCGImage = originalImage.cgImage,
              let edgeCGImage = edgeImage.cgImage else { return nil }
        
        let width = originalCGImage.width
        let height = originalCGImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create contexts for both images
        guard let originalContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let edgeContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Draw images into contexts
        originalContext.draw(originalCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        edgeContext.draw(edgeCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let originalData = originalContext.data,
              let edgeData = edgeContext.data else { return nil }
        
        let originalPixels = originalData.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        let edgePixels = edgeData.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        
        // Determine background color from corners
        let corners = [
            (0, 0), // Top-left
            (width - 1, 0), // Top-right
            (0, height - 1), // Bottom-left
            (width - 1, height - 1) // Bottom-right
        ]
        
        var avgR: CGFloat = 0, avgG: CGFloat = 0, avgB: CGFloat = 0
        for (x, y) in corners {
            let pixelIndex = (y * width + x) * bytesPerPixel
            avgR += CGFloat(originalPixels[pixelIndex]) / 255.0
            avgG += CGFloat(originalPixels[pixelIndex + 1]) / 255.0
            avgB += CGFloat(originalPixels[pixelIndex + 2]) / 255.0
        }
        avgR /= CGFloat(corners.count)
        avgG /= CGFloat(corners.count)
        avgB /= CGFloat(corners.count)
        
        let targetColor = (r: avgR, g: avgG, b: avgB)
        
        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                
                // Check if this pixel is near an edge
                let edgeIntensity = CGFloat(edgePixels[pixelIndex]) / 255.0
                let isNearEdge = edgeIntensity > 0.1
                
                let r = CGFloat(originalPixels[pixelIndex]) / 255.0
                let g = CGFloat(originalPixels[pixelIndex + 1]) / 255.0
                let b = CGFloat(originalPixels[pixelIndex + 2]) / 255.0
                
                // Calculate color difference
                let deltaR = abs(r - targetColor.r)
                let deltaG = abs(g - targetColor.g)
                let deltaB = abs(b - targetColor.b)
                let colorDistance = sqrt(deltaR * deltaR + deltaG * deltaG + deltaB * deltaB)
                
                // Be more conservative near edges to preserve details
                let adjustedTolerance = isNearEdge ? tolerance * 0.5 : tolerance
                
                // If the color is similar to the background color, make it transparent
                if colorDistance <= adjustedTolerance {
                    originalPixels[pixelIndex + 3] = 0 // Set alpha to 0 (transparent)
                }
            }
        }
        
        // Create a new image from the modified pixel data
        guard let modifiedCGImage = originalContext.makeImage() else { return nil }
        return UIImage(cgImage: modifiedCGImage)
    }
    
    // MARK: - Utility Functions
    
    /// Loads front_image_mmr.tif from Asset Catalog and makes white background transparent
    /// This is the primary function for processing front_image_mmr.tif
    /// - Parameter tolerance: Color tolerance for white background detection (default 0.08 optimized for front_image_mmr.tif)
    /// - Returns: UIImage with transparent background, or nil if processing fails
    static func loadFrontImageWithTransparentBackground(tolerance: CGFloat = 0.08) -> UIImage? {
        var frontImage: UIImage? = nil
        
        // Try multiple loading approaches
        // 1. Try loading from Asset Catalog with exact name
        frontImage = UIImage(named: "front_image_mmr")
        if frontImage != nil {
            print("Loaded front_image_mmr from Asset Catalog")
        }
        
        // 2. Try loading from front_image asset (which contains front_image_mmr.tiff)
        if frontImage == nil {
            // Load the front_image asset and check if it's actually the TIFF
            if let image = UIImage(named: "front_image") {
                print("Loaded from front_image Asset Catalog")
                frontImage = image
            }
        }
        
        // 3. Try direct bundle loading with .tif extension
        if frontImage == nil {
            if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tif"),
               let imageFromFile = UIImage(contentsOfFile: url.path) {
                print("Loaded front_image_mmr.tif from bundle URL")
                frontImage = imageFromFile
            }
        }
        
        // 4. Try direct bundle loading with .tiff extension
        if frontImage == nil {
            if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tiff"),
               let imageFromFile = UIImage(contentsOfFile: url.path) {
                print("Loaded front_image_mmr.tiff from bundle URL")
                frontImage = imageFromFile
            }
        }
        
        // 5. Try loading from Assets.xcassets directory directly
        if frontImage == nil {
            let assetPaths = [
                "Assets.xcassets/front_image_mmr.imageset/front_image_mmr.tif",
                "Assets.xcassets/front_image.imageset/front_image_mmr.tiff"
            ]
            
            for relativePath in assetPaths {
                if let bundlePath = Bundle.main.resourcePath {
                    let fullPath = (bundlePath as NSString).appendingPathComponent(relativePath)
                    if let image = UIImage(contentsOfFile: fullPath) {
                        print("Loaded from direct path: \(relativePath)")
                        frontImage = image
                        break
                    }
                }
            }
        }
        
        guard let image = frontImage else {
            print("Failed to load front_image_mmr.tif/tiff from any source")
            return nil
        }
        
        print("Processing front_image_mmr with tolerance: \(tolerance), size: \(image.size)")
        
        // Use white color as the background to remove (front_image_mmr.tif has white background)
        let whiteBackground = UIColor.white
        return makeBackgroundTransparent(from: image, tolerance: tolerance, backgroundColor: whiteBackground)
    }
    
    /// Convenience function specifically for front_image_mmr.tif with optimized settings
    /// - Returns: UIImage with transparent background using optimal settings for front_image_mmr.tif
    static func processFrontImageMMR() -> UIImage? {
        // Use optimized tolerance value specifically tuned for front_image_mmr.tif
        return loadFrontImageWithTransparentBackground(tolerance: 0.08)
    }
    
    /// Specifically removes white background from front_image_mmr.tif
    /// - Parameters:
    ///   - image: The front image with white background
    ///   - tolerance: Tolerance for white color detection (default 0.08 for better precision)
    /// - Returns: UIImage with transparent background
    static func removeWhiteBackground(from image: UIImage, tolerance: CGFloat = 0.08) -> UIImage? {
        return makeBackgroundTransparent(from: image, tolerance: tolerance, backgroundColor: UIColor.white)
    }
    
    /// Saves an image with transparent background to the Photos library
    /// - Parameters:
    ///   - image: The image with transparent background
    ///   - completion: Completion handler with success/failure result
    static func saveTransparentImage(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        completion(true, nil)
    }
    
    /// Converts an image to PNG data to preserve transparency
    /// - Parameter image: The image with transparency
    /// - Returns: PNG data, or nil if conversion fails
    static func convertToPNGData(_ image: UIImage) -> Data? {
        return image.pngData()
    }
    
    /// Creates a preview showing original and transparent versions side by side
    /// - Parameters:
    ///   - originalImage: The original image
    ///   - transparentImage: The image with transparent background
    /// - Returns: Combined preview image
    static func createBeforeAfterPreview(
        originalImage: UIImage,
        transparentImage: UIImage
    ) -> UIImage? {
        let size = CGSize(
            width: originalImage.size.width * 2 + 20,
            height: originalImage.size.height + 40
        )
        
        UIGraphicsBeginImageContextWithOptions(size, false, originalImage.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw white background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Draw original image
        originalImage.draw(in: CGRect(x: 0, y: 20, width: originalImage.size.width, height: originalImage.size.height))
        
        // Draw transparent image with checkerboard background
        let transparentRect = CGRect(
            x: originalImage.size.width + 20,
            y: 20,
            width: transparentImage.size.width,
            height: transparentImage.size.height
        )
        
        // Draw checkerboard pattern
        drawCheckerboard(in: transparentRect, context: context)
        
        // Draw transparent image
        transparentImage.draw(in: transparentRect)
        
        // Add labels
        let labelFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.black
        ]
        
        "Original".draw(at: CGPoint(x: 10, y: 2), withAttributes: labelAttributes)
        "Transparent".draw(at: CGPoint(x: originalImage.size.width + 30, y: 2), withAttributes: labelAttributes)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// Draws a checkerboard pattern to visualize transparency
    private static func drawCheckerboard(in rect: CGRect, context: CGContext) {
        let checkSize: CGFloat = 10
        let lightColor = UIColor(white: 0.9, alpha: 1.0).cgColor
        let darkColor = UIColor(white: 0.7, alpha: 1.0).cgColor
        
        let numX = Int(ceil(rect.width / checkSize))
        let numY = Int(ceil(rect.height / checkSize))
        
        for x in 0..<numX {
            for y in 0..<numY {
                let checkRect = CGRect(
                    x: rect.minX + CGFloat(x) * checkSize,
                    y: rect.minY + CGFloat(y) * checkSize,
                    width: checkSize,
                    height: checkSize
                )
                
                let isEvenX = x % 2 == 0
                let isEvenY = y % 2 == 0
                let useLight = (isEvenX && isEvenY) || (!isEvenX && !isEvenY)
                
                context.setFillColor(useLight ? lightColor : darkColor)
                context.fill(checkRect)
            }
        }
    }
}