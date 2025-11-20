# Camera Edge Detection Presets - Proposal

## Overview

This document proposes the implementation of two new Camera preset variants that replace the Line spectrogram visualization with real-time edge detection and audio-driven displacement effects.

## Requirements

### Version 1: Edge Detection with Raw Waveform Displacement
- Perform edge detection on each camera frame
- Identify edge pixels using a mask
- Apply outward displacement from screen center to edge pixels
- Displacement magnitude driven by raw waveform values (higher values = greater displacement)

### Version 2: Edge Detection with Spectrogram Band-Based Color Displacement
- Perform edge detection on each camera frame
- Identify edge pixels using a mask
- Apply outward displacement from screen center to edge pixels
- Displacement magnitude driven by spectrogram frequency bands
- Color mapping: lower bands → specific color range, higher bands → different color range

## Technical Approach

### 1. Camera Frame Capture

**Current State:**
- `CameraVisualizerPreset` uses `AVCaptureVideoPreviewLayer` for display
- No direct access to pixel buffers

**Proposed Solution:**
- Add `AVCaptureVideoDataOutput` to capture `CMSampleBuffer` frames
- Convert `CMSampleBuffer` → `CVPixelBuffer` → `MTLTexture`
- Use `CVMetalTextureCache` for efficient texture creation
- Maintain separate capture session for Metal processing vs. preview

**Performance Considerations:**
- Use `kCVPixelFormatType_32BGRA` for direct Metal compatibility
- Process frames at 30-60 FPS depending on device capability
- Use `AVCaptureVideoDataOutputSampleBufferDelegate` for frame callbacks
- Implement frame dropping if processing falls behind

### 2. Edge Detection Implementation

**Algorithm: Sobel Operator (GPU-optimized)**

The Sobel operator is ideal for real-time edge detection in Metal:
- Computationally efficient (3x3 convolution kernels)
- Parallelizable across all pixels
- Produces edge magnitude and direction

**Implementation:**
- Compute shader: `edgeDetectionCompute`
- Two-pass approach:
  1. Convert RGB to grayscale
  2. Apply Sobel X and Y kernels
  3. Calculate edge magnitude: `sqrt(Gx² + Gy²)`
  4. Threshold to create binary edge mask

**Sobel Kernels:**
```
Gx = [-1  0  1]    Gy = [-1 -2 -1]
     [-2  0  2]         [ 0  0  0]
     [-1  0  1]         [ 1  2  1]
```

**Performance Optimizations:**
- Use shared memory for kernel sampling (reduce texture reads)
- Process in 16x16 thread groups
- Use `half` precision where possible
- Downsample input if needed (e.g., 1080p → 720p for processing)

### 3. Outward Displacement from Center

**Displacement Vector Calculation:**
```
center = (0.5, 0.5)  // Normalized screen center
direction = normalize(pixelPosition - center)
displacement = direction * magnitude * scale
```

**Implementation:**
- Fragment shader samples edge mask texture
- If pixel is an edge (mask > threshold):
  - Calculate direction from center
  - Sample audio data for displacement magnitude
  - Calculate displaced UV coordinates
  - Sample camera texture at displaced position

**Edge Cases:**
- Clamp displaced UVs to [0, 1] to avoid sampling outside texture
- Consider edge wrapping vs. clamping behavior

### 4. Version 1: Raw Waveform Displacement

**Audio Data Mapping:**
- Use `rawAudioSamples` array
- Map pixel X position to sample index: `sampleIndex = (uv.x * sampleCount)`
- Use sample magnitude (absolute value) for displacement
- Normalize by max amplitude

**Displacement Formula:**
```
sampleValue = rawAudioSamples[sampleIndex]
normalizedAmplitude = abs(sampleValue) / maxAmplitude
displacementMagnitude = normalizedAmplitude * displacementScale
```

**Performance:**
- Pre-normalize waveform data on CPU
- Pass as buffer to shader (not texture, for faster access)
- Use linear interpolation for smooth mapping

### 5. Version 2: Spectrogram Band-Based Color Displacement

**Frequency Band Mapping:**
- Use `magnitudes` array (FFT frequency bins)
- Map pixel X position to frequency bin: `binIndex = (uv.x * magnitudeCount)`
- Use magnitude value for displacement
- Map frequency bin to color based on band ranges

**Color Mapping Strategy:**
- Low bands (0-33%): Red spectrum (red → orange → yellow)
- Mid bands (33-66%): Green spectrum (yellow → green → cyan)
- High bands (66-100%): Blue spectrum (cyan → blue → purple)

**Displacement Formula:**
```
magnitude = magnitudes[binIndex]
normalizedMag = magnitude / maxMagnitude
displacementMagnitude = normalizedMag * displacementScale
color = mapFrequencyToColor(binIndex / magnitudeCount)
```

**Color Calculation:**
```
bandPosition = binIndex / magnitudeCount  // [0, 1]
if (bandPosition < 0.33) {
    // Red to yellow
    color = mix(red, yellow, bandPosition / 0.33)
} else if (bandPosition < 0.66) {
    // Yellow to cyan
    color = mix(yellow, cyan, (bandPosition - 0.33) / 0.33)
} else {
    // Cyan to purple
    color = mix(cyan, purple, (bandPosition - 0.66) / 0.34)
}
```

