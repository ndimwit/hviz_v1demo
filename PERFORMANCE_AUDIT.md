# Performance Audit & Optimization Proposals

## Executive Summary

This document provides a comprehensive performance audit of the Audio Visualizer codebase, with a special focus on Quadrant mode rendering. The audit identifies bottlenecks, proposes optimizations with tradeoff analysis, and prioritizes improvements based on impact and implementation difficulty.

## Current Architecture Overview

### Data Flow
1. **AudioUnitMonitor** → Captures audio, performs FFT → Updates `fftMagnitudes` on MainActor
2. **AudioVisualizerFeature** → Interpolates/smooths magnitudes → Updates `displayMagnitudes`
3. **VisualizerPreset** → Each preset processes data independently → Renders via SwiftUI

### Quadrant Mode Current Implementation
- Creates 4 separate preset instances (LineChart, HistogramBands, Oscilloscope, StereoField)
- Each preset independently:
  - Receives the same input data
  - Performs its own downsampling
  - Creates its own GeometryReader
  - Renders independently (potentially out of sync)

---

## Performance Issues Identified

### Critical Issues (High Impact)

#### 1. **Redundant Data Processing in Quadrant Mode**
**Problem:**
- Same `magnitudes` array is downsampled 4 times (once per preset)
- Each preset uses identical input but processes independently
- No shared preprocessing or caching

**Impact:** 
- 4x CPU overhead for downsampling
- Potential data inconsistency between quadrants
- Unnecessary memory allocations

**Evidence:**
```swift
// QuadrantPreset.makeView() calls:
lineChartPreset.makeView(...)      // Downsamples magnitudes
histogramBandsPreset.makeView(...) // Downsamples magnitudes again
oscilloscopePreset.makeView(...)   // Downsamples rawAudioSamples
stereoFieldPreset.makeView(...)    // Processes stereo data
```

---

#### 2. **SwiftUI Charts Performance**
**Problem:**
- SwiftUI Charts (Swift Charts framework) is heavy for real-time rendering
- Each Chart view creates complex view hierarchies
- Animation overhead on every frame update
- Not optimized for 60+ FPS updates

**Impact:**
- Significant CPU/GPU overhead
- Frame drops during rapid updates
- Quadrant mode renders 2-4 Charts simultaneously

**Evidence:**
- LineChartPreset uses `Chart` with `LineMark`
- OscilloscopePreset uses `Chart` with `LineMark`
- Each Chart has `.animation()` modifiers

---

#### 3. **ForEach with `id: \.self` in Scrolling Mode**
**Problem:**
- Scrolling mode creates many small views via `ForEach(scrollingFrames.indices, id: \.self)`
- `id: \.self` causes SwiftUI to recreate views when indices change
- No stable view identity

**Impact:**
- Excessive view recreation
- Layout thrashing
- Poor performance with many frames (e.g., 32k frames for oscilloscope)

**Evidence:**
```swift
ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
    // View recreated on every update
}
```

---

#### 4. **Multiple GeometryReader Instances**
**Problem:**
- Each preset creates its own `GeometryReader`
- Quadrant mode has 4 GeometryReaders (one per preset) + 1 parent
- GeometryReader triggers layout passes on every update

**Impact:**
- Multiple layout calculations per frame
- Layout thrashing
- Increased CPU usage

---

### Moderate Issues (Medium Impact)

#### 5. **Linear Interpolation Downsampling Algorithm**
**Problem:**
- Current downsampling uses O(n) linear interpolation
- Performed repeatedly on every frame
- No caching of intermediate results
- Could use faster algorithms (e.g., vDSP)

**Impact:**
- CPU overhead (especially with large arrays)
- Quadrant mode: 4x this overhead

---

#### 6. **No View Identity Stability**
**Problem:**
- Views don't have stable identifiers
- SwiftUI can't efficiently diff view hierarchies
- Causes unnecessary re-renders

**Impact:**
- Extra rendering work
- Potential frame drops

---

#### 7. **Data Synchronization in Quadrant Mode**
**Problem:**
- Each preset receives data at slightly different times
- No guarantee all 4 quadrants show the same frame
- `displayMagnitudes` may update between preset renders

**Impact:**
- Visual misalignment between quadrants
- Inconsistent visualization

---

#### 8. **Memory Allocations in Hot Paths**
**Problem:**
- Downsampling creates new arrays on every call
- No object pooling or reuse
- Frequent allocations in rendering path

**Impact:**
- Memory pressure
- GC pauses
- Performance degradation

---

### Minor Issues (Low Impact)

#### 9. **Redundant Calculations**
- `maxMagnitude` calculated multiple times
- Color calculations repeated
- No memoization

#### 10. **Animation Overhead**
- Multiple `.animation()` modifiers
- SwiftUI animation system overhead

---

## Optimization Proposals

### Priority 1: Critical Optimizations (High Impact, Medium-High Difficulty)

#### **OP1: Shared Data Preprocessing for Quadrant Mode**
**Description:**
- Preprocess data once before passing to quadrants
- Create a shared data structure with pre-downsampled arrays
- Ensure all quadrants use the same data snapshot

