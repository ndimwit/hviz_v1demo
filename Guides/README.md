# Audio Visualizer - TCA Swift Application

A real-time audio waveform visualizer built with SwiftUI and The Composable Architecture (TCA), demonstrating live audio analysis using Fast Fourier Transform (FFT).

## Overview

This application captures audio input from the device's microphone, performs real-time frequency analysis using FFT, and visualizes the results as a dynamic waveform chart. The architecture follows TCA principles for predictable state management and testability.

**Platform Support:**
- ✅ iPhone (iOS 17.0+)
- ✅ iPad (iOS 17.0+)
- ✅ Mac (macOS 13.0+ via Mac Catalyst)

## Architecture

### The Composable Architecture (TCA)

This project uses [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) by Point-Free, which provides:

- **Unidirectional data flow**: State flows down, actions flow up
- **Predictable state management**: All state changes are explicit and traceable
- **Testability**: Business logic is isolated and easily testable
- **Composability**: Features can be composed together

### Architecture Components

#### 1. **Feature Module** (`AudioVisualizerFeature`)
   - **State**: Contains all the UI state (magnitudes, monitoring status, errors)
   - **Action**: Defines all possible user actions and system events
   - **Reducer**: Pure function that transforms state based on actions
   - **Dependencies**: Injected dependencies for testability

#### 2. **Service Layer** (`AudioWaveformMonitor`)
   - Handles audio input capture via `AVAudioEngine`
   - Performs FFT analysis using Apple's Accelerate framework
   - Manages audio engine lifecycle
   - Provides real-time magnitude data

#### 3. **View Layer** (`AudioVisualizerView`)
   - SwiftUI view that displays the waveform chart
   - Uses Swift Charts for visualization
   - Connects to TCA store via `WithViewStore`

## Project Structure

```
hviz_v1demo/
├── Package.swift                    # Swift Package Manager manifest
├── Info.plist                       # App configuration (microphone permissions)
├── .gitignore                       # Git ignore rules
├── README.md                        # This file
└── Sources/
    └── AudioVisualizer/
        ├── AudioVisualizerApp.swift      # App entry point
        ├── AudioVisualizerFeature.swift  # TCA feature (State, Action, Reducer)
        ├── AudioVisualizerView.swift     # SwiftUI view
        ├── AudioWaveformMonitor.swift    # Audio service layer
        └── Constants.swift               # Configuration constants
```

### File Descriptions

#### `Package.swift`
Swift Package Manager manifest defining:
- Package dependencies (TCA)
- Target configurations
- Platform requirements (iOS 17+, macOS 14+)

#### `AudioVisualizerApp.swift`
Main app entry point that creates the root store and view.

#### `AudioVisualizerFeature.swift`
Core TCA feature containing:
- **State**: 
  - `fftMagnitudes`: Raw FFT frequency data
  - `downsampledMagnitudes`: Reduced dataset for visualization
  - `isMonitoring`: Audio capture status
  - `errorMessage`: Error handling
  - `maxMagnitude`: Chart scaling helper

- **Actions**:
  - `toggleMonitoringTapped`: User interaction
  - `monitoringStarted/Stopped`: State transitions
  - `magnitudesUpdated`: FFT data updates
  - `errorOccurred`: Error handling
  - `clearError`: Error dismissal

- **Reducer**: 
  - Handles all state transitions
  - Manages async audio operations
  - Observes magnitude updates at ~30 FPS

#### `AudioVisualizerView.swift`
SwiftUI view that:
- Displays live waveform using Swift Charts
- Shows start/stop button
- Handles error display
- Uses gradient styling for visualization

#### `AudioWaveformMonitor.swift`
Service class that:
- Manages `AVAudioEngine` for microphone access
- Configures FFT using Accelerate framework
- Performs real-time frequency analysis
- Provides downsampled data for efficient rendering
- Handles microphone permissions

#### `Constants.swift`
Configuration values:
- `sampleAmount`: Number of frequency bins (200)
- `downsampleFactor`: Data reduction factor (8)
- `magnitudeLimit`: Maximum magnitude cap (100)

## Technical Details

### Fast Fourier Transform (FFT)

The app uses Apple's Accelerate framework to perform FFT on audio samples:
1. Captures audio buffer (8192 samples)
2. Converts time-domain signal to frequency-domain
3. Computes magnitude for each frequency bin
4. Limits magnitudes to prevent visualization distortion

### Real-time Processing

- Audio buffers are processed asynchronously
- FFT results are updated at ~30 FPS for smooth visualization
- Downsampling reduces rendering overhead

### Permissions

The app requires microphone access. The `Info.plist` includes:
- `NSMicrophoneUsageDescription`: User-facing permission text
- `MTLCaptureEnabled`: Optional Metal debugging support

## Getting Started

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ or macOS 14.0+
- Swift 5.9+

### Setup

#### As an iPhone/iPad App (Recommended)

See **`QUICK_START.md`** for the fastest way to get running, or **`BUILD_IOS_APP.md`** for detailed instructions.

Quick steps:
1. Open Xcode → File > New > Project → iOS > App
2. Add local package dependency (this directory)
3. Use `AudioVisualizerApp/AudioVisualizerApp.swift` as your app entry point
4. Build and run on a physical device (microphone access required)
5. Grant microphone permission when prompted
6. Tap "Start" to begin visualization

#### Running on Mac (Mac Catalyst)

This app supports **Mac Catalyst**, allowing it to run natively on Mac. See **`TESTING_ON_MAC.md`** for detailed instructions.

Quick steps:
1. Open `AudioVisualizerApp.xcodeproj` in Xcode
2. Select **"My Mac (Designed for iPad)"** as the build target
3. Build and run (Cmd+R)
4. Grant microphone permission when prompted
5. Click "Start" to begin visualization

**Requirements:**
- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later

#### As a Swift Package

1. Clone the repository
2. Open `Package.swift` in Xcode
3. Build the package: `swift build`
4. Run tests: `swift test`

### Building

```bash
swift build
```

### Running Tests

```bash
swift test
```

## Dependencies

- **ComposableArchitecture**: State management framework
  - Version: 1.0.0+
  - Source: https://github.com/pointfreeco/swift-composable-architecture

## Architecture Benefits

### Testability
- Reducer logic is pure and easily testable
- Dependencies can be mocked for unit tests
- State transitions are predictable

### Maintainability
- Clear separation of concerns
- Single source of truth (State)
- Explicit action-based state changes

### Scalability
- Features can be composed together
- Easy to add new functionality
- Modular architecture supports growth

## Future Enhancements

Potential improvements:
- Multiple visualization modes (bar chart, area chart)
- Audio recording functionality
- Frequency filtering
- Sound recognition integration
- Customizable chart styling
- Export waveform data

## References

- [TCA Documentation](https://pointfreeco.github.io/swift-composable-architecture/)
- [Creating a Live Audio Waveform in SwiftUI](https://www.createwithswift.com/creating-a-live-audio-waveform-in-swiftui/)
- [Apple Accelerate Framework](https://developer.apple.com/documentation/accelerate)
- [AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)

