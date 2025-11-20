#!/bin/bash

# HLSL to Metal Shader Converter Build Script
# This script automatically converts .hlsl shader files to .metal files during build

set -e

# Colors for output (only if running in a TTY)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    # No colors when running in Xcode build (non-interactive)
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
SHADERS_DIR="$PROJECT_ROOT/Sources/AudioVisualizer/Shaders"
SOURCE_DIR="$PROJECT_ROOT/Sources/AudioVisualizer"

echo -e "${GREEN}HLSL to Metal Converter${NC}"
echo "================================"
echo "Shaders directory: $SHADERS_DIR"
echo ""

# Check if shaders directory exists
if [ ! -d "$SHADERS_DIR" ]; then
    echo -e "${RED}Error: Shaders directory not found at $SHADERS_DIR${NC}"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to convert HLSL to Metal using SPIRV-Cross (if available)
convert_with_spirv_cross() {
    local hlsl_file="$1"
    local metal_file="$2"
    
    if ! command_exists dxc; then
        return 1
    fi
    
    if ! command_exists spirv-cross; then
        return 1
    fi
    
    echo "Converting $hlsl_file using SPIRV-Cross..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    SPIRV_FILE="$TEMP_DIR/$(basename "$hlsl_file" .hlsl).spv"
    
    # Compile HLSL to SPIR-V
    # Note: This requires HLSL shader to have proper entry points
    # For compute shaders: -T cs_6_0
    # For vertex shaders: -T vs_6_0
    # For pixel/fragment shaders: -T ps_6_0
    
    # Try different shader types
    if dxc -T cs_6_0 -E ProcessAudioData -spirv -Fo "$SPIRV_FILE" "$hlsl_file" 2>/dev/null; then
        echo "  Compiled to SPIR-V (compute shader)"
    elif dxc -T vs_6_0 -E HistogramVertex -spirv -Fo "$SPIRV_FILE" "$hlsl_file" 2>/dev/null; then
        echo "  Compiled to SPIR-V (vertex shader)"
    elif dxc -T ps_6_0 -E RenderHistogramBar -spirv -Fo "$SPIRV_FILE" "$hlsl_file" 2>/dev/null; then
        echo "  Compiled to SPIR-V (pixel shader)"
    else
        echo -e "${YELLOW}  Warning: Could not compile HLSL to SPIR-V (may need manual entry point specification)${NC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Convert SPIR-V to MSL
    if spirv-cross "$SPIRV_FILE" --msl --output "$metal_file"; then
        echo -e "${GREEN}  Successfully converted to $metal_file${NC}"
        rm -rf "$TEMP_DIR"
        return 0
    else
        echo -e "${YELLOW}  Warning: SPIRV-Cross conversion failed${NC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
}

# Function to convert HLSL to Metal using Metal Shader Converter (if available)
convert_with_metal_converter() {
    local hlsl_file="$1"
    local metal_file="$2"
    
    # Check for metal-shaderconverter
    if ! command_exists metal-shaderconverter; then
        # Check common installation locations
        if [ -f "/usr/local/bin/metal-shaderconverter" ]; then
            METAL_CONVERTER="/usr/local/bin/metal-shaderconverter"
        elif [ -f "$HOME/.local/bin/metal-shaderconverter" ]; then
            METAL_CONVERTER="$HOME/.local/bin/metal-shaderconverter"
        else
            return 1
        fi
    else
        METAL_CONVERTER="metal-shaderconverter"
    fi
    
    # Check for dxc (DirectX Shader Compiler) - required for HLSL to DXIL conversion
    if ! command_exists dxc; then
        # Check common installation locations
        if [ -f "/usr/local/bin/dxc" ]; then
            DXC="/usr/local/bin/dxc"
        elif [ -f "/opt/homebrew/bin/dxc" ]; then
            DXC="/opt/homebrew/bin/dxc"
        elif [ -d "/usr/local/lib/dxc" ]; then
            # dxc might be in a subdirectory
            DXC=$(find /usr/local/lib/dxc -name "dxc" -type f 2>/dev/null | head -1)
        else
            echo -e "${YELLOW}  dxc (DirectX Shader Compiler) not found${NC}"
            echo -e "${YELLOW}  Install from: https://github.com/microsoft/DirectXShaderCompiler${NC}"
            return 1
        fi
    else
        DXC="dxc"
    fi
    
    echo "Converting $hlsl_file using Metal Shader Converter..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    DXIL_FILE="$TEMP_DIR/$(basename "$hlsl_file" .hlsl).dxil"
    
    # Compile HLSL to DXIL
    echo "  Compiling HLSL to DXIL using dxc..."
    if "$DXC" -T cs_6_0 -E ProcessAudioData -Fo "$DXIL_FILE" "$hlsl_file" 2>&1; then
        echo "  ✓ Compiled to DXIL (compute shader)"
    elif "$DXC" -T vs_6_0 -E HistogramVertex -Fo "$DXIL_FILE" "$hlsl_file" 2>&1; then
        echo "  ✓ Compiled to DXIL (vertex shader)"
    elif "$DXC" -T ps_6_0 -E RenderHistogramBar -Fo "$DXIL_FILE" "$hlsl_file" 2>&1; then
        echo "  ✓ Compiled to DXIL (pixel shader)"
    else
        echo -e "${YELLOW}  Warning: Could not compile HLSL to DXIL${NC}"
        echo -e "${YELLOW}  Check that your HLSL file has the correct entry points${NC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Convert DXIL to Metal
    if "$METAL_CONVERTER" -o "$metal_file" "$DXIL_FILE" 2>/dev/null; then
        echo -e "${GREEN}  Successfully converted to $metal_file${NC}"
        rm -rf "$TEMP_DIR"
        return 0
    else
        echo -e "${YELLOW}  Warning: Metal Shader Converter failed${NC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
}

