# Entitlements Check for Mac Catalyst

## Critical: Audio Input Entitlement

The HALC errors suggest the app might be missing the **Audio Input** entitlement required for Mac Catalyst apps to access the microphone.

## How to Check/Add Entitlements in Xcode

1. **Open your Xcode project**
2. **Select your app target** (AudioVisualizerApp)
3. **Go to "Signing & Capabilities" tab**
4. **Click "+ Capability"**
5. **Add "Audio Input" capability**
   - This adds the `com.apple.security.device.audio-input` entitlement
6. **Under "Hardened Runtime"** (if visible), ensure:
   - "Audio Input" is checked/enabled

## Alternative: Check Entitlements File

If you have an `.entitlements` file, it should contain:
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

## Why This Matters

On macOS/Mac Catalyst, apps need explicit entitlements to access:
- Microphone (Audio Input entitlement)
- Camera
- Other hardware resources

Without the Audio Input entitlement, the HAL (Hardware Abstraction Layer) will reject access attempts, causing the HALC_ProxySystem errors you're seeing.

## After Adding Entitlement

1. Clean build folder (Cmd+Shift+K)
2. Rebuild the app
3. Test again

The HALC errors should disappear once the entitlement is properly configured.

