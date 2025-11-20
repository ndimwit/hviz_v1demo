# Adding HLSL Conversion Build Phase to Xcode

The conversion script needs to be added as a build phase in Xcode to run automatically during builds.

## Quick Steps

1. **Open your project in Xcode**
   ```
   open AudioVisualizerApp.xcodeproj
   ```

2. **Select your target**
   - Click on the project in the navigator
   - Select the "AudioVisualizerApp" target

3. **Go to Build Phases tab**
   - Click on the target
   - Select the "Build Phases" tab at the top

4. **Add Run Script Phase**
   - Click the **+** button at the top left of the Build Phases section
   - Select **New Run Script Phase**

5. **Configure the script**
   - Expand the new "Run Script" phase
   - In the script editor, paste:
     ```bash
     "${SRCROOT}/Scripts/convert_hlsl_to_metal.sh"
     ```
   - **Important**: Make sure "Shell" is set to `/bin/sh`
   - Optionally check "Show environment variables in build log" for debugging

6. **Move the phase**
   - Drag the "Run Script" phase to be **before** "Compile Sources"
   - This ensures shaders are converted before compilation

7. **Test it**
   - Build your project (⌘B)
   - Check the build log for "HLSL to Metal Converter" output

## Verification

After adding the build phase, you should see output like this in the build log:

```
HLSL to Metal Converter
================================
Shaders directory: /path/to/Sources/AudioVisualizer/Shaders
Processing: HLSLVisualizerShader.hlsl
...
```

## Troubleshooting

### Script not running
- Verify the script path is correct: `"${SRCROOT}/Scripts/convert_hlsl_to_metal.sh"`
- Check that the script has execute permissions: `chmod +x Scripts/convert_hlsl_to_metal.sh`
- Ensure the Run Script phase is before "Compile Sources"

### dxc not found
The script requires `dxc` (DirectX Shader Compiler) to convert HLSL to DXIL. Install it:

**Option 1: Homebrew (if available)**
```bash
brew install directx-shader-compiler
```

**Option 2: Manual installation**
1. Download from: https://github.com/microsoft/DirectXShaderCompiler/releases
2. Extract and add `dxc` to your PATH or `/usr/local/bin/`

**Option 3: Build from source**
See: https://github.com/microsoft/DirectXShaderCompiler

### Conversion errors
- Check that your HLSL shaders have proper entry points
- Verify shader profiles match (cs_6_0, vs_6_0, ps_6_0)
- Some HLSL features may not translate directly to MSL

## Alternative: Manual Conversion

If you prefer not to set up automatic conversion, you can:
1. Run the script manually before building: `./Scripts/convert_hlsl_to_metal.sh`
2. Or keep the existing `.metal` files and update them manually when needed

