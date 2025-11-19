# Setting Up the Xcode Project

Since `swift package generate-xcodeproj` is deprecated, follow these steps to create an Xcode project for the Audio Visualizer app:

## Option 1: Create iOS App Project in Xcode (Recommended)

1. **Open Xcode** (version 15.0 or later)

2. **Create a new iOS App project:**
   - File > New > Project
   - Choose **iOS** > **App**
   - Click **Next**
   - Product Name: `AudioVisualizerApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Click **Next** and choose a location (you can create it in a subdirectory or separate location)

3. **Add the local Swift package:**
   - In the new project, go to **File > Add Package Dependencies...**
   - Click **Add Local...**
   - Navigate to and select this directory: `/Users/brianwong/projects/hviz_v1demo`
   - Click **Add Package**
   - Select the `AudioVisualizer` library product
   - Click **Add Package**

4. **Update the app entry point:**
   - In your new app's `App.swift` (or create it if it doesn't exist), replace the content with:
   ```swift
   import SwiftUI
   import AudioVisualizer
   
   @main
   struct AudioVisualizerApp: App {
       var body: some Scene {
           WindowGroup {
               AudioVisualizerView(
                   store: Store(initialState: AudioVisualizerFeature.State()) {
                       AudioVisualizerFeature()
                   }
               )
           }
       }
   }
   ```
   
   Or use the helper:
   ```swift
   import SwiftUI
   import AudioVisualizer
   
   @main
   struct AudioVisualizerApp: App {
       var body: some Scene {
           WindowGroup {
               AudioVisualizerAppConfig.createView()
           }
       }
   }
   ```

5. **Add Info.plist settings:**
   - In your app target's Info.plist, add:
   ```xml
   <key>NSMicrophoneUsageDescription</key>
   <string>This app needs access to your microphone to visualize live audio waveforms.</string>
   <key>MTLCaptureEnabled</key>
   <true/>
   ```

6. **Build and Run:**
   - Select a physical iOS device (simulator doesn't have microphone access)
   - Press Cmd+R to build and run

## Option 2: Open Package Directly in Xcode

1. **Open the package:**
   ```bash
   open Package.swift
   ```
   This opens the Swift package in Xcode.

2. **Note:** This approach works for building the library, but to run as an app, you'll still need to create an iOS app target (see Option 1).

## Building from Command Line

You can build the Swift package from the command line:

```bash
swift build
```

To run tests:

```bash
swift test
```

## Troubleshooting

- **Microphone permission:** Make sure you're running on a physical device, as the iOS Simulator doesn't support microphone access.
- **Build errors:** Ensure you're using Xcode 15.0+ and Swift 5.9+
- **Package resolution:** Run `swift package resolve` if dependencies aren't resolving

