# Fixing Metal Toolchain Installation

## Error Message
```
The Metal Toolchain was not installed and could not compile the Metal source files. 
Download the Metal Toolchain from Xcode > Settings > Components and try again.
```

## Solution

### Option 1: Install via Xcode (Recommended)

1. **Open Xcode**
2. Go to **Xcode** → **Settings** (or **Preferences** on older versions)
3. Click on the **Components** tab (or **Platforms** in older versions)
4. Find **Metal Toolchain** in the list
5. Click the **Download** button next to it
6. Wait for the download and installation to complete
7. Restart Xcode if prompted

### Option 2: Install via Command Line

If you prefer command line:

```bash
xcode-select --install
```

Then follow the prompts to install command line tools.

### Option 3: Verify Installation

After installation, verify the Metal compiler is available:

```bash
xcrun --find metal
```

This should return a path like: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/usr/bin/metal`

### Option 4: Check Xcode Command Line Tools

Make sure Xcode command line tools are properly configured:

```bash
xcode-select -p
```

This should return something like: `/Applications/Xcode.app/Contents/Developer`

If it doesn't, set it:
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

## After Installation

1. **Clean Build Folder**: In Xcode, press `⌘⇧K` (Cmd+Shift+K)
2. **Rebuild**: Press `⌘B` (Cmd+B)

The Metal shaders should now compile successfully.

## Troubleshooting

### Still getting errors?
- Make sure you're using a recent version of Xcode (14.0+)
- Try restarting Xcode
- Check that your Xcode license is accepted: `sudo xcodebuild -license accept`

### Alternative: Use Xcode Beta
If you're using Xcode beta, make sure the beta version has the Metal Toolchain installed.