# Function to check file size (safeguard against infinite loops)
check_file_size() {
    local file="$1"
    local max_size_mb=10  # 10MB max file size
    
    if [ -f "$file" ]; then
        local size_bytes=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        local size_mb=$((size_bytes / 1024 / 1024))
        
        if [ "$size_mb" -gt "$max_size_mb" ]; then
            echo -e "${RED}  ERROR: File $file is too large (${size_mb}MB). Possible infinite loop detected!${NC}"
            return 1
        fi
    fi
    return 0
}

# Function to create a basic MSL file from HLSL (fallback)
create_fallback_metal() {
    local hlsl_file="$1"
    local metal_file="$2"
    
    # CRITICAL: Check if metal_file already exists - if so, preserve it
    if [ -f "$metal_file" ]; then
        # Check file size to detect corruption from previous runs
        if ! check_file_size "$metal_file"; then
            echo -e "${RED}  Removing corrupted file and creating new one...${NC}"
            rm -f "$metal_file"
        else
            echo -e "${GREEN}  Metal file exists and will be preserved${NC}"
            echo -e "${YELLOW}  Note: Install conversion tools (dxc + metal-shaderconverter or spirv-cross) for automatic conversion${NC}"
            return 0
        fi
    fi
    
    echo -e "${YELLOW}Creating fallback Metal file from HLSL (manual conversion may be needed)${NC}"
    
    # Use a temporary file to avoid any issues
    local temp_file="${metal_file}.tmp"
    
    # Create the Metal file header
    cat > "$temp_file" << METAL_HEADER
#include <metal_stdlib>
using namespace metal;

// NOTE: This file was auto-generated from HLSL source
// Manual conversion and testing may be required
// Original HLSL file: $(basename "$hlsl_file")
//
// This is a placeholder file. To enable automatic conversion:
// 1. Install Metal Shader Converter from Apple, OR
// 2. Install SPIRV-Cross + DirectX Shader Compiler (dxc)
//
// See Scripts/README_HLSL_CONVERSION.md for details

METAL_HEADER
    
    # Add a note about manual conversion
    cat >> "$temp_file" << 'METAL_FOOTER'

// Placeholder implementation - replace with actual Metal shader code
// Refer to the original HLSL file for the shader logic

METAL_FOOTER
    
    # Check the temp file size before moving
    if ! check_file_size "$temp_file"; then
        rm -f "$temp_file"
        echo -e "${RED}  ERROR: Failed to create fallback file${NC}"
        return 1
    fi
    
    # Move temp file to final location atomically
    mv "$temp_file" "$metal_file"
    
    echo -e "${YELLOW}  Created fallback file: $metal_file${NC}"
    echo -e "${YELLOW}  Note: This is a placeholder. Install conversion tools for automatic conversion.${NC}"
}

# Process all HLSL files
CONVERTED=0
SKIPPED=0

