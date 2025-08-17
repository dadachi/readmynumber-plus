# Three-Layer Composite Residence Card Implementation

## Overview

The `createCompositeResidenceCard` function now implements a sophisticated three-layer compositing system:

1. **Base Layer**: `front_image_background.png` (pre-processed transparent background)
2. **Middle Layer**: `transparentFrontImage` (processed ResidenceCardData.frontImage with white background removed)
3. **Top Layer**: `faceImage` (ResidenceCardData.faceImage positioned correctly)

## Architecture

### Three-Layer Compositing Flow

```
1. Load front_image_background.png
   ↓
2. Process ResidenceCardData.frontImage (TIFF → transparent)
   ↓
3. Convert ResidenceCardData.faceImage (JPEG2000 → UIImage)
   ↓
4. Composite all three layers:
   - Draw background (transparent base)
   - Draw transparent front image on top
   - Draw face at calculated position
   ↓
5. Return final composite with transparency
```

### Fallback Mechanism

If `front_image_background.png` is not available:
- Falls back to two-layer compositing (original functionality)
- Processes frontImage to remove white background
- Composites face directly onto transparent frontImage

## Code Structure

### Main Function: `createCompositeResidenceCard`

```swift
static func createCompositeResidenceCard(from cardData: ResidenceCardData, tolerance: CGFloat = 0.08) -> UIImage?
```

**Three-Layer Path:**
1. `UIImage(named: "front_image_background")` - Load base layer
2. `convertTIFFDataToUIImage(data: cardData.frontImage)` - Process front image
3. `makeBackgroundTransparent(from:tolerance:backgroundColor:)` - Remove white background
4. `convertImageDataToUIImage(data: cardData.faceImage)` - Process face image
5. `createThreeLayerComposite(backgroundImage:transparentFrontImage:faceImage:)` - Combine layers

**Fallback Path:**
1. `createTwoLayerComposite(from:tolerance:)` - Original two-layer logic

### Helper Functions

#### `createThreeLayerComposite`
```swift
private static func createThreeLayerComposite(
    backgroundImage: UIImage,
    transparentFrontImage: UIImage,
    faceImage: UIImage
) -> UIImage?
```

- **Canvas Size**: Uses background image dimensions
- **Layer 1**: Draws background image at full size
- **Layer 2**: Draws transparent front image at full size (overlays content)
- **Layer 3**: Draws face image at calculated position

#### `createTwoLayerComposite`
```swift
private static func createTwoLayerComposite(from cardData: ResidenceCardData, tolerance: CGFloat) -> UIImage?
```

- Fallback function maintaining original behavior
- Used when `front_image_background.png` not available

#### `calculateFacePosition`
```swift
private static func calculateFacePosition(for cardSize: CGSize) -> CGRect
```

- **Position**: 72% width, 35% height from top-left
- **Size**: 22% width, 30% height of card
- **Shared Logic**: Used by both three-layer and two-layer compositing

## Benefits of Three-Layer Approach

### 1. **Clean Background**
- Uses pre-processed `front_image_background.png` with perfect transparency
- No artifacts from automatic white background removal
- Consistent transparent areas

### 2. **Accurate Content**
- Uses actual ResidenceCardData.frontImage for authentic card content
- Preserves all card details and text
- Maintains data integrity

### 3. **Precise Positioning**
- Face image positioned using residence card specifications
- Consistent placement across different card images
- Proper scaling and proportions

### 4. **Robust Fallback**
- Graceful degradation if background image unavailable
- Maintains compatibility with existing functionality
- No breaking changes to API

## Usage Examples

### Basic Usage
```swift
// Three-layer compositing (if front_image_background.png available)
let composite = ImageProcessor.createCompositeResidenceCard(from: cardData)
```

### With Custom Tolerance
```swift
// Adjust background removal sensitivity
let composite = ImageProcessor.createCompositeResidenceCard(from: cardData, tolerance: 0.05)
```

### Complete Processing and Save
```swift
let result = ImageProcessor.processAndSaveResidenceCard(
    from: cardData,
    fileName: "three_layer_composite",
    tolerance: 0.08
)
```

## Technical Details

