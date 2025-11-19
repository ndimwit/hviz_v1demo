# Building as an iPhone App

This guide will help you convert this Swift Package into a runnable iOS app.

## Quick Start (Recommended)

### Step 1: Create the Xcode Project

1. **Open Xcode** (version 15.0 or later)

2. **Create a new iOS App project:**
   - File > New > Project
   - Choose **iOS** > **App**
   - Click **Next**
   - Product Name: `AudioVisualizerApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Click **Next**
   - **Save it in this directory:** `/Users/brianwong/projects/hviz_v1demo`
   - Click **Create**

### Step 2: Configure the App

1. **Replace the app entry point:**
   - In Xcode, delete the default `ContentView.swift` (if it was created)
   - In the Project Navigator, right-click on your app target folder
   - Choose "Add Files to [Project Name]..."
   - Navigate to and select: `AudioVisualizerApp/AudioVisualizerApp.swift`
   - Make sure "Copy items if needed" is **unchecked** (we want to reference the existing file)
   - Make sure your app target is checked
   - Click **Add**

2. **Add microphone permissions:**
   - Select your project in the Project Navigator
   - Select your app target
   - Go to the **Info** tab
   - Add a new key: `Privacy - Microphone Usage Description`
   - Set value: `This app needs access to your microphone to visualize live audio waveforms.`
   - (Optional) Add `Metal Capture Enabled` key with value `YES`

   OR manually edit `Info.plist` and add:
   ```xml
   <key>NSMicrophoneUsageDescription</key>
   <string>This app needs access to your microphone to visualize live audio waveforms.</string>
   <key>MTLCaptureEnabled</key>
   <true/>
   ```

### Step 3: Add the Swift Package Dependency

1. **Add the local package:**
   - In Xcode, go to **File > Add Package Dependencies...**
   - Click **Add Local...**
   - Navigate to and select this directory: `/Users/brianwong/projects/hviz_v1demo`
   - Click **Add Package**
   - Select the `AudioVisualizer` library product
   - Make sure your app target is selected
   - Click **Add Package**

### Step 4: Build and Run

1. **Select a device:**
   - Connect a physical iOS device (microphone doesn't work in simulator)
   - Select it from the device menu in Xcode

2. **Build and run:**
   - Press **Cmd+R** or click the Run button
   - Grant microphone permission when prompted
   - Tap "Start" to begin visualization

## Alternative: Using XcodeGen (Automatic)

If you have XcodeGen installed:

```bash
# Install XcodeGen (if not installed)
brew install xcodegen

# Generate the project
./setup_ios_app.sh
```

This will automatically create the Xcode project from `project.yml`.

## Project Structure

After setup, your project should look like:

```
hviz_v1demo/
├── AudioVisualizerApp.xcodeproj/    # Xcode project (created)
├── AudioVisualizerApp/               # App source files
│   ├── AudioVisualizerApp.swift     # App entry point
│   └── Info.plist                   # App configuration
├── Sources/                          # Swift Package source
│   └── AudioVisualizer/
└── Package.swift                     # Package manifest
```

## Troubleshooting

### Build Errors

- **"No such module 'AudioVisualizer'"**: Make sure you added the local package dependency (Step 3)
- **"Cannot find 'AudioVisualizerView'"**: Ensure the package is linked to your app target
- **Microphone permission denied**: Make sure you're running on a physical device, not the simulator

### Package Resolution Issues

If dependencies aren't resolving:
```bash
swift package resolve
```

Then in Xcode: File > Packages > Reset Package Caches

### Xcode Version

Make sure you're using Xcode 15.0 or later with Swift 5.9+.

## Verification

After setup, you should be able to:
1. Build the project (Cmd+B) without errors
2. Run on a physical iOS device
3. See the "Live Audio Waveform" interface
4. Tap "Start" and grant microphone permission
5. See real-time waveform visualization

