//
//  ImageLoadingDiagnostic.swift
//  readmynumber
//
//  Diagnostic tool to debug front_image_mmr.tif loading issues
//

import UIKit
import Foundation

class ImageLoadingDiagnostic {
    
    /// Run comprehensive diagnostic to find and test loading front_image_mmr.tif
    static func runDiagnostic() {
        print("=== IMAGE LOADING DIAGNOSTIC ===")
        print("Searching for front_image_mmr.tif/tiff...")
        print("================================\n")
        
        // Test 1: Asset Catalog loading
        print("Test 1: Asset Catalog Loading")
        print("------------------------------")
        
        let assetNames = ["front_image_mmr", "front_image", "frontImage", "front-image-mmr"]
        for name in assetNames {
            if let image = UIImage(named: name) {
                print("✅ SUCCESS: UIImage(named: \"\(name)\") - Size: \(image.size)")
            } else {
                print("❌ FAILED: UIImage(named: \"\(name)\")")
            }
        }
        
        print("\nTest 2: Bundle Resource Loading")
        print("--------------------------------")
        
        // Test 2: Bundle resource loading
        let resourceNames = ["front_image_mmr", "front_image", "frontImage"]
        let extensions = ["tif", "tiff", "TIF", "TIFF"]
        
        for name in resourceNames {
            for ext in extensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    print("✅ Found: \(name).\(ext) at \(url.path)")
                    if let image = UIImage(contentsOfFile: url.path) {
                        print("   ✅ Loaded successfully - Size: \(image.size)")
                    } else {
                        print("   ❌ Failed to create UIImage from file")
                    }
                }
            }
        }
        
        print("\nTest 3: Direct Path Check")
        print("-------------------------")
        
        // Test 3: Check direct paths
        if let bundlePath = Bundle.main.resourcePath {
            let possiblePaths = [
                "Assets.xcassets/front_image_mmr.imageset/front_image_mmr.tif",
                "Assets.xcassets/front_image.imageset/front_image_mmr.tiff",
                "front_image_mmr.tif",
                "front_image_mmr.tiff"
            ]
            
            for relativePath in possiblePaths {
                let fullPath = (bundlePath as NSString).appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: fullPath) {
                    print("✅ File exists: \(relativePath)")
                    if let image = UIImage(contentsOfFile: fullPath) {
                        print("   ✅ Loaded successfully - Size: \(image.size)")
                    } else {
                        print("   ❌ Failed to create UIImage")
                    }
                } else {
                    print("❌ File not found: \(relativePath)")
                }
            }
        }
        
        print("\nTest 4: List All Bundle Images")
        print("-------------------------------")
        
        // Test 4: List all images in bundle
        if let resourcePath = Bundle.main.resourcePath {
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                let imageExtensions = ["tif", "tiff", "png", "jpg", "jpeg"]
                let images = items.filter { item in
                    let lowercased = item.lowercased()
                    return imageExtensions.contains { ext in
                        lowercased.hasSuffix(".\(ext)")
                    }
                }
                
                if !images.isEmpty {
                    print("Found images in bundle root:")
                    for image in images {
                        print("  - \(image)")
                    }
                } else {
                    print("No images found in bundle root")
                }
            } catch {
                print("Error listing bundle contents: \(error)")
            }
        }
        
        print("\nTest 5: Asset Catalog Contents")
        print("-------------------------------")
        
        // Try to load Assets.car (compiled asset catalog)
        if let assetsPath = Bundle.main.path(forResource: "Assets", ofType: "car") {
            print("✅ Found Assets.car at: \(assetsPath)")
            // Note: Assets.car is compiled and not directly readable
            print("   (Asset catalog is compiled - images should be accessible via UIImage(named:))")
        } else {
            print("❌ Assets.car not found")
        }
        
        print("\n=== DIAGNOSTIC COMPLETE ===")
        print("===========================\n")
        
        // Provide recommendation
        print("RECOMMENDATION:")
        var foundImage = false
        
        if let _ = UIImage(named: "front_image_mmr") {
            print("✅ Use: UIImage(named: \"front_image_mmr\")")
            foundImage = true
        } else if let _ = UIImage(named: "front_image") {
            print("✅ Use: UIImage(named: \"front_image\")")
            foundImage = true
        } else if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tif"),
                  let _ = UIImage(contentsOfFile: url.path) {
            print("✅ Use: Bundle.main.url(forResource: \"front_image_mmr\", withExtension: \"tif\")")
            foundImage = true
        }
        
        if !foundImage {
            print("⚠️ Could not find a working method to load front_image_mmr.tif")
            print("   Please check that the file is properly added to the Xcode project")
        }
    }
    
    /// Get the first successfully loaded front_image_mmr
    static func loadFrontImage() -> UIImage? {
        // Try the most likely methods first
        if let image = UIImage(named: "front_image_mmr") {
            return image
        }
        
        if let image = UIImage(named: "front_image") {
            return image
        }
        
        if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tif"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        
        if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tiff"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        
        return nil
    }
}