### Layer Drawing Order
```swift
// Layer 1: Background (transparent base)
backgroundImage.draw(in: CGRect(origin: .zero, size: canvasSize))

// Layer 2: Transparent front image (card content)
transparentFrontImage.draw(in: CGRect(origin: .zero, size: canvasSize))

// Layer 3: Face image (positioned)
faceImage.draw(in: faceRect)
```

### Image Format Handling
- **Background**: PNG with transparency (from Asset Catalog)
- **Front Image**: TIFF → UIImage → Transparent UIImage
- **Face Image**: JPEG2000 → UIImage
- **Output**: PNG with transparency preserved

### Performance Characteristics
- **Three-Layer**: Slightly more processing (loads additional background image)
- **Two-Layer**: Original performance (fallback)
- **Memory**: Efficient cleanup with `defer { UIGraphicsEndImageContext() }`
- **Quality**: No quality loss in compositing process

## Error Handling and Logging

### Debug Output
```
✅ Three-Layer Success:
"Loaded front_image_background.png as base - Size: (width, height)"
"Converted frontImage from TIFF - Size: (width, height)"
"Made frontImage background transparent"
"Converted faceImage - Size: (width, height)"
"Drew background layer - Size: (width, height)"
"Drew transparent front image layer"
"Drew face image at position: (x, y, width, height)"
"Successfully created three-layer composite residence card"

⚠️ Fallback to Two-Layer:
"Failed to load front_image_background.png from Asset Catalog"
"Falling back to two-layer compositing..."
[Two-layer processing messages]
```

### Error Scenarios
1. **Background Image Missing**: Falls back to two-layer compositing
2. **TIFF Conversion Failure**: Returns nil, logs error
3. **Face Image Conversion Failure**: Returns nil, logs error
4. **Compositing Failure**: Returns nil, logs error

## Integration with ResidenceCardDetailView

### UI Updates
- **Same Button**: "合成・透明化" triggers three-layer compositing
- **Same Display**: Checkerboard background shows transparency
- **Same Export**: Saves as PNG with transparency preserved

### User Experience
- **Transparent**: Better background quality with three-layer approach
- **Seamless**: Automatic fallback if background image unavailable
- **Consistent**: Same interface regardless of compositing method

## Asset Requirements

### Required Asset
- **`front_image_background.png`**: Pre-processed background with transparency
- **Location**: Asset Catalog as "front_image_background"
- **Format**: PNG with alpha channel
- **Purpose**: Clean transparent base layer

### Optional Assets (for fallback)
- ResidenceCardData.frontImage (TIFF) - always available from card data
- ResidenceCardData.faceImage (JPEG2000) - always available from card data

## Testing

### Test Coverage
1. **`testThreeLayerVsTwoLayerCompositing`**: Verifies both paths work
2. **`testBackgroundImageLoadingBehavior`**: Checks if background image available
3. **`testResidenceCardDataCompositeImage`**: Tests complete functionality
4. **`testProcessAndSaveResidenceCard`**: Tests file saving

### Test Behavior
- **With Background Image**: Uses three-layer compositing
- **Without Background Image**: Falls back to two-layer compositing
- **Both Cases**: Should produce valid transparent PNG output

## File Output

### Export Files
1. **`residence_card_front.jpg`**: Original front image
2. **`residence_card_face.jpg`**: Face image  
3. **`residence_card_composite_transparent.png`**: **Three-layer composite** with transparent background

### Quality Comparison
- **Three-Layer**: Clean transparent background + authentic content + positioned face
- **Two-Layer**: Processed transparent background + positioned face
- **Both**: PNG format preserves transparency

## Best Practices

### Implementation
```swift
// Always check result
guard let composite = ImageProcessor.createCompositeResidenceCard(from: cardData) else {
    // Handle failure appropriately
    return
}

// Use default tolerance unless specific requirements
let composite = ImageProcessor.createCompositeResidenceCard(from: cardData) // tolerance: 0.08
```

### Asset Management
- **Include** `front_image_background.png` in Asset Catalog for best quality
- **Test** fallback behavior when background image unavailable
- **Verify** background image has proper transparency

### Performance
- **Cache** background image if processing multiple cards
- **Monitor** memory usage with large card images
- **Use** appropriate tolerance values for background removal

This three-layer approach provides the highest quality composite residence card images while maintaining backward compatibility and robust error handling.