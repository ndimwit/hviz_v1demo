# Audio Visualizer

A real-time audio waveform visualizer built with SwiftUI and The Composable Architecture (TCA), demonstrating live audio analysis using Fast Fourier Transform (FFT).

## Quick Start

### One-Line Setup

```bash
./setup.sh
```

This script will:
- ✅ Check for and install Xcode Command Line Tools
- ✅ Check for and install Homebrew (if needed)
- ✅ Check for and install XcodeGen (optional, for project generation)
- ✅ Check for and install Python 3 and dependencies (numpy, scipy)
- ✅ Resolve Swift Package dependencies
- ✅ Generate Xcode project (if XcodeGen is available)

### After Setup

1. **Open the project in Xcode:**
   ```bash
   open AudioVisualizerApp.xcodeproj
   ```
   (If the .xcodeproj doesn't exist, open `Package.swift` instead)

2. **Build and run:**
   - Select a **physical iOS device** (simulator doesn't support microphone)
   - Press `Cmd+R` to build and run
   - Grant microphone permission when prompted
   - Tap "Start" to begin visualization

3. **Generate test audio files (optional):**
   ```bash
   python3 generate_test_audio.py
   ```

## Requirements

- **macOS** (for development)
- **Xcode 15.0+** (with Command Line Tools)
- **iOS 17.0+** or **macOS 14.0+** (for running the app)
- **Physical iOS device** (simulator doesn't support microphone)
- **Python 3** (optional, for generating test audio files)

## Platform Support

- ✅ iPhone (iOS 17.0+)
- ✅ iPad (iOS 17.0+)
- ✅ Mac (macOS 14.0+ via Mac Catalyst)

## Project Structure

```
hviz_v1demo/
├── README.md                    # This file
├── setup.sh                     # One-line setup script
├── Package.swift                # Swift Package Manager manifest
├── project.yml                  # XcodeGen project configuration
├── AudioVisualizerApp/          # iOS app target
│   ├── AudioVisualizerApp.swift # App entry point
│   └── Info.plist              # App configuration
├── Sources/
│   └── AudioVisualizer/        # Main package source code
├── Tests/                       # Unit tests
├── test_audio/                  # Test audio files
├── generate_test_audio.py       # Script to generate test audio
├── Guides/                      # Detailed guides and documentation
└── docs/                        # Additional documentation
```

## Architecture

This project uses [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) by Point-Free, which provides:

- **Unidirectional data flow**: State flows down, actions flow up
- **Predictable state management**: All state changes are explicit and traceable
- **Testability**: Business logic is isolated and easily testable
- **Composability**: Features can be composed together

### Key Components

1. **AudioVisualizerFeature**: TCA feature (State, Action, Reducer)
2. **AudioVisualizerView**: SwiftUI view with waveform visualization
3. **AudioWaveformMonitor**: Audio service layer using AVAudioEngine and Accelerate framework

## Building

### Using Xcode

1. Open `AudioVisualizerApp.xcodeproj` (or `Package.swift`)
2. Select your target device
3. Press `Cmd+R` to build and run

### Using Swift Package Manager

```bash
swift build
swift test
```

## Dependencies

- **ComposableArchitecture**: State management framework
  - Version: 1.0.0+
  - Source: https://github.com/pointfreeco/swift-composable-architecture

## Documentation

- **Quick Start**: See `Guides/QUICK_START.md`
- **Building iOS App**: See `Guides/BUILD_IOS_APP.md`
- **Testing on Mac**: See `Guides/TESTING_ON_MAC.md`
- **Testing on iPhone**: See `Guides/TESTING_ON_IPHONE.md`
- **Full Documentation**: See `Guides/README.md`

## Troubleshooting

### Setup Script Issues

If the setup script fails:
1. Make sure you're running on macOS
2. Install Xcode Command Line Tools manually: `xcode-select --install`
3. Install Homebrew manually: https://brew.sh

### Build Issues

- **"No such module 'AudioVisualizer'"**: Make sure the local package is added to your Xcode project
- **Microphone not working**: Make sure you're running on a physical device (not simulator)
- **Permission denied**: Grant microphone permission in Settings > Privacy & Security > Microphone

### Xcode Project Not Found

If `AudioVisualizerApp.xcodeproj` doesn't exist:
1. Install XcodeGen: `brew install xcodegen`
2. Run: `xcodegen generate`
3. Or open `Package.swift` directly in Xcode

## License

See LICENSE file for details.

