# Quick Start: Building as iPhone App

## 🚀 Fastest Way to Get Running

### Option 1: Automated Setup (if XcodeGen is installed)

```bash
brew install xcodegen  # If not installed
./setup_ios_app.sh
```

### Option 2: Manual Setup in Xcode (5 minutes)

1. **Open Xcode** → File > New > Project
2. **Choose:** iOS > App > Next
3. **Configure:**
   - Product Name: `AudioVisualizerApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Save in: **This directory** (`/Users/brianwong/projects/hviz_v1demo`)
4. **After creation:**
   - Delete `ContentView.swift` (if created)
   - Add existing file: `AudioVisualizerApp/AudioVisualizerApp.swift` to your target
   - Add local package: File > Add Package Dependencies > Add Local... > Select this directory
   - Add `AudioVisualizer` product to your app target
   - Update Info.plist with microphone permissions (see `AudioVisualizerApp/Info.plist`)
5. **Run:** Connect iPhone → Select device → Cmd+R

## 📱 What You'll Get

- ✅ Real-time audio waveform visualization
- ✅ Live FFT frequency analysis
- ✅ Beautiful Swift Charts visualization
- ✅ TCA architecture for clean state management

## ⚠️ Important Notes

- **Must run on physical device** (simulator doesn't support microphone)
- **Requires iOS 17.0+**
- **Xcode 15.0+** required

## 📚 More Details

See `BUILD_IOS_APP.md` for detailed step-by-step instructions.

