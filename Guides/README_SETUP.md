# 🎯 Complete Setup Guide: Building as iPhone App

## ✅ What's Ready

All the necessary files are in place:
- ✅ Swift Package with TCA architecture
- ✅ App entry point: `AudioVisualizerApp/AudioVisualizerApp.swift`
- ✅ Info.plist with microphone permissions
- ✅ All source code compiled and tested

## 🚀 Next Steps: Create Xcode Project

### Method 1: Create in Xcode (Recommended - 5 minutes)

1. **Open Xcode**

2. **Create New Project:**
   - File > New > Project (or Cmd+Shift+N)
   - Select **iOS** tab
   - Choose **App** template
   - Click **Next**

3. **Configure Project:**
   - Product Name: `AudioVisualizerApp`
   - Team: (Select your development team)
   - Organization Identifier: `com.yourname` (or any unique identifier)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None (or Core Data if you plan to add it later)
   - Include Tests: ✅ (optional)
   - Click **Next**

4. **Save Location:**
   - Navigate to: `/Users/brianwong/projects/hviz_v1demo`
   - **Important:** Save it here so it's in the same directory as the package
   - Click **Create**

5. **Replace App Entry Point:**
   - In Xcode, find and **delete** `ContentView.swift` (if it was created)
   - In Project Navigator, right-click your app target folder
   - Choose **Add Files to "AudioVisualizerApp"...**
   - Navigate to and select: `AudioVisualizerApp/AudioVisualizerApp.swift`
   - **Uncheck** "Copy items if needed" (we want to reference the existing file)
   - Make sure your app target is checked
   - Click **Add**

6. **Add Local Package:**
   - File > Add Package Dependencies...
   - Click **Add Local...** button
   - Navigate to: `/Users/brianwong/projects/hviz_v1demo`
   - Select the folder and click **Add Package**
   - In the package products, select **AudioVisualizer**
   - Make sure your app target is selected
   - Click **Add Package**

7. **Configure Info.plist:**
   - Select your project in Project Navigator
   - Select your app target
   - Go to **Info** tab
   - Add new key: `Privacy - Microphone Usage Description`
   - Value: `This app needs access to your microphone to visualize live audio waveforms.`
   - (Optional) Add `Metal Capture Enabled` = `YES`

   OR manually edit the Info.plist file and add:
   ```xml
   <key>NSMicrophoneUsageDescription</key>
   <string>This app needs access to your microphone to visualize live audio waveforms.</string>
   <key>MTLCaptureEnabled</key>
   <true/>
   ```

8. **Build and Run:**
   - Connect a physical iOS device (iPhone/iPad)
   - Select your device from the device menu
   - Press **Cmd+R** or click the Run button
   - Grant microphone permission when prompted
   - Tap "Start" to see the live waveform!

### Method 2: Using XcodeGen (Automatic)

If you prefer automation:

```bash
# Install XcodeGen
brew install xcodegen

# Generate project
./setup_ios_app.sh

# Open the generated project
open AudioVisualizerApp.xcodeproj
```

## 📁 Final Project Structure

After setup, you should have:

```
hviz_v1demo/
├── AudioVisualizerApp.xcodeproj/     # Your Xcode project
├── AudioVisualizerApp/                # App source files
│   ├── AudioVisualizerApp.swift      # App entry point
│   └── Info.plist                    # App config
├── Sources/                           # Swift Package
│   └── AudioVisualizer/
├── Package.swift                      # Package manifest
└── ... (other files)
```

## ✅ Verification Checklist

- [ ] Xcode project created
- [ ] `AudioVisualizerApp.swift` added to app target
- [ ] Local package dependency added
- [ ] Microphone permission added to Info.plist
- [ ] Project builds without errors (Cmd+B)
- [ ] Physical device connected
- [ ] App runs and shows "Live Audio Waveform" screen
- [ ] Microphone permission prompt appears
- [ ] Waveform visualization works when tapping "Start"

## 🐛 Troubleshooting

### "No such module 'AudioVisualizer'"
- Make sure you added the local package dependency (Step 6)
- Check that the package is linked to your app target
- Try: File > Packages > Reset Package Caches

### "Cannot find 'AudioVisualizerView'"
- Verify the package dependency is correctly added
- Clean build folder: Product > Clean Build Folder (Cmd+Shift+K)
- Rebuild: Product > Build (Cmd+B)

### Microphone not working
- **Must use physical device** - Simulator doesn't support microphone
- Check Info.plist has `NSMicrophoneUsageDescription`
- Grant permission in iOS Settings > Privacy > Microphone

### Build errors
- Ensure Xcode 15.0+ and iOS 17.0+ deployment target
- Check Swift version is 5.9+
- Try: Product > Clean Build Folder, then rebuild

## 🎉 Success!

Once everything is set up, you'll have a fully functional audio visualizer app with:
- Real-time FFT analysis
- Beautiful waveform visualization
- Clean TCA architecture
- Ready for further development

Happy coding! 🚀

