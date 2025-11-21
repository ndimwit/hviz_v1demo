# Camera Edge Detection Presets - Implementation Plan

## Overview

This document outlines the detailed implementation plan for two new Camera preset variants that perform real-time edge detection and audio-driven displacement effects.

## Architecture Review

### Current State
- `CameraVisualizerPreset` uses `AVCaptureVideoPreviewLayer` for display only
- No access to pixel buffers for Metal processing
- MSL presets follow pattern: Preset → MetalView → Coordinator with Metal setup
- Environment keys used for parameter control (e.g., `mslDisplaceScale`, `mslShaderOpacity`)

### Required Changes

1. **Camera Texture Provider**: Extract camera capture logic to provide Metal textures
2. **Edge Detection Shader**: Sobel operator compute shader
3. **Displacement Shaders**: Two fragment shaders (waveform-based and spectrogram-based)
4. **New Presets**: Two new preset implementations
5. **UI Controls**: Environment keys and parameter controls

## Implementation Steps

### Step 1: Create Camera Texture Provider

**File**: `Sources/AudioVisualizer/CameraTextureProvider.swift`

**Purpose**: Manages camera capture and converts frames to Metal textures

**Key Components**:
- `AVCaptureVideoDataOutput` for frame capture
- `CVMetalTextureCache` for efficient texture creation
- Delegate pattern to notify when new texture is available
- Thread-safe texture access

**Interface**:
```swift
class CameraTextureProvider: NSObject {
    var currentTexture: MTLTexture? { get }
    var onNewFrame: ((MTLTexture) -> Void)?
    func startCapture(device: MTLDevice) -> Bool
    func stopCapture()
}
```

**Implementation Notes**:
- Use `kCVPixelFormatType_32BGRA` for Metal compatibility
- Process frames on background queue
- Use `CVMetalTextureCacheCreateTextureFromImage` for conversion
- Handle frame dropping if processing lags

### Step 2: Create Edge Detection Shader

**File**: `Sources/AudioVisualizer/Shaders/Source/MSLCameraEdge.metal`

**Compute Shader**: `edgeDetectionCompute`

**Algorithm**:
1. Convert RGB to grayscale: `luminance = 0.299*R + 0.587*G + 0.114*B`
2. Apply Sobel X kernel: `Gx = -1*TL + 1*TR - 2*ML + 2*MR - 1*BL + 1*BR`
3. Apply Sobel Y kernel: `Gy = -1*TL - 2*TM - 1*TR + 1*BL + 2*BM + 1*BR`
4. Calculate magnitude: `magnitude = sqrt(Gx² + Gy²)`
5. Apply threshold: `edge = step(threshold, magnitude)`

**Parameters**:
- `edgeThreshold`: Float (0.0 - 1.0)
- `edgeSensitivity`: Float (0.0 - 2.0) - multiplier for magnitude

**Performance**:
- Use 16x16 thread groups
- Sample neighbors using texture reads (no shared memory needed for simplicity)
- Output to single-channel texture (R channel only)

### Step 3: Create Displacement Shaders

**File**: `Sources/AudioVisualizer/Shaders/Source/MSLCameraEdge.metal`

#### Version 1: Waveform Displacement Fragment Shader

**Function**: `cameraEdgeWaveformFragment`

**Logic**:
1. Sample edge mask texture
2. If edge pixel (mask > threshold):
   - Calculate direction from center: `dir = normalize(uv - 0.5)`
   - Map UV.x to sample index: `index = uv.x * sampleCount`
   - Get waveform value: `value = rawAudioSamples[index]`
   - Calculate displacement: `displacement = dir * abs(value) * scale`
   - Sample camera texture at displaced UV: `sample(cameraTexture, uv + displacement)`
3. Else: sample camera texture normally

**Parameters**:
- `displacementScale`: Float (0.0 - 1.0)
- `edgeThreshold`: Float (0.0 - 1.0)
- `rawAudioSamples`: device float* buffer
- `sampleCount`: uint
- `maxAmplitude`: float

#### Version 2: Spectrogram Color Displacement Fragment Shader

**Function**: `cameraEdgeColorFragment`

**Logic**:
1. Sample edge mask texture
2. If edge pixel (mask > threshold):
   - Calculate direction from center: `dir = normalize(uv - 0.5)`
   - Map UV.x to frequency bin: `binIndex = uv.x * magnitudeCount`
   - Get magnitude: `magnitude = magnitudes[binIndex]`
   - Calculate displacement: `displacement = dir * (magnitude / maxMagnitude) * scale`
   - Map frequency to color:
     - Low bands (0-33%): Red → Yellow
     - Mid bands (33-66%): Yellow → Cyan
     - High bands (66-100%): Cyan → Purple
   - Sample camera texture at displaced UV
   - Multiply by frequency color
3. Else: sample camera texture normally

**Parameters**:
- `displacementScale`: Float (0.0 - 1.0)
- `edgeThreshold`: Float (0.0 - 1.0)
- `magnitudes`: device float* buffer
- `magnitudeCount`: uint
- `maxMagnitude`: float
- `colorIntensity`: Float (0.0 - 2.0)

### Step 4: Create Preset Implementations

#### Version 1: Camera Edge Waveform Preset

**File**: `Sources/AudioVisualizer/Presets/CameraEdgeWaveformPreset.swift`

