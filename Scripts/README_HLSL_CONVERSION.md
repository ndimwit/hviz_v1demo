# HLSL to Metal Automatic Conversion Setup

This directory contains scripts for automatically converting HLSL shader files to Metal Shading Language (MSL) during the build process.

## Quick Setup

### Option 1: Add Build Phase in Xcode (Recommended)

1. Open your project in Xcode
2. Select your target (AudioVisualizerApp)
3. Go to **Build Phases** tab
4. Click the **+** button and select **New Run Script Phase**
5. Move the new script phase to run **before** "Compile Sources"
6. In the script editor, add:

```bash
"${SRCROOT}/Scripts/convert_hlsl_to_metal.sh"
```

7. Make sure "Show environment variables in build log" is checked (optional, for debugging)
8. Build your project - the script will run automatically

### Option 2: Manual Execution

Run the script manually before building:

```bash
./Scripts/convert_hlsl_to_metal.sh
```

## Required Tools

The script will attempt to use one of these conversion tools (in order of preference):

1. **Metal Shader Converter** (Apple's official tool - recommended)
   - Download from: https://developer.apple.com/metal/shader-converter/
   - Install to `/usr/local/bin/` or ensure it's in your PATH

2. **SPIRV-Cross + DirectX Shader Compiler (dxc)**
   - Install SPIRV-Cross: `brew install spirv-cross` or build from source
   - Install dxc: Download from https://github.com/microsoft/DirectXShaderCompiler
   - Ensure both are in your PATH

3. **Fallback Mode**
   - If no conversion tools are available, the script creates a placeholder Metal file
   - You'll need to manually convert or use the existing `.metal` file

## How It Works

1. The script scans `Sources/AudioVisualizer/Shaders/` for `.hlsl` files
2. For each `.hlsl` file, it checks if a corresponding `.metal` file exists and is up-to-date
3. If the `.hlsl` file is newer, it attempts conversion using available tools
4. The converted `.metal` file is placed in the same directory
5. Xcode automatically compiles `.metal` files into the default Metal library

## Conversion Process

The script supports two conversion paths:

### Path 1: HLSL → DXIL → MSL (Metal Shader Converter)
```
.hlsl → [dxc] → .dxil → [metal-shaderconverter] → .metal
```

### Path 2: HLSL → SPIR-V → MSL (SPIRV-Cross)
```
.hlsl → [dxc] → .spv → [spirv-cross] → .metal
```

## Troubleshooting

### Script not running
- Ensure the script has execute permissions: `chmod +x Scripts/convert_hlsl_to_metal.sh`
- Check that the script path in Xcode build phase is correct
- Verify the script phase runs before "Compile Sources"

### Conversion tools not found
- Install one of the required tools (see above)
- Ensure tools are in your PATH or update the script with custom paths
- The script will use fallback mode if no tools are available

### Conversion errors
- Check that your HLSL shaders have proper entry points
- Verify shader profiles match (cs_6_0, vs_6_0, ps_6_0, etc.)
- Some HLSL features may not translate directly to MSL - manual adjustment may be needed

### Metal shaders not loading
- Ensure `.metal` files are included in your target
- Check that shader function names match between HLSL and MSL
- Verify the Metal library is being loaded correctly in your code

## File Structure

```
Sources/AudioVisualizer/Shaders/
├── HLSLVisualizerShader.hlsl    # Original HLSL source
├── HLSLVisualizerShader.metal   # Auto-generated Metal (or manual)
└── MSLVisualizerShader.metal    # Direct MSL implementation
```

## Notes

- The existing `HLSLVisualizerShader.metal` file serves as a reference implementation
- If automatic conversion fails, the script preserves the existing `.metal` file
- Always test converted shaders thoroughly - automatic conversion may require manual adjustments
- The `.hlsl` file is kept for reference and potential future cross-platform use

