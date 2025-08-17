# Transparent Background Processing for front_image_mmr.tif

This document shows how to use the transparent background functionality implemented in the `ImageProcessor` class.

## Overview

The `ImageProcessor` class provides several methods to remove white backgrounds from the front_image_mmr.tif file and convert them to transparent PNG images.

## Basic Usage

### 1. Load and Process Image with Transparent Background

```swift
// Simple white background removal
if let transparentImage = ImageProcessor.loadFrontImageWithTransparentBackground() {
    // Use the image with transparent background
    imageView.image = transparentImage
}

// Or load any image and remove white background
if let originalImage = UIImage(named: "front_image_mmr") {
    let transparentImage = ImageProcessor.removeWhiteBackground(from: originalImage, tolerance: 0.08)
    // Use transparentImage
}
```

### 2. Adjust Tolerance for Better Results

```swift
// Strict tolerance (removes only pure white)
let strictImage = ImageProcessor.removeWhiteBackground(from: image, tolerance: 0.01)

// Lenient tolerance (removes near-white colors)
let lenientImage = ImageProcessor.removeWhiteBackground(from: image, tolerance: 0.2)

// Default tolerance (good balance)
let defaultImage = ImageProcessor.removeWhiteBackground(from: image) // tolerance: 0.08
```

### 3. Advanced Background Removal with Edge Detection

```swift
// Use advanced algorithm that preserves edges better
let advancedImage = ImageProcessor.removeBackgroundAdvanced(
    from: originalImage,
    cornerTolerance: 0.1,
    edgeThreshold: 0.3
)
```

### 4. Create Before/After Preview

```swift
if let original = UIImage(named: "front_image_mmr"),
   let transparent = ImageProcessor.removeWhiteBackground(from: original) {
    
    let preview = ImageProcessor.createBeforeAfterPreview(
        originalImage: original,
        transparentImage: transparent
    )
    
    // Show side-by-side comparison
    previewImageView.image = preview
}
```

### 5. Export as PNG (Preserves Transparency)

```swift
if let transparentImage = ImageProcessor.loadFrontImageWithTransparentBackground() {
    // Convert to PNG data
    let pngData = ImageProcessor.convertToPNGData(transparentImage)
    
    // Save to Documents directory
    if let data = pngData {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent("transparent_front_image.png")
        try? data.write(to: filePath)
    }
}
```

## UI Integration

The app includes a dedicated "透明背景" (Transparent Background) tab that provides:

- **Interactive tolerance adjustment** with slider control
- **Real-time preview** showing before/after comparison
- **Visual transparency** with checkerboard pattern background
- **Export functionality** to save as PNG

### Using the Test View

Navigate to the "透明背景" tab in the app to:

1. **Adjust tolerance**: Use the slider to find the optimal tolerance value
2. **Process image**: Tap "Process Image" to apply background removal
3. **Preview results**: See side-by-side comparison with original
4. **Export PNG**: Save the transparent image to your device

## Technical Details

### Tolerance Values
- **0.001 - 0.05**: Very strict, removes only pure white
- **0.05 - 0.15**: Balanced, good for most images (recommended)
- **0.15 - 0.3**: Lenient, removes off-white and light gray

### Image Quality
- Original TIFF format is preserved during processing
- Final output as PNG maintains transparency
- No quality loss during background removal

### Performance
- Processing is done on background queue
- Typical processing time: < 1 second for standard images
- Memory efficient with proper cleanup

## Use Cases

1. **Document Processing**: Remove white backgrounds from scanned documents
2. **UI Design**: Create transparent overlays for app interfaces
3. **Image Editing**: Prepare images for compositing with other backgrounds
4. **Export/Sharing**: Save high-quality transparent PNGs

## Error Handling

The functions return `nil` if processing fails. Always check for `nil` results:

```swift
guard let transparentImage = ImageProcessor.removeWhiteBackground(from: originalImage) else {
    print("Failed to process image")
    return
}

// Proceed with transparent image
```

## Testing

Run the included tests to verify functionality:

```bash
xcodebuild test -scheme "readmynumber" -only-testing:readmynumberTests/FrontImageLoadingTests/testTransparentBackgroundProcessing
```

The tests verify:
- Basic white background removal
- Different tolerance values
- PNG conversion with transparency
- Before/after preview generation
- Advanced edge-preserving algorithms