**Implementation:**
```swift
struct QuadrantData {
    let downsampledMagnitudes: [Float]
    let downsampledRawSamples: [Float]
    let stereoData: StereoFieldData
    let maxMagnitude: Float
    let timestamp: Date // For synchronization
}

// In QuadrantPreset:
let sharedData = preprocessQuadrantData(...)
// Pass sharedData to all 4 presets
```

**Tradeoffs:**
- ✅ Eliminates redundant processing
- ✅ Ensures data consistency
- ✅ Reduces CPU usage by ~75% in quadrant mode
- ⚠️ Adds complexity to data flow
- ⚠️ Requires refactoring preset interface

**Difficulty:** Medium (3-5 days)
**Impact:** Very High (4x reduction in processing)

---

#### **OP2: Replace SwiftUI Charts with Custom Path Rendering**
**Description:**
- Replace `Chart` views with custom `Path` rendering
- Use `Canvas` API or direct `Path` drawing
- Optimize for real-time updates

**Implementation:**
```swift
// Instead of Chart:
Path { path in
    // Direct path construction
    for (index, value) in data.enumerated() {
        let point = CGPoint(x: xPos, y: yPos)
        if index == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
}
.stroke(gradient, lineWidth: 2)
```

**Tradeoffs:**
- ✅ Much faster rendering (10-50x improvement)
- ✅ More control over rendering
- ✅ Better performance in quadrant mode
- ⚠️ More code to maintain
- ⚠️ Lose some Chart features (auto-scaling, etc.)
- ⚠️ Need to implement interpolation manually

**Difficulty:** High (5-7 days)
**Impact:** Very High (major FPS improvement)

---

#### **OP3: Use Stable View Identifiers**
**Description:**
- Replace `id: \.self` with stable identifiers
- Use frame timestamps or sequence numbers
- Implement proper view identity

**Implementation:**
```swift
struct FrameIdentifier: Identifiable {
    let id: UUID // Stable across updates
    let index: Int
    let data: [Float]
}

// In scrolling mode:
ForEach(frames.map { FrameIdentifier(...) }) { frame in
    // View identity is stable
}
```

**Tradeoffs:**
- ✅ Reduces view recreation
- ✅ Better SwiftUI diffing
- ✅ Improved scrolling performance
- ⚠️ Requires data structure changes
- ⚠️ More memory for identifiers

**Difficulty:** Medium (2-3 days)
**Impact:** High (especially for scrolling mode)

---

### Priority 2: High-Value Optimizations (High Impact, Medium Difficulty)

#### **OP4: Consolidate GeometryReaders**
**Description:**
- Use single GeometryReader at top level
- Pass geometry down to presets
- Reduce layout passes

**Implementation:**
```swift
GeometryReader { geometry in
    let quadrantSize = CGSize(...)
    // Pass quadrantSize to presets instead of GeometryReader
}
```

**Tradeoffs:**
- ✅ Fewer layout calculations
- ✅ Better performance
- ⚠️ Less flexible layout
- ⚠️ Requires preset interface changes

**Difficulty:** Medium (2-3 days)
**Impact:** Medium-High

---

#### **OP5: Use vDSP for Downsampling**
**Description:**
- Replace linear interpolation with vDSP decimation
- Use Accelerate framework for faster processing
- Cache downsampling results when possible

**Implementation:**
```swift
import Accelerate

func downsampleWithVDSP(_ input: [Float], to targetCount: Int) -> [Float] {
    // Use vDSP_deq22 or similar for decimation
    // Much faster than manual interpolation
}
```

**Tradeoffs:**
- ✅ Faster downsampling (5-10x)
- ✅ Better for large arrays
- ✅ Leverages hardware acceleration
- ⚠️ More complex implementation
- ⚠️ May need different algorithm for different use cases

**Difficulty:** Medium (3-4 days)
**Impact:** High (especially with large arrays)

---

#### **OP6: Data Snapshot for Quadrant Mode**
**Description:**
- Capture data snapshot once per frame
- All quadrants use the same snapshot
- Prevents data inconsistency

**Implementation:**
```swift
struct DataSnapshot {
    let magnitudes: [Float]
    let rawSamples: [Float]
    let leftChannel: [Float]
    let rightChannel: [Float]
    let timestamp: Date
}

// In QuadrantPreset:
let snapshot = DataSnapshot(...)
// All 4 presets use snapshot
```

**Tradeoffs:**
- ✅ Perfect synchronization
- ✅ Consistent visualization
- ✅ Simpler data flow
- ⚠️ Slight memory overhead
- ⚠️ Requires state management

**Difficulty:** Low-Medium (1-2 days)
**Impact:** High (fixes alignment issues)

---

### Priority 3: Medium-Value Optimizations (Medium Impact, Low-Medium Difficulty)

#### **OP7: Memoization of Expensive Calculations**
**Description:**
- Cache `maxMagnitude` calculations
- Memoize color calculations
- Reuse when inputs haven't changed

