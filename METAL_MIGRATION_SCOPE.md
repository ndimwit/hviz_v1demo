# Metal-Based Game Window Migration Scope

## Overview
This document outlines the changes required to migrate from SwiftUI/Swift Charts rendering to a Metal-based game window implementation, based on [Apple's Metal window management documentation](https://developer.apple.com/documentation/Metal/managing-your-game-window-for-metal-in-macos).

**Note:** The referenced documentation is for macOS, but this app targets iOS. The core Metal concepts apply, but window management differs significantly between platforms.

## Current Architecture

### Current Stack:
- **UI Framework:** SwiftUI
- **Rendering:** Swift Charts
- **State Management:** TCA (The Composable Architecture)
- **Platforms:** iOS 17.0+, macOS 14.0+ (Mac Catalyst)
- **Visualization Presets:** 5 presets (Line Chart, Histogram Bands, Oscilloscope, Stereo Field, Quadrant)

### Current Rendering Flow:
1. Audio data → FFT processing → Magnitude arrays
2. Magnitude arrays → Swift Charts views
3. Swift Charts → SwiftUI rendering pipeline

## Required Changes

### 1. Core Metal Infrastructure

#### 1.1 Metal Device & Command Queue Setup
**Files to Create:**
- `Sources/AudioVisualizer/MetalRenderer.swift` - Core Metal rendering engine
- `Sources/AudioVisualizer/MetalDeviceManager.swift` - Device and queue management

**Changes:**
- Create `MTLDevice` instance (shared system device)
- Create `MTLCommandQueue` for command submission
- Implement device capability checking
- Handle device loss/recovery scenarios

**Key Code Structure:**
```swift
class MetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.deviceCreationFailed
        }
        self.device = device
        // ... setup command queue and shader library
    }
}
```

#### 1.2 MTKView Integration
**Files to Create:**
- `Sources/AudioVisualizer/MetalVisualizerView.swift` - UIViewRepresentable wrapper for MTKView
- `Sources/AudioVisualizer/MetalViewCoordinator.swift` - Coordinator for MTKViewDelegate

**Changes:**
- Create `MTKView` wrapper compatible with SwiftUI
- Implement `MTKViewDelegate` for frame updates
- Handle view lifecycle (appear/disappear)
- Manage drawable resources

**Key Code Structure:**
```swift
struct MetalVisualizerView: UIViewRepresentable {
    let renderer: MetalRenderer
    let magnitudes: [Float]
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device
        mtkView.delegate = context.coordinator
        // ... configure view
        return mtkView
    }
}
```

### 2. Shader Implementation

#### 2.1 Metal Shader Library
**Files to Create:**
- `Sources/AudioVisualizer/Shaders.metal` - Metal shader source code

**Shaders Required:**
1. **Line Chart Shader** - Vertex/fragment shader for line rendering
2. **Histogram Shader** - Compute shader for bar chart rendering
3. **Oscilloscope Shader** - Vertex shader for waveform rendering
4. **Stereo Field Shader** - Fragment shader for stereo visualization
5. **Quadrant Shader** - Multi-pass shader for quadrant view

**Key Shader Structure:**
```metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position;
    float magnitude;
};

struct VertexOut {
    float4 position [[position]];
    float magnitude;
};

vertex VertexOut lineChartVertex(device VertexIn* vertices [[buffer(0)]],
                                  uint vid [[vertex_id]]) {
    // Vertex processing
}

fragment float4 lineChartFragment(VertexOut in [[stage_in]]) {
    // Fragment processing with gradient
}
```

#### 2.2 Compute Shaders for FFT Visualization
**Additional Shaders:**
- FFT magnitude to vertex buffer conversion
- Scrolling buffer management
- Color gradient application

### 3. Rendering Pipeline Refactoring

#### 3.1 Replace Swift Charts with Metal Rendering
**Files to Modify:**
- `Sources/AudioVisualizer/VisualizerPreset.swift` - Update all preset implementations
- `Sources/AudioVisualizer/AudioVisualizerView.swift` - Replace Chart views with Metal views

**Changes per Preset:**

**LineChartPreset:**
- Remove: Swift Charts `LineMark`, `Chart`, `Path`
- Add: Metal vertex buffer generation from magnitudes
- Add: Metal line rendering with gradient shader

**HistogramBandsPreset:**
- Remove: Swift Charts `BarMark`
- Add: Metal compute shader for bar heights
- Add: Metal instanced rendering for bars

**OscilloscopePreset:**
- Remove: Swift Charts `LineMark` for waveform
- Add: Metal vertex buffer from raw audio samples
- Add: Metal line strip rendering

**StereoFieldPreset:**
- Remove: Swift Charts dual-channel visualization
- Add: Metal fragment shader for stereo field
- Add: Metal texture-based rendering

**QuadrantPreset:**
- Remove: Swift Charts multi-view layout
- Add: Metal viewport splitting
- Add: Metal multi-pass rendering

#### 3.2 Buffer Management
**Files to Create:**
- `Sources/AudioVisualizer/MetalBufferManager.swift` - Buffer allocation and management

**Buffers Required:**
- Vertex buffers for each visualization type
- Uniform buffers for transformation matrices
- Index buffers for optimized rendering
- Texture buffers for scrolling data

**Key Features:**
- Dynamic buffer resizing based on FFT size
- Buffer pooling for performance
- Thread-safe buffer updates

### 4. Window Management (iOS-Specific)

#### 4.1 Full Screen Configuration
**Files to Modify:**
- `AudioVisualizerApp/AudioVisualizerApp.swift` - Window configuration

**Changes:**
- Remove `fullScreenCover` approach (if not working)
- Use `MTKView` with `ignoresSafeArea` for full screen
- Configure `MTKView.preferredFramesPerSecond` for 60fps
- Set `MTKView.enableSetNeedsDisplay = false` for continuous rendering

**iOS Window Management:**
Unlike macOS, iOS apps don't have traditional windows. Instead:
- Use `MTKView` that fills the entire screen
- Handle safe area insets in Metal rendering (adjust viewport)
- Use `UIViewController` presentation for full screen if needed

#### 4.2 View Controller Integration
**Files to Create:**
- `Sources/AudioVisualizer/MetalViewController.swift` - UIViewController wrapper

**Changes:**
- Create `UIViewController` that hosts `MTKView`
- Integrate with SwiftUI via `UIViewControllerRepresentable`
- Handle orientation changes
- Manage Metal view lifecycle

### 5. Performance Optimizations

#### 5.1 Rendering Optimizations
**Changes:**
- Implement frame rate limiting (60fps target)
- Use triple buffering for drawables
- Implement occlusion culling for off-screen elements
- Use instanced rendering for repeated elements (bars, lines)

#### 5.2 Memory Management
**Changes:**
- Implement buffer recycling
- Use `MTLResourceOptions.storageModeShared` for CPU-accessible buffers
- Use `MTLResourceOptions.storageModePrivate` for GPU-only buffers
- Implement proper resource cleanup on view dismissal

### 6. State Management Integration

#### 6.1 TCA Integration
**Files to Modify:**
- `Sources/AudioVisualizer/AudioVisualizerFeature.swift` - Add Metal rendering state

**Changes:**
- Add Metal renderer instance to feature state
- Update actions to trigger Metal rendering
- Maintain compatibility with existing TCA architecture

#### 6.2 Data Flow Updates
**Current Flow:**
```
AudioUnitMonitor → FFT Magnitudes → Swift Charts
```

**New Flow:**
```
AudioUnitMonitor → FFT Magnitudes → Metal Buffer Updates → Metal Rendering
```

### 7. Platform-Specific Considerations

#### 7.1 iOS
- Use `MTKView` directly in SwiftUI
- Handle safe area insets in viewport calculations
- Support all iOS device screen sizes
- Handle orientation changes

#### 7.2 macOS (Mac Catalyst)
- Adapt window management from documentation
- Support window resizing
- Handle multiple displays
- Implement window state restoration

### 8. Testing & Validation

#### 8.1 Visual Regression Testing
- Compare Metal rendering output with Swift Charts
- Verify all 5 presets render correctly
- Test scrolling and continuous modes

#### 8.2 Performance Testing
- Measure frame rates on various devices
- Profile GPU usage
- Test memory usage patterns
- Validate battery impact

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
1. Set up Metal device and command queue
2. Create MTKView wrapper for SwiftUI
3. Implement basic line rendering shader
4. Replace one preset (LineChart) as proof of concept

### Phase 2: Core Rendering (Week 3-4)
1. Implement all shader types
2. Create buffer management system
3. Replace all 5 presets with Metal rendering
4. Implement scrolling mode rendering

### Phase 3: Optimization (Week 5-6)
1. Performance profiling and optimization
2. Memory management improvements
3. Frame rate optimization
4. Battery usage optimization

### Phase 4: Polish (Week 7-8)
1. Visual parity with Swift Charts
2. Handle edge cases
3. Comprehensive testing
4. Documentation

## Dependencies

### New Dependencies:
- **Metal Framework** - Already available in iOS/macOS SDK
- **MetalKit Framework** - For MTKView (already available)

### No External Dependencies Required:
- Metal is part of the system frameworks
- No additional package dependencies needed

## Breaking Changes

### API Changes:
- `VisualizerPreset.makeView()` return type may need adjustment
- Some SwiftUI-specific features may not translate directly

### Migration Path:
- Can implement Metal rendering alongside Swift Charts initially
- Feature flag to switch between rendering backends
- Gradual migration per preset

## Risk Assessment

### High Risk:
- **Performance on older devices** - Metal may not perform well on older iPhones
- **Visual parity** - Matching Swift Charts appearance exactly may be challenging
- **Development time** - Significant effort required for shader development

### Medium Risk:
- **Platform differences** - iOS vs macOS window management differences
- **State management** - Integrating Metal with TCA may require refactoring

### Low Risk:
- **Metal availability** - All target devices support Metal
- **Framework stability** - Metal is mature and well-documented

## Estimated Effort

- **Total Development Time:** 6-8 weeks
- **Lines of Code:** ~3,000-5,000 new lines
- **Files Created:** ~10-15 new files
- **Files Modified:** ~5-8 existing files

## References

- [Metal Window Management (macOS)](https://developer.apple.com/documentation/Metal/managing-your-game-window-for-metal-in-macos)
- [Metal Programming Guide](https://developer.apple.com/documentation/metal)
- [MetalKit Documentation](https://developer.apple.com/documentation/metalkit)
- [MTKView Documentation](https://developer.apple.com/documentation/metalkit/mtkview)

