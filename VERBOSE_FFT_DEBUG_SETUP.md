# Verbose FFT Debugging Setup

This document explains how to enable verbose FFT debugging in the AudioVisualizer package.

## Overview

Most verbose FFT debugging console messages are disabled by default to reduce console noise. To enable them, you need to add a compiler flag to your Xcode project.

## How to Enable Verbose FFT Debugging

Since this is a Swift Package, you need to add the compiler flag in the **consuming Xcode project** (the app that uses this package), not in the package itself.

### Steps:

1. **Open your Xcode project** that uses the AudioVisualizer package

2. **Select your project** in the Project Navigator (left sidebar)

3. **Select your app target** (not the package target)

4. **Go to Build Settings** tab

5. **Search for "Other Swift Flags"** or navigate to:
   - **Swift Compiler - Custom Flags** → **Other Swift Flags**

6. **Add the flag**:
   - Click the `+` button to add a new flag
   - For **Debug** configuration, add: `-D VERBOSE_FFT_DEBUG`
   - (Optional) For **Release** configuration, add the same flag if you want verbose debugging in release builds

   Alternatively, you can add it to both configurations at once by selecting "Any Architecture | Any SDK"

7. **Clean and rebuild** your project (Product → Clean Build Folder, then build again)

## What Gets Enabled

When `VERBOSE_FFT_DEBUG` is enabled, the following debug messages will appear in the console:

- Raw DFT output (real/imaginary pairs)
- Full magnitude output from DFT
- Mirroring checks (comparing bin k with bin N-k)
- Detailed FFT analysis (input statistics, frequency bins, magnitude distribution)
- File save confirmations for debug text files

## What Stays Enabled

The following messages are **always enabled** (not controlled by the flag) as they indicate important errors or warnings:

- FFT setup failures
- Band quantity warnings
- FFT processing errors
- Empty magnitude array warnings

## Debug Files

Debug text files are still saved to the Documents directory even when verbose logging is disabled, as they are less intrusive than console spam. The file save confirmation messages are only shown when verbose debugging is enabled.

