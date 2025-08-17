//
//  TransparentBackgroundTestView.swift
//  readmynumber
//
//  Created by Claude Code on 2025/08/17.
//

import SwiftUI

struct TransparentBackgroundTestView: View {
    @State private var originalImage: UIImage?
    @State private var transparentImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var isProcessing = false
    @State private var tolerance: Double = 0.08
    @State private var showingExportSheet = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text("front_image_mmr.tif Background Removal")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    Text("Remove white background from front_image_mmr.tif")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Tolerance Control
                    VStack(alignment: .leading, spacing: 8) {
                        Text("White Background Tolerance: \(tolerance, specifier: "%.3f")")
                            .font(.headline)
                        
                        HStack {
                            Text("0.001")
                                .font(.caption)
                            Slider(value: $tolerance, in: 0.001...0.3, step: 0.001)
                            Text("0.3")
                                .font(.caption)
                        }
                        
                        Text("Lower values = more precise white removal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Action Buttons
                    HStack(spacing: 16) {
                        Button(action: runDiagnostic) {
                            HStack {
                                Image(systemName: "stethoscope")
                                Text("Diagnose")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button(action: loadAndProcessImage) {
                            HStack {
                                Image(systemName: "photo")
                                Text("Process")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(originalImage != nil ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isProcessing || originalImage == nil)
                        
                        Button(action: exportTransparentImage) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export PNG")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(transparentImage != nil ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(transparentImage == nil)
                    }
                    .padding(.horizontal)
                    
                    if isProcessing {
                        ProgressView("Processing...")
                            .padding()
                    }
                    
                    // Preview Images
                    if let preview = previewImage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before & After Comparison")
                                .font(.headline)
                            
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .background(Color.white)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        }
                        .padding()
                    }
                    
                    // Individual Images
                    HStack(spacing: 16) {
                        // Original Image
                        VStack {
                            Text("Original (front_image_mmr.tif)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            if let original = originalImage {
                                Image(uiImage: original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .shadow(radius: 1)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 200)
                                    .cornerRadius(8)
                                    .overlay(
                                        Text("No Image")
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                        
                        // Transparent Image
                        VStack {
                            Text("Transparent")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            ZStack {
                                // Checkerboard background to show transparency
                                CheckerboardView()
                                    .frame(height: 200)
                                    .cornerRadius(8)
                                
                                if let transparent = transparentImage {
                                    Image(uiImage: transparent)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                        .cornerRadius(8)
                                } else {
                                    Text("No Image")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Info note
                    Text("Image Source: front_image_mmr.tif from Asset Catalog")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top)
                    
                    Spacer()
                }
            }
            .navigationTitle("front_image_mmr.tif")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadOriginalImage()
            }
            .alert("Result", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingExportSheet) {
                if let transparentImage = transparentImage,
                   let pngData = ImageProcessor.convertToPNGData(transparentImage) {
                    ShareSheet(activityItems: [pngData])
                }
            }
        }
    }
    
    private func loadOriginalImage() {
        // Try multiple approaches to load front_image_mmr.tif
        
        // 1. Try loading from Asset Catalog with exact name
        originalImage = UIImage(named: "front_image_mmr")
        
        // 2. Try loading from front_image asset (which might contain the TIFF)
        if originalImage == nil {
            originalImage = UIImage(named: "front_image")
        }
        
        // 3. Try direct bundle loading with .tif extension
        if originalImage == nil {
            if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tif") {
                originalImage = UIImage(contentsOfFile: url.path)
            }
        }
        
        // 4. Try direct bundle loading with .tiff extension
        if originalImage == nil {
            if let url = Bundle.main.url(forResource: "front_image_mmr", withExtension: "tiff") {
                originalImage = UIImage(contentsOfFile: url.path)
            }
        }
        
        if originalImage != nil {
            print("Successfully loaded front_image_mmr: \(originalImage!.size)")
        } else {
            print("Failed to load front_image_mmr.tif/tiff")
        }
    }
    
    private func loadAndProcessImage() {
        // First ensure we have the front_image_mmr.tif loaded
        if originalImage == nil {
            loadOriginalImage()
        }
        
        guard let original = originalImage else {
            alertMessage = "Failed to load front_image_mmr.tif from assets"
            showAlert = true
            return
        }
        
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Process the image with current tolerance
            let transparent = ImageProcessor.removeWhiteBackground(from: original, tolerance: tolerance)
            
            // Create preview if successful
            let preview = transparent != nil ? 
                ImageProcessor.createBeforeAfterPreview(originalImage: original, transparentImage: transparent!) : nil
            
            DispatchQueue.main.async {
                self.transparentImage = transparent
                self.previewImage = preview
                self.isProcessing = false
                
                if transparent != nil {
                    self.alertMessage = "Background removal completed successfully!"
                } else {
                    self.alertMessage = "Failed to process image. Try adjusting the tolerance."
                }
                self.showAlert = true
            }
        }
    }
    
    private func exportTransparentImage() {
        guard transparentImage != nil else { return }
        showingExportSheet = true
    }
    
    private func runDiagnostic() {
        // Run diagnostic to find the image
        ImageLoadingDiagnostic.runDiagnostic()
        
        // Try to load using diagnostic method
        if let image = ImageLoadingDiagnostic.loadFrontImage() {
            originalImage = image
            alertMessage = "Diagnostic complete! Image loaded successfully.\nSize: \(image.size)"
        } else {
            alertMessage = "Diagnostic complete. Check console for details.\nCould not load front_image_mmr.tif"
        }
        showAlert = true
    }
}

// Checkerboard pattern to visualize transparency
struct CheckerboardView: View {
    let checkSize: CGFloat = 10
    
    var body: some View {
        GeometryReader { geometry in
            let numX = Int(ceil(geometry.size.width / checkSize))
            let numY = Int(ceil(geometry.size.height / checkSize))
            
            VStack(spacing: 0) {
                ForEach(0..<numY, id: \.self) { y in
                    HStack(spacing: 0) {
                        ForEach(0..<numX, id: \.self) { x in
                            Rectangle()
                                .fill(checkColor(x: x, y: y))
                                .frame(width: checkSize, height: checkSize)
                        }
                    }
                }
            }
        }
    }
    
    private func checkColor(x: Int, y: Int) -> Color {
        let isEvenX = x % 2 == 0
        let isEvenY = y % 2 == 0
        let useLight = (isEvenX && isEvenY) || (!isEvenX && !isEvenY)
        return useLight ? Color.gray.opacity(0.2) : Color.gray.opacity(0.4)
    }
}

// Note: ShareSheet is already defined in CertificateDetailView.swift

#Preview {
    TransparentBackgroundTestView()
}