#!/bin/bash

# This script creates an Xcode project by opening Xcode and providing instructions
# Since XcodeGen is not available, we'll use Xcode's built-in project creation

set -e

PROJECT_DIR="$(pwd)"
PROJECT_NAME="AudioVisualizerApp"

echo "=========================================="
echo "Creating iOS App Project: $PROJECT_NAME"
echo "=========================================="
echo ""

# Check if project already exists
if [ -d "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" ]; then
    echo "✓ Xcode project already exists!"
    echo "Opening project..."
    open "$PROJECT_NAME.xcodeproj"
    exit 0
fi

echo "Since XcodeGen is not available, please create the project manually:"
echo ""
echo "OPTION 1: Quick Setup (Recommended)"
echo "-----------------------------------"
echo "1. Open Xcode"
echo "2. File > New > Project"
echo "3. iOS > App > Next"
echo "4. Product Name: $PROJECT_NAME"
echo "5. Interface: SwiftUI"
echo "6. Language: Swift"
echo "7. Save in: $PROJECT_DIR"
echo ""
echo "8. After creation:"
echo "   - Delete ContentView.swift (if created)"
echo "   - Copy $PROJECT_DIR/AudioVisualizerApp/AudioVisualizerApp.swift"
echo "     to replace your App.swift"
echo "   - Update Info.plist with microphone permissions"
echo "   - File > Add Package Dependencies > Add Local..."
echo "   - Select: $PROJECT_DIR"
echo "   - Add AudioVisualizer product to target"
echo ""
echo "OPTION 2: Use XcodeGen (Automatic)"
echo "-----------------------------------"
echo "Install XcodeGen:"
echo "  brew install xcodegen"
echo ""
echo "Then run:"
echo "  ./setup_ios_app.sh"
echo ""

# Try to open Xcode
if command -v open &> /dev/null; then
    echo "Opening Xcode..."
    open -a Xcode "$PROJECT_DIR"
fi

