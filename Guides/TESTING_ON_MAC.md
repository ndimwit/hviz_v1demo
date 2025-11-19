# Testing on Mac (Mac Catalyst)

This app now supports running on Mac via **Mac Catalyst**, which allows iOS apps to run natively on macOS.

## Prerequisites

1. **Mac running macOS 13.0 (Ventura) or later** (required for Mac Catalyst)
2. **Xcode 15.0 or later** installed on your Mac
3. **Apple Developer Account** (free account works for development)

## What is Mac Catalyst?

Mac Catalyst allows iOS apps to run natively on Mac with minimal code changes. The app will:
- Run as a native Mac app (not in a simulator)
- Use Mac-style window controls and menus
- Support Mac-specific features like window resizing
- Still use iOS frameworks (UIKit/SwiftUI) under the hood

## Step-by-Step Instructions

### 1. Open the Project in Xcode

1. Open `AudioVisualizerApp.xcodeproj` in Xcode

### 2. Select "My Mac (Designed for iPad)" as Build Target

1. At the top of Xcode, next to the scheme selector, you'll see a device selector
2. Click on it and look for **"My Mac (Designed for iPad)"** or **"Mac"** in the list
   - It should appear under the "Mac" section
   - If you don't see it, make sure you're running macOS 13.0+ and Xcode 15.0+

### 3. Configure Code Signing

1. In Xcode, select the **AudioVisualizerApp** project in the Project Navigator (left sidebar)
2. Select the **AudioVisualizerApp** target
3. Go to the **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Select your **Team** from the dropdown (your Apple ID)
6. Xcode will automatically create a provisioning profile

**Note:** If you see signing errors:
- Make sure you're signed in with your Apple ID in Xcode Settings
- Try changing the **Bundle Identifier** to something unique (e.g., `com.yourname.audiovisualizer`)

### 4. Build and Run

1. Click the **Play** button (▶️) in the top-left of Xcode, or press **Cmd+R**
2. Xcode will:
   - Build the project for Mac Catalyst
   - Launch the app on your Mac
   - The app will appear in a window (not full screen)

### 5. Grant Microphone Permission

When the app launches:
1. You'll see a permission dialog: **"AudioVisualizerApp" Would Like to Access the Microphone**
2. Click **OK** or **Allow**
3. If you accidentally denied it, you can grant permission later:
   - Go to **System Settings** > **Privacy & Security** > **Microphone**
   - Find **AudioVisualizerApp** and toggle it ON

### 6. Test the App

1. Click the **"Start"** button in the app
2. Speak, play music, or make sounds near your Mac's microphone
3. You should see the live waveform visualization updating in real-time
4. Click **"Stop"** to stop monitoring

## Mac-Specific Features

When running on Mac via Mac Catalyst, the app will:
- ✅ Support window resizing
- ✅ Show Mac-style window controls (red, yellow, green buttons)
- ✅ Support keyboard shortcuts
- ✅ Work with Mac's built-in microphone or external audio interfaces
- ✅ Respect Mac's system preferences for microphone access

## Troubleshooting

### "My Mac (Designed for iPad)" Not Showing in Device List

- **Check macOS version**: You need macOS 13.0 (Ventura) or later
- **Check Xcode version**: You need Xcode 15.0 or later
- **Restart Xcode**: Sometimes Xcode needs a restart to detect Mac Catalyst support
- **Check build settings**: Make sure `SUPPORTS_MACCATALYST = YES` is set (it should be after our setup)

### Code Signing Errors

**Error: "No signing certificate found"**
- Go to Xcode > Settings > Accounts
- Select your Apple ID and click "Download Manual Profiles"
- Make sure "Automatically manage signing" is checked

**Error: "Bundle identifier is already in use"**
- Change the Bundle Identifier in Signing & Capabilities tab
- Use something unique like: `com.yourname.audiovisualizer`

### App Builds but Won't Launch

- Check the console in Xcode for error messages
- Make sure microphone permission was granted
- Try a clean build: Product > Clean Build Folder (Cmd+Shift+K)

### Microphone Not Working

- **Check permissions**: System Settings > Privacy & Security > Microphone > AudioVisualizerApp (should be ON)
- **Restart the app**: Quit and reopen
- **Check hardware**: Make sure your Mac's microphone isn't muted or blocked
- **Try external microphone**: Connect a USB or Bluetooth microphone to test

### Build Errors

- **Clean build folder**: Product > Clean Build Folder (Cmd+Shift+K)
- **Restart Xcode**: Sometimes Xcode needs a restart after configuration changes
- **Check deployment target**: Make sure your Mac is running macOS 13.0 or later

## Differences from iOS/iPad

- The app runs in a resizable window (not full screen by default)
- Window controls are Mac-style (red, yellow, green buttons)
- Menu bar integration (if you add menu items)
- Different keyboard shortcuts may apply
- Microphone selection follows Mac system preferences

## Quick Checklist

- [ ] macOS 13.0+ installed
- [ ] Xcode 15.0+ installed
- [ ] Signed in to Apple ID in Xcode
- [ ] Code signing configured
- [ ] "My Mac (Designed for iPad)" selected as build target
- [ ] App built and launched
- [ ] Microphone permission granted
- [ ] App running and showing waveform

## Need Help?

If you encounter issues:
1. Check the Xcode console for error messages
2. Check System Settings > Privacy & Security > Microphone
3. Make sure all prerequisites are met
4. Try a clean build: Product > Clean Build Folder
5. Verify Mac Catalyst is enabled in build settings

Happy testing on Mac! 🎉

