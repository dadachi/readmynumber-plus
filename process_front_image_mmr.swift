#!/usr/bin/env swift

import Foundation
import UIKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Simple script to process front_image_mmr.tif and remove white background

print("Processing front_image_mmr.tif...")
print("=====================================")

// Function to remove white background
func removeWhiteBackground(from image: UIImage, tolerance: CGFloat = 0.08) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    guard let data = context.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
    
    // White color target
    let targetColor = (r: CGFloat(1.0), g: CGFloat(1.0), b: CGFloat(1.0))
    
    // Process each pixel
    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = (y * width + x) * bytesPerPixel
            
            let r = CGFloat(pixels[pixelIndex]) / 255.0
            let g = CGFloat(pixels[pixelIndex + 1]) / 255.0
            let b = CGFloat(pixels[pixelIndex + 2]) / 255.0
            
            let deltaR = abs(r - targetColor.r)
            let deltaG = abs(g - targetColor.g)
            let deltaB = abs(b - targetColor.b)
            let colorDistance = sqrt(deltaR * deltaR + deltaG * deltaG + deltaB * deltaB)
            
            if colorDistance <= tolerance {
                pixels[pixelIndex + 3] = 0 // Set alpha to 0
            }
        }
    }
    
    guard let modifiedCGImage = context.makeImage() else { return nil }
    return UIImage(cgImage: modifiedCGImage)
}

// Main processing
let inputPath = "readmynumber/Assets.xcassets/front_image_mmr.imageset/front_image_mmr.tif"
let outputPath = "front_image_mmr_transparent.png"

print("Input file: \(inputPath)")
print("Output file: \(outputPath)")

// Load the image
guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: inputPath)) else {
    print("❌ Error: Could not load front_image_mmr.tif")
    print("Make sure the file exists at: \(inputPath)")
    exit(1)
}

print("✅ Loaded image data: \(imageData.count) bytes")

// Create UIImage from data
guard let originalImage = UIImage(data: imageData) else {
    print("❌ Error: Could not create image from TIFF data")
    exit(1)
}

print("✅ Created UIImage: \(originalImage.size.width) x \(originalImage.size.height)")

// Process with different tolerance values
let tolerances: [CGFloat] = [0.05, 0.08, 0.10, 0.15]

for tolerance in tolerances {
    print("\nProcessing with tolerance: \(tolerance)")
    
    guard let transparentImage = removeWhiteBackground(from: originalImage, tolerance: tolerance) else {
        print("❌ Failed to process with tolerance \(tolerance)")
        continue
    }
    
    // Save as PNG
    guard let pngData = transparentImage.pngData() else {
        print("❌ Failed to convert to PNG")
        continue
    }
    
    let outputFile = "front_image_mmr_transparent_\(Int(tolerance * 100)).png"
    
    do {
        try pngData.write(to: URL(fileURLWithPath: outputFile))
        print("✅ Saved: \(outputFile) (\(pngData.count) bytes)")
    } catch {
        print("❌ Error saving file: \(error)")
    }
}

print("\n=====================================")
print("Processing complete!")
print("Check the output PNG files with different tolerance levels.")
print("Recommended: front_image_mmr_transparent_8.png (tolerance 0.08)")