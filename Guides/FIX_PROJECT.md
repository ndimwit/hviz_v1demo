# Fix: Creating the Xcode Project

The project file structure is complex to generate manually. The easiest solution is to create it in Xcode:

## Quick Fix (2 minutes)

1. **Open Xcode**

2. **File > New > Project**
   - Choose **iOS** > **App**
   - Product Name: `AudioVisualizerApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Save in: `/Users/brianwong/projects/hviz_v1demo`

3. **After creation:**
   - Delete `ContentView.swift` (if created)
   - Right-click your app target → **Add Files to "AudioVisualizerApp"...**
   - Select: `AudioVisualizerApp/AudioVisualizerApp.swift`
   - **Uncheck** "Copy items if needed"
   - Make sure your app target is checked
   - Click **Add**

4. **Add Package:**
   - File > Add Package Dependencies...
   - Click **Add Local...**
   - Select: `/Users/brianwong/projects/hviz_v1demo`
   - Add `AudioVisualizer` product to your target

5. **Update Info.plist:**
   - Add `Privacy - Microphone Usage Description` = `This app needs access to your microphone to visualize live audio waveforms.`

6. **Build and Run!**

## Alternative: Use XcodeGen

If you want automatic generation:

```bash
brew install xcodegen
./setup_ios_app.sh
```

This will generate a proper project from `project.yml`.

