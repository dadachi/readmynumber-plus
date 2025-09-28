//
//  FrontImageUsageExample.swift
//  Example of using front_image_mmr.tif with transparent background
//

import UIKit
import SwiftUI

// MARK: - Example 1: Simple UIKit Usage
class FrontImageViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var toleranceSlider: UISlider!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        processFrontImage()
    }
    
    func processFrontImage() {
        // Method 1: Use the convenience function (recommended)
        if let transparentImage = ImageProcessor.processFrontImageMMR() {
            imageView.image = transparentImage
            print("Successfully processed front_image_mmr.tif")
        }
        
        // Method 2: Process with custom tolerance
        let customTolerance: CGFloat = 0.1
        if let transparentImage = ImageProcessor.loadFrontImageWithTransparentBackground(tolerance: customTolerance) {
            imageView.image = transparentImage
        }
        
        // Method 3: Load and process manually
        if let originalImage = UIImage(named: "front_image_mmr") {
            let transparentImage = ImageProcessor.removeWhiteBackground(from: originalImage, tolerance: 0.08)
            imageView.image = transparentImage
        }
    }
    
    @IBAction func toleranceChanged(_ sender: UISlider) {
        let tolerance = CGFloat(sender.value)
        
        // Reprocess front_image_mmr.tif with new tolerance
        if let transparentImage = ImageProcessor.loadFrontImageWithTransparentBackground(tolerance: tolerance) {
            imageView.image = transparentImage
        }
    }
    
    @IBAction func exportImage(_ sender: UIButton) {
        guard let image = imageView.image else { return }
        
        // Convert to PNG to preserve transparency
        if let pngData = ImageProcessor.convertToPNGData(image) {
            // Save to documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filePath = documentsPath.appendingPathComponent("front_image_mmr_transparent.png")
            
            do {
                try pngData.write(to: filePath)
                print("Saved transparent image to: \(filePath)")
            } catch {
                print("Error saving: \(error)")
            }
        }
    }
}

// MARK: - Example 2: SwiftUI Usage
struct FrontImageView: View {
    @State private var transparentImage: UIImage?
    @State private var tolerance: Double = 0.08
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("front_image_mmr.tif Processing")
                .font(.title2)
                .bold()
            
            // Display the processed image
            if let image = transparentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .background(CheckerboardPattern())
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 300)
                    .overlay(
                        Text("Loading front_image_mmr.tif...")
                            .foregroundColor(.gray)
                    )
            }
            
            // Tolerance control
            VStack(alignment: .leading) {
                Text("Tolerance: \(tolerance, specifier: "%.3f")")
                Slider(value: $tolerance, in: 0.01...0.3)
                    .onChange(of: tolerance) { _ in
                        processFrontImage()
                    }
            }
            .padding(.horizontal)
            
            // Process button
            Button(action: processFrontImage) {
                Label("Process front_image_mmr.tif", systemImage: "photo")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isProcessing)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .onAppear {
            processFrontImage()
        }
    }
    
    private func processFrontImage() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Process front_image_mmr.tif with current tolerance
            let processed = ImageProcessor.loadFrontImageWithTransparentBackground(tolerance: tolerance)
            
            DispatchQueue.main.async {
                self.transparentImage = processed
                self.isProcessing = false
            }
        }
    }
}

// Checkerboard pattern to show transparency
struct CheckerboardPattern: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let size: CGFloat = 10
                let rows = Int(geometry.size.height / size)
                let columns = Int(geometry.size.width / size)
                
                for row in 0..<rows {
                    for column in 0..<columns {
                        if (row + column) % 2 == 0 {
                            let rect = CGRect(
                                x: CGFloat(column) * size,
                                y: CGFloat(row) * size,
                                width: size,
                                height: size
                            )
                            path.addRect(rect)
                        }
                    }
                }
            }
            .fill(Color.gray.opacity(0.2))
        }
    }
}

// MARK: - Example 3: Batch Processing
class FrontImageBatchProcessor {
    
    /// Process front_image_mmr.tif with multiple tolerance values
    static func batchProcess() {
        let tolerances: [CGFloat] = [0.05, 0.08, 0.10, 0.15, 0.20]
        var results: [(tolerance: CGFloat, image: UIImage)] = []
        
        for tolerance in tolerances {
            if let processed = ImageProcessor.loadFrontImageWithTransparentBackground(tolerance: tolerance) {
                results.append((tolerance, processed))
                print("✅ Processed front_image_mmr.tif with tolerance: \(tolerance)")
            } else {
                print("❌ Failed to process with tolerance: \(tolerance)")
            }
        }
        
        // Save all results
        saveResults(results)
    }
    
    static func saveResults(_ results: [(tolerance: CGFloat, image: UIImage)]) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        for (tolerance, image) in results {
            if let pngData = ImageProcessor.convertToPNGData(image) {
                let filename = "front_image_mmr_tol_\(Int(tolerance * 100)).png"
                let filePath = documentsPath.appendingPathComponent(filename)
                
                do {
                    try pngData.write(to: filePath)
                    print("Saved: \(filename)")
                } catch {
                    print("Error saving \(filename): \(error)")
                }
            }
        }
    }
}

// MARK: - Example 4: Integration with RDCDetailView
extension RDCDetailView {
    
    /// Replace white background in front image with transparency
    func processFrontImageWithTransparency() -> UIImage? {
        // Use the specific front_image_mmr.tif processor
        return ImageProcessor.processFrontImageMMR()
    }
    
    /// Display front image with transparent background
    func displayTransparentFrontImage(in imageView: UIImageView) {
        if let transparentImage = processFrontImageWithTransparency() {
            // Set the image with transparent background
            imageView.image = transparentImage
            
            // Optional: Add a pattern background to show transparency
            imageView.backgroundColor = UIColor(patternImage: createCheckerboardPattern())
        }
    }
    
    private func createCheckerboardPattern() -> UIImage {
        let size = CGSize(width: 20, height: 20)
        UIGraphicsBeginImageContext(size)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        context.setFillColor(UIColor.lightGray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
        
        let pattern = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return pattern
    }
}

// MARK: - Preview
#Preview {
    FrontImageView()
}