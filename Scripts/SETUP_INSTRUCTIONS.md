# HLSL to Metal Conversion Setup - Complete Instructions

## Current Status

✅ **Metal Shader Converter**: Installed at `/usr/local/bin/metal-shaderconverter`  
❌ **DirectX Shader Compiler (dxc)**: Not installed (required)  
❌ **Build Phase**: Not added to Xcode project yet

## What You Need

The conversion process requires **two tools**:

1. **dxc** (DirectX Shader Compiler) - Converts HLSL → DXIL
2. **metal-shaderconverter** - Converts DXIL → Metal ✅ (already installed)

## Step 1: Install dxc

Since Homebrew doesn't have a directx-shader-compiler formula, you need to install manually:

### Option A: Download Pre-built Binary (Easiest)

1. Go to: https://github.com/microsoft/DirectXShaderCompiler/releases
2. Download the latest release for macOS (look for `dxc-macos-*.tar.gz`)
3. Extract the archive
4. Copy the `dxc` binary to `/usr/local/bin/`:
   ```bash
   sudo cp path/to/extracted/dxc /usr/local/bin/
   sudo chmod +x /usr/local/bin/dxc
   ```

### Option B: Build from Source

See: https://github.com/microsoft/DirectXShaderCompiler#building

## Step 2: Verify Installation

Run this to test:
```bash
cd /Users/brianwong/projects/hviz_v1demo
./Scripts/convert_hlsl_to_metal.sh
```

You should see:
```
✓ dxc (DirectX Shader Compiler) found
✓ metal-shaderconverter found
```

## Step 3: Add Build Phase to Xcode

1. Open Xcode: `open AudioVisualizerApp.xcodeproj`
2. Select the **AudioVisualizerApp** target
3. Go to **Build Phases** tab
4. Click **+** → **New Run Script Phase**
5. Expand the new phase and add:
   ```bash
   "${SRCROOT}/Scripts/convert_hlsl_to_metal.sh"
   ```
6. **Important**: Drag this phase to be **before** "Compile Sources"
7. Build (⌘B) to test

## Step 4: Test the Conversion

To force a conversion (even if Metal file exists), temporarily delete the Metal file:
```bash
rm Sources/AudioVisualizer/Shaders/HLSLVisualizerShader.metal
./Scripts/convert_hlsl_to_metal.sh
```

You should see:
```
Converting HLSLVisualizerShader.hlsl using Metal Shader Converter...
  Compiling HLSL to DXIL using dxc...
  ✓ Compiled to DXIL (compute shader)
  ✓ Successfully converted to .../HLSLVisualizerShader.metal
```

## Troubleshooting

### "dxc not found"
- Verify it's in PATH: `which dxc`
- Or check: `ls -la /usr/local/bin/dxc`
- If missing, install using Step 1 above

### "Could not compile HLSL to DXIL"
- Your HLSL file might not have the expected entry points
- Check the HLSL file for function names like `ProcessAudioData`, `HistogramVertex`, `RenderHistogramBar`
- The script tries different shader types automatically

### Script not running during build
- Verify the build phase is added (see Step 3)
- Check that the script path is correct: `"${SRCROOT}/Scripts/convert_hlsl_to_metal.sh"`
- Ensure the phase runs before "Compile Sources"
- Check build log for errors

### Conversion produces errors
- Some HLSL features don't translate directly to Metal
- You may need to manually adjust the converted Metal code
- The existing `HLSLVisualizerShader.metal` file serves as a reference

## Quick Test Command

After installing dxc, test everything:
```bash
cd /Users/brianwong/projects/hviz_v1demo
rm -f Sources/AudioVisualizer/Shaders/HLSLVisualizerShader.metal
./Scripts/convert_hlsl_to_metal.sh
```