for hlsl_file in "$SHADERS_DIR"/*.hlsl; do
    # Check if file exists (handles case where no .hlsl files exist)
    [ -f "$hlsl_file" ] || continue
    
    # Output Metal file to source directory (not Shaders directory)
    # This is where Xcode/Swift Package Manager expects Metal files to be compiled
    metal_file="$SOURCE_DIR/$(basename "${hlsl_file%.hlsl}").metal"
    filename=$(basename "$hlsl_file")
    
    echo "Processing: $filename"
    
    # SAFETY CHECK: Verify metal_file is different from hlsl_file
    if [ "$hlsl_file" = "$metal_file" ]; then
        echo -e "${RED}  ERROR: Output file same as input file! Skipping...${NC}"
        continue
    fi
    
    # SAFETY CHECK: Check existing metal file size before processing
    if [ -f "$metal_file" ]; then
        if ! check_file_size "$metal_file"; then
            echo -e "${RED}  Removing corrupted file...${NC}"
            rm -f "$metal_file"
        elif [ "$hlsl_file" -ot "$metal_file" ]; then
            echo "  Metal file is up to date, skipping..."
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi
    
    # Try conversion methods in order of preference
    SUCCESS=0
    
    # Method 1: Try Metal Shader Converter (Apple's official tool)
    if convert_with_metal_converter "$hlsl_file" "$metal_file"; then
        # Verify the output file is reasonable
        if check_file_size "$metal_file"; then
            SUCCESS=1
            CONVERTED=$((CONVERTED + 1))
        else
            echo -e "${RED}  Conversion produced invalid file, removing...${NC}"
            rm -f "$metal_file"
        fi
    # Method 2: Try SPIRV-Cross
    elif convert_with_spirv_cross "$hlsl_file" "$metal_file"; then
        # Verify the output file is reasonable
        if check_file_size "$metal_file"; then
            SUCCESS=1
            CONVERTED=$((CONVERTED + 1))
        else
            echo -e "${RED}  Conversion produced invalid file, removing...${NC}"
            rm -f "$metal_file"
        fi
    fi
    
    # Fallback: Create a placeholder file (only if conversion failed)
    if [ $SUCCESS -eq 0 ]; then
        create_fallback_metal "$hlsl_file" "$metal_file"
        SKIPPED=$((SKIPPED + 1))
    fi
    
    echo ""
done

# Summary
echo "================================"
if [ $CONVERTED -gt 0 ]; then
    echo -e "${GREEN}Successfully converted $CONVERTED shader(s)${NC}"
fi
if [ $SKIPPED -gt 0 ]; then
    echo -e "${YELLOW}Skipped or used fallback for $SKIPPED shader(s)${NC}"
fi

# Check for conversion tools
echo ""
echo "Conversion tool status:"
if command_exists dxc; then
    echo -e "${GREEN}✓ dxc (DirectX Shader Compiler) found${NC}"
else
    echo -e "${YELLOW}✗ dxc not found (install from: https://github.com/microsoft/DirectXShaderCompiler)${NC}"
fi

if command_exists metal-shaderconverter || [ -f "/usr/local/bin/metal-shaderconverter" ]; then
    echo -e "${GREEN}✓ metal-shaderconverter found${NC}"
else
    echo -e "${YELLOW}✗ metal-shaderconverter not found (download from: https://developer.apple.com/metal/shader-converter/)${NC}"
fi

if command_exists spirv-cross; then
    echo -e "${GREEN}✓ spirv-cross found${NC}"
else
    echo -e "${YELLOW}✗ spirv-cross not found (install via: brew install spirv-cross or build from source)${NC}"
fi

echo ""
if [ $CONVERTED -eq 0 ] && [ $SKIPPED -gt 0 ]; then
    echo "Note: Conversion skipped because:"
    if ! command_exists dxc && [ ! -f "/usr/local/bin/dxc" ] && [ ! -f "/opt/homebrew/bin/dxc" ]; then
        echo "  - dxc (DirectX Shader Compiler) is not installed"
    fi
    if ! command_exists metal-shaderconverter && [ ! -f "/usr/local/bin/metal-shaderconverter" ]; then
        echo "  - metal-shaderconverter is not installed"
    fi
    echo ""
    echo "Your existing Metal files are being preserved."
    echo "To enable automatic conversion, install dxc from:"
    echo "  https://github.com/microsoft/DirectXShaderCompiler/releases"
else
    echo "For automatic conversion, install one of the following:"
    echo "  1. Metal Shader Converter (recommended for Apple platforms)"
    echo "  2. SPIRV-Cross + DirectX Shader Compiler (dxc)"
fi

exit 0