### 6. Shader Architecture

**Compute Passes:**
1. `edgeDetectionCompute`: Convert camera frame → edge mask texture
2. `displacementCompute` (optional): Pre-calculate displacement map from audio

**Render Pass:**
- `edgeDisplaceFragment`: 
  - Sample edge mask
  - If edge pixel: calculate displacement, sample camera at displaced UV
  - Apply color (Version 2 only)
  - Output final pixel

**Texture Pipeline:**
```
Camera Frame (CVPixelBuffer)
    ↓
Camera Texture (MTLTexture)
    ↓
Edge Mask Texture (MTLTexture) [Compute]
    ↓
Final Output (MTLTexture) [Render]
```

### 7. Performance Optimizations

**Texture Management:**
- Reuse textures across frames (don't recreate)
- Use `MTLTextureUsage.shaderRead | .shaderWrite` for compute textures
- Use `MTLStorageMode.shared` for CPU-accessible textures if needed

**Compute Optimization:**
- Use optimal threadgroup sizes (16x16 for 2D)
- Minimize texture reads (use shared memory where possible)
- Process at lower resolution if needed (e.g., 720p instead of 1080p)

**Memory Management:**
- Use `CVMetalTextureCache` for efficient CVPixelBuffer → MTLTexture conversion
- Release textures when not needed
- Monitor memory pressure

**Frame Rate:**
- Target 30 FPS minimum, 60 FPS preferred
- Implement adaptive quality (reduce resolution if FPS drops)
- Skip frames if processing queue backs up

### 8. UI Controls

**Edge Detection Parameters:**
- `edgeThreshold`: Float (0.0 - 1.0) - Threshold for edge detection
- `edgeSensitivity`: Float (0.0 - 2.0) - Multiplier for Sobel magnitude
- `edgeBlur`: Float (0.0 - 1.0) - Optional blur before edge detection

**Displacement Parameters:**
- `displacementScale`: Float (0.0 - 1.0) - Overall displacement strength
- `displacementSmoothing`: Float (0.0 - 1.0) - Temporal smoothing factor

**Version 2 Specific:**
- `colorIntensity`: Float (0.0 - 2.0) - Color saturation multiplier
- `lowBandColor`: Color - Color for low frequency bands
- `highBandColor`: Color - Color for high frequency bands
- `bandSplitPoint`: Float (0.0 - 1.0) - Point where low/high bands split

**Audio Parameters:**
- `audioGain`: Float (0.0 - 2.0) - Audio input gain multiplier
- `audioSmoothing`: Float (0.0 - 1.0) - Temporal smoothing for audio

### 9. Implementation Structure

**New Files:**
- `Sources/AudioVisualizer/Presets/CameraEdgeDisplacePreset.swift` (Version 1)
- `Sources/AudioVisualizer/Presets/CameraEdgeColorDisplacePreset.swift` (Version 2)
- `Sources/AudioVisualizer/Shaders/Source/MSLCameraEdge.metal` (Shared shaders)

**Modified Files:**
- `Sources/AudioVisualizer/VisualizerPreset.swift` - Add new preset types
- `Sources/AudioVisualizer/Presets/CameraVisualizerPreset.swift` - Extract camera capture logic

**Shared Components:**
- `CameraTextureProvider`: Manages camera → Metal texture conversion
- `EdgeDetectionProcessor`: Manages edge detection compute pipeline

### 10. Potential Issues & Solutions

**Issue: Frame Rate Drops**
- Solution: Reduce processing resolution, optimize shaders, skip frames

**Issue: Memory Pressure**
- Solution: Use texture pools, release unused textures, monitor memory

**Issue: Audio/Video Synchronization**
- Solution: Use timestamps, implement frame dropping, smooth interpolation

**Issue: Edge Detection Too Sensitive/Not Sensitive Enough**
- Solution: Expose threshold controls, add adaptive thresholding

**Issue: Displacement Artifacts**
- Solution: Clamp UVs, use smooth interpolation, add temporal smoothing

**Issue: Color Banding (Version 2)**
- Solution: Use smooth color interpolation, dithering if needed

### 11. Testing Strategy

**Performance Testing:**
- Measure FPS on various devices (iPhone, iPad, Mac)
- Profile GPU/CPU usage
- Test memory usage over extended periods

**Visual Testing:**
- Test with various lighting conditions
- Test with different audio inputs (silence, music, speech)
- Verify edge detection quality
- Verify displacement smoothness

**Edge Cases:**
- No camera available
- Camera permission denied
- Audio input unavailable
- Rapid parameter changes

## Performance Targets

- **Frame Rate:** 30+ FPS on iPhone 12+, 60 FPS on iPhone 14+
- **Latency:** < 100ms from frame capture to display
- **Memory:** < 100MB additional memory usage
- **GPU Usage:** < 80% on target devices

## Next Steps

1. Review and refine this proposal
2. Create detailed implementation plan
3. Implement camera texture provider
4. Implement edge detection shaders
5. Implement displacement shaders
6. Integrate with preset system
7. Add UI controls
8. Performance testing and optimization
9. Documentation

