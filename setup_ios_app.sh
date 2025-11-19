#!/bin/bash

# Script to set up the iOS app project
# This will either use XcodeGen if available, or guide you through manual setup

set -e

PROJECT_DIR="$(pwd)"
PROJECT_NAME="AudioVisualizerApp"

echo "Setting up iOS app project: $PROJECT_NAME"
echo ""

# Check if XcodeGen is installed
if command -v xcodegen &> /dev/null; then
    echo "✓ XcodeGen found. Generating Xcode project..."
    xcodegen generate
    echo ""
    echo "✓ Xcode project generated successfully!"
    echo "Opening project in Xcode..."
    open "$PROJECT_NAME.xcodeproj"
    exit 0
fi

# XcodeGen not found - provide manual instructions
echo "XcodeGen not found. Installing it is recommended for automatic project generation."
echo ""
echo "To install XcodeGen:"
echo "  brew install xcodegen"
echo ""
echo "Or follow these manual steps:"
echo ""
echo "1. Open Xcode"
echo "2. File > New > Project"
echo "3. Choose iOS > App"
echo "4. Product Name: $PROJECT_NAME"
echo "5. Interface: SwiftUI"
echo "6. Language: Swift"
echo "7. Save in: $PROJECT_DIR"
echo ""
echo "8. After project creation:"
echo "   a. Delete default ContentView.swift if created"
echo "   b. Copy AudioVisualizerApp/AudioVisualizerApp.swift to your app target"
echo "   c. Update Info.plist with microphone permissions (see AudioVisualizerApp/Info.plist)"
echo "   d. File > Add Package Dependencies > Add Local..."
echo "   e. Select: $PROJECT_DIR"
echo "   f. Add AudioVisualizer product to your app target"
echo ""
echo "9. Build and run on a physical iOS device (simulator doesn't support microphone)"
echo ""

# Try to open Xcode
if command -v open &> /dev/null; then
    read -p "Open Xcode now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open -a Xcode
    fi
fi

