#!/bin/bash

# Helper script to add the HLSL conversion build phase to Xcode project
# This script modifies the project.pbxproj file to add a run script phase

set -e

PROJECT_FILE="AudioVisualizerApp.xcodeproj/project.pbxproj"
SCRIPT_PATH="Scripts/convert_hlsl_to_metal.sh"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project file not found at $PROJECT_FILE"
    exit 1
fi

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Conversion script not found at $SCRIPT_PATH"
    exit 1
fi

echo "This script will help you add the HLSL conversion build phase."
echo ""
echo "For safety, it's recommended to add the build phase manually in Xcode:"
echo "  1. Open Xcode"
echo "  2. Select your target"
echo "  3. Go to Build Phases"
echo "  4. Click + and add 'New Run Script Phase'"
echo "  5. Add: \${SRCROOT}/$SCRIPT_PATH"
echo "  6. Move it before 'Compile Sources'"
echo ""
read -p "Do you want to proceed with automatic addition? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Please add the build phase manually."
    exit 0
fi

echo "Note: Automatic project file modification is complex and error-prone."
echo "It's safer to add the build phase manually in Xcode."
echo ""
echo "If you still want to proceed, you'll need to:"
echo "  1. Use Xcode's UI to add the build phase (recommended)"
echo "  2. Or manually edit project.pbxproj (advanced, not recommended)"
echo ""
echo "The script path to use in Xcode is:"
echo "  \${SRCROOT}/$SCRIPT_PATH"

exit 0

