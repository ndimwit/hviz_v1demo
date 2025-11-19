# Testing on iPhone

## Prerequisites

1. **Physical iPhone** (iOS 17.0 or later)
2. **USB Cable** to connect iPhone to Mac
3. **Apple Developer Account** (free account works for development)
4. **Xcode** installed on your Mac

## Step-by-Step Instructions

### 1. Connect Your iPhone

- Connect your iPhone to your Mac using a USB cable
- Unlock your iPhone
- If prompted on iPhone, tap **"Trust This Computer"** and enter your passcode

### 2. Enable Developer Mode on iPhone

**For iOS 16+ (Required):**

1. On your iPhone, go to **Settings** > **Privacy & Security**
2. Scroll down to find **Developer Mode**
3. Toggle **Developer Mode** ON
4. Your iPhone will restart
5. After restart, confirm you want to enable Developer Mode

### 3. Configure Your Apple ID in Xcode

1. Open Xcode
2. Go to **Xcode** > **Settings** (or **Preferences** on older versions)
3. Click the **Accounts** tab
4. Click the **+** button and select **Apple ID**
5. Sign in with your Apple ID
6. Select your account and click **Download Manual Profiles** (if needed)

### 4. Select Your iPhone as the Build Target

1. Open the project: `AudioVisualizerApp.xcodeproj` in Xcode
2. At the top of Xcode, next to the scheme selector, you'll see a device selector
3. Click on it and select your connected iPhone from the list
   - It should show something like: **"Your Name's iPhone"** or **"iPhone (iOS 17.x)"**

### 5. Configure Code Signing

1. In Xcode, select the **AudioVisualizerApp** project in the Project Navigator (left sidebar)
2. Select the **AudioVisualizerApp** target
3. Go to the **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Select your **Team** from the dropdown (your Apple ID)
6. Xcode will automatically create a provisioning profile

**Note:** If you see signing errors:
- Make sure you're signed in with your Apple ID in Xcode Settings
- Try changing the **Bundle Identifier** to something unique (e.g., `com.yourname.audiovisualizer`)

### 6. Build and Run

1. Click the **Play** button (▶️) in the top-left of Xcode, or press **Cmd+R**
2. Xcode will:
   - Build the project
   - Install the app on your iPhone
   - Launch the app

### 7. Trust the Developer Certificate (First Time Only)

**On your iPhone:**
1. Go to **Settings** > **General** > **VPN & Device Management** (or **Device Management**)
2. Tap on your Apple ID under **Developer App**
3. Tap **Trust "[Your Apple ID]"**
4. Confirm by tapping **Trust**

### 8. Grant Microphone Permission

When the app launches:
1. You'll see a permission dialog: **"AudioVisualizerApp" Would Like to Access the Microphone**
2. Tap **OK** or **Allow**
3. The app will now have access to your microphone

### 9. Test the App

1. Tap the **"Start"** button in the app
2. Speak, play music, or make sounds near your iPhone
3. You should see the live waveform visualization updating in real-time
4. Tap **"Stop"** to stop monitoring

## Troubleshooting

### "No devices found" or iPhone not showing in device list

- **Check USB connection**: Try a different cable or USB port
- **Unlock iPhone**: Make sure your iPhone is unlocked
- **Trust computer**: Make sure you tapped "Trust This Computer" on iPhone
- **Restart Xcode**: Quit and reopen Xcode
- **Check Developer Mode**: Make sure Developer Mode is enabled (iOS 16+)

### Code Signing Errors

**Error: "No signing certificate found"**
- Go to Xcode > Settings > Accounts
- Select your Apple ID and click "Download Manual Profiles"
- Make sure "Automatically manage signing" is checked

**Error: "Bundle identifier is already in use"**
- Change the Bundle Identifier in Signing & Capabilities tab
- Use something unique like: `com.yourname.audiovisualizer`

### App Installs but Crashes Immediately

- Check the console in Xcode for error messages
- Make sure microphone permission was granted
- Try deleting the app from iPhone and reinstalling

### Microphone Not Working

- **Check permissions**: Settings > Privacy & Security > Microphone > AudioVisualizerApp (should be ON)
- **Restart the app**: Force quit and reopen
- **Check hardware**: Make sure your iPhone's microphone isn't blocked

### Build Errors

- **Clean build folder**: Product > Clean Build Folder (Cmd+Shift+K)
- **Restart Xcode**: Sometimes Xcode needs a restart after adding packages
- **Check deployment target**: Make sure your iPhone is running iOS 17.0 or later

## Alternative: Wireless Debugging (iOS 16+)

You can also connect wirelessly:

1. Connect iPhone via USB first (one time setup)
2. In Xcode, go to **Window** > **Devices and Simulators**
3. Select your iPhone
4. Check **"Connect via network"**
5. Disconnect USB cable
6. Your iPhone should now appear in the device list wirelessly

## Quick Checklist

- [ ] iPhone connected via USB
- [ ] iPhone unlocked and trusted computer
- [ ] Developer Mode enabled (iOS 16+)
- [ ] Signed in to Apple ID in Xcode
- [ ] Code signing configured
- [ ] iPhone selected as build target
- [ ] App built and installed
- [ ] Developer certificate trusted on iPhone
- [ ] Microphone permission granted
- [ ] App running and showing waveform

## Need Help?

If you encounter issues:
1. Check the Xcode console for error messages
2. Check the device console: Window > Devices and Simulators > View Device Logs
3. Make sure all prerequisites are met
4. Try a clean build: Product > Clean Build Folder

Happy testing! 🎉