**Structure**:
- Similar to `MSLDisplacePreset` pattern
- Uses `CameraTextureProvider` for camera frames
- Edge detection compute pass
- Waveform displacement fragment pass
- Environment keys for parameters

**Key Methods**:
- `makeView()`: Returns `CameraEdgeWaveformMetalView`
- Coordinator manages Metal resources and rendering

#### Version 2: Camera Edge Color Preset

**File**: `Sources/AudioVisualizer/Presets/CameraEdgeColorPreset.swift`

**Structure**:
- Similar to Version 1
- Uses color displacement fragment shader
- Additional color parameters

### Step 5: Add Environment Keys

**Files**:
- `Sources/AudioVisualizer/CameraEdgeParametersKey.swift`

**Keys**:
- `edgeThreshold`: Float (default: 0.1)
- `edgeSensitivity`: Float (default: 1.0)
- `cameraEdgeDisplacementScale`: Float (default: 0.2)
- `cameraEdgeColorIntensity`: Float (default: 1.0) - Version 2 only

### Step 6: Update VisualizerPreset Enum

**File**: `Sources/AudioVisualizer/VisualizerPreset.swift`

**Changes**:
- Add `cameraEdgeWaveform` and `cameraEdgeColor` cases
- Add to `defaultPresets` or create new category
- Add display names
- Add preset instances

### Step 7: Update UI Controls

**File**: `Sources/AudioVisualizer/AudioVisualizerView.swift`

**Changes**:
- Add new parameter cases to `ControlParameter` enum
- Add parameter visibility logic
- Add UI controls for new parameters

## Implementation Details

### Camera Texture Provider Implementation

```swift
class CameraTextureProvider: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?
    private let textureQueue = DispatchQueue(label: "camera.texture.queue")
    private var device: MTLDevice?
    
    var onNewFrame: ((MTLTexture) -> Void)?
    
    func startCapture(device: MTLDevice) -> Bool {
        // Setup CVMetalTextureCache
        // Setup AVCaptureSession with AVCaptureVideoDataOutput
        // Start session
    }
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didOutput sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        // Convert CMSampleBuffer to MTLTexture
        // Update currentTexture
        // Call onNewFrame callback
    }
}
```

### Edge Detection Compute Shader

```metal
kernel void edgeDetectionCompute(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> edgeTexture [[texture(1)]],
    constant float& threshold [[buffer(0)]],
    constant float& sensitivity [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Sobel edge detection implementation
}
```

### Displacement Fragment Shaders

```metal
fragment float4 cameraEdgeWaveformFragment(
    VertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> edgeTexture [[texture(1)]],
    device const float* rawAudioSamples [[buffer(0)]],
    constant uint& sampleCount [[buffer(1)]],
    constant float& maxAmplitude [[buffer(2)]],
    constant float& displacementScale [[buffer(3)]],
    constant float& edgeThreshold [[buffer(4)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Waveform-based displacement
}

fragment float4 cameraEdgeColorFragment(
    VertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> edgeTexture [[texture(1)]],
    device const float* magnitudes [[buffer(0)]],
    constant uint& magnitudeCount [[buffer(1)]],
    constant float& maxMagnitude [[buffer(2)]],
    constant float& displacementScale [[buffer(3)]],
    constant float& edgeThreshold [[buffer(4)]],
    constant float& colorIntensity [[buffer(5)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Spectrogram-based color displacement
}
```

## Performance Considerations

### Optimization Strategies

1. **Texture Resolution**: Process at 720p instead of 1080p if needed
2. **Frame Dropping**: Skip frames if processing queue backs up
3. **Thread Groups**: Use optimal sizes (16x16 for 2D)
4. **Texture Reuse**: Reuse textures across frames
5. **Memory Management**: Use `CVMetalTextureCache` for efficient conversion

### Performance Targets

- **Frame Rate**: 30+ FPS on iPhone 12+, 60 FPS on iPhone 14+
- **Latency**: < 100ms from capture to display
- **Memory**: < 100MB additional usage

## Testing Strategy

1. **Unit Tests**: Test edge detection accuracy
2. **Performance Tests**: Measure FPS on various devices
3. **Visual Tests**: Verify edge detection quality and displacement smoothness
4. **Edge Cases**: No camera, permission denied, audio unavailable

## Implementation Order

1. ✅ Create proposal document
2. ✅ Create implementation plan
3. ⏳ Create CameraTextureProvider
4. ⏳ Create edge detection shader
5. ⏳ Create displacement shaders
6. ⏳ Create preset implementations
7. ⏳ Add environment keys
8. ⏳ Update VisualizerPreset enum
9. ⏳ Update UI controls
10. ⏳ Testing and optimization
11. ⏳ Documentation

## Potential Issues & Solutions

### Issue: Frame Rate Drops
**Solution**: Reduce processing resolution, optimize shaders, implement frame dropping

### Issue: Memory Pressure
**Solution**: Use texture pools, release unused textures, monitor memory

### Issue: Audio/Video Sync
**Solution**: Use timestamps, smooth interpolation, frame dropping

### Issue: Edge Detection Quality
**Solution**: Expose threshold controls, add adaptive thresholding option

### Issue: Displacement Artifacts
**Solution**: Clamp UVs, use smooth interpolation, add temporal smoothing

## Next Steps

Proceed with implementation following the order above.

