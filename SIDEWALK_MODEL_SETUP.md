# Sidewalk Detection Model Setup

## Current Implementation

The app now uses **semantic segmentation** for robust sidewalk detection instead of depth gradients.

## Option 1: Use Pre-trained Model (Recommended)

### Download DeepLabV3 or Similar Model

1. **DeepLabV3 (Pascal VOC)**
   - Download from: https://developer.apple.com/machine-learning/models/
   - File: `DeepLabV3.mlmodel`
   - Size: ~16MB
   - Classes: 21 classes including road/sidewalk

2. **DeepLabV3 (Cityscapes)** - Best for sidewalks
   - Better option for urban navigation
   - Classes include: road, sidewalk, person, car, etc.
   - Download from Core ML Model Zoo or convert from TensorFlow

3. **Road Segmentation Models**
   - Search "road segmentation Core ML"
   - Many available on GitHub

### Add Model to Project

1. Download `.mlmodel` file
2. Drag into Xcode project
3. Ensure "Target Membership" includes SmartCane
4. Xcode will automatically compile to `.mlmodelc`

### Model Requirements

- **Input**: Camera image (CVPixelBuffer)
- **Output**: Segmentation map with class indices
- **Classes needed**: Road (class 0), Sidewalk (class 1)

## Option 2: Use Built-in Vision (Current Fallback)

The app includes a fallback that uses:
- Apple's Vision framework horizon detection
- Combined with depth analysis
- No external model needed
- Less accurate but functional

## Option 3: Simple Heuristic (Quick Start)

For immediate testing without a model:

The current implementation will use horizon detection + depth analysis when no model is found.

## Configuring Class Indices

In `SemanticSidewalkDetector.swift`, update these based on your model:

```swift
private let roadClassIndices: Set<Int> = [0, 1]  // Adjust for your model
private let sidewalkClassIndex = 1  // Typically sidewalk class
```

### Common Class Mappings

**Cityscapes Model:**
- 0: road
- 1: sidewalk
- 11: person
- 13: car

**PASCAL VOC (DeepLabV3):**
- 0: background
- 15: person
- (no explicit road/sidewalk - less ideal)

## Testing Without Model

The app will run without a model using:
1. Horizon detection for orientation
2. Depth analysis for nearby surfaces
3. Conservative boundary estimation

## Recommended Quick Start

1. **Download DeepLabV3Int8LUT.mlmodel** from Apple
   ```
   https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3Int8LUT.mlmodel
   ```

2. Add to Xcode project

3. Run app - segmentation will automatically activate

## Performance Notes

- Segmentation runs every 300ms (not every frame)
- Results are cached and smoothed
- Minimal impact on obstacle detection performance
- GPU-accelerated via Core ML

## Troubleshooting

**"No segmentation model found"**
- Normal - app uses fallback mode
- Add .mlmodel file to enable segmentation

**Model not loading**
- Check Target Membership in Xcode
- Verify model file extension (.mlmodel)
- Check Xcode build logs

**Poor detection**
- Adjust `roadClassIndices` for your model
- Tune `temporalSmoothingFactor` (0.7 default)
- Increase `processingInterval` if too slow

## Future: Custom Model

For best results, train a custom model on:
- Sidewalk/curb images from your environment
- Use TensorFlow or PyTorch
- Convert to Core ML format
- Achieves >90% accuracy for specific use case