**Tradeoffs:**
- ✅ Reduces redundant calculations
- ✅ Simple to implement
- ⚠️ Memory overhead
- ⚠️ Cache invalidation complexity

**Difficulty:** Low (1-2 days)
**Impact:** Medium

---

#### **OP8: Object Pooling for Arrays**
**Description:**
- Reuse arrays instead of allocating new ones
- Pool for common sizes
- Reduce GC pressure

**Tradeoffs:**
- ✅ Reduces allocations
- ✅ Better memory usage
- ⚠️ More complex memory management
- ⚠️ Potential memory leaks if not careful

**Difficulty:** Medium (2-3 days)
**Impact:** Medium

---

#### **OP9: Reduce Animation Overhead**
**Description:**
- Remove unnecessary `.animation()` modifiers
- Use explicit animation only when needed
- Consider implicit animations

**Tradeoffs:**
- ✅ Less animation overhead
- ✅ Better performance
- ⚠️ May reduce visual smoothness
- ⚠️ Need to balance aesthetics

**Difficulty:** Low (1 day)
**Impact:** Low-Medium

---

### Priority 4: Advanced Optimizations (High Impact, Very High Difficulty)

#### **OP10: Metal Rendering Pipeline**
**Description:**
- Use Metal for custom rendering
- GPU-accelerated path drawing
- Custom shaders for visualizations

**Tradeoffs:**
- ✅ Maximum performance
- ✅ GPU acceleration
- ✅ Can handle very high frame rates
- ⚠️ Very complex implementation
- ⚠️ Platform-specific code
- ⚠️ Significant development time

**Difficulty:** Very High (2-3 weeks)
**Impact:** Very High (ultimate performance)

---

#### **OP11: Core Graphics/Core Animation Optimization**
**Description:**
- Use CALayer for static elements
- Cache rendered paths
- Use CAShapeLayer for efficient updates

**Tradeoffs:**
- ✅ Good performance
- ✅ Better than SwiftUI for some cases
- ⚠️ More complex than SwiftUI
- ⚠️ Less declarative

**Difficulty:** High (1-2 weeks)
**Impact:** High

---

## Recommended Implementation Plan

### Phase 1: Quick Wins (1-2 weeks)
1. **OP6: Data Snapshot** - Fixes alignment issues immediately
2. **OP3: Stable View Identifiers** - Improves scrolling performance
3. **OP9: Reduce Animation Overhead** - Simple performance gain

### Phase 2: Core Optimizations (2-3 weeks)
1. **OP1: Shared Data Preprocessing** - Major quadrant mode improvement
2. **OP4: Consolidate GeometryReaders** - Reduces layout overhead
3. **OP5: vDSP Downsampling** - Faster processing

### Phase 3: Advanced Rendering (3-4 weeks)
1. **OP2: Custom Path Rendering** - Replace Charts for maximum performance
2. **OP7: Memoization** - Polish and optimization
3. **OP8: Object Pooling** - Memory optimization

### Phase 4: Ultimate Performance (Optional, 2-3 weeks)
1. **OP10: Metal Rendering** - If maximum performance needed
2. **OP11: Core Graphics** - Alternative to Metal

---

## Quadrant Mode Specific Recommendations

### Immediate Fixes (Critical for Smoothness)
1. **Data Snapshot (OP6)** - Ensures all quadrants are synchronized
2. **Shared Preprocessing (OP1)** - Eliminates redundant work

### Performance Improvements
1. **Custom Path Rendering (OP2)** - Replace Charts for better performance
2. **Consolidate GeometryReaders (OP4)** - Reduce layout passes

### Alignment Fixes
1. **Data Snapshot (OP6)** - Primary solution for alignment
2. **Shared Preprocessing (OP1)** - Ensures consistent data

---

## Metrics to Track

### Before Optimization
- FPS in Quadrant mode: [Measure]
- CPU usage: [Measure]
- Memory allocations per frame: [Measure]
- Frame time variance: [Measure]

### After Optimization
- Target: 60 FPS stable in Quadrant mode
- Target: <30% CPU usage
- Target: <10 allocations per frame
- Target: <16ms frame time (60 FPS)

---

## Risk Assessment

### Low Risk
- OP6: Data Snapshot
- OP3: Stable View Identifiers
- OP9: Reduce Animation Overhead
- OP7: Memoization

### Medium Risk
- OP1: Shared Preprocessing
- OP4: Consolidate GeometryReaders
- OP5: vDSP Downsampling
- OP8: Object Pooling

### High Risk
- OP2: Custom Path Rendering (breaking change)
- OP10: Metal Rendering (complex, platform-specific)
- OP11: Core Graphics (significant refactoring)

---

## Conclusion

The primary performance bottleneck in Quadrant mode is **redundant data processing** and **SwiftUI Charts overhead**. The recommended approach is:

1. **Immediate:** Implement data snapshot (OP6) to fix alignment
2. **Short-term:** Add shared preprocessing (OP1) to eliminate redundancy
3. **Medium-term:** Replace Charts with custom Path rendering (OP2) for maximum performance

This phased approach balances impact, difficulty, and risk while delivering measurable improvements at each stage.

