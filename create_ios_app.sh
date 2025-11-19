#!/bin/bash

# Script to create an iOS app Xcode project
# This script creates the project structure and opens it in Xcode

set -e

PROJECT_NAME="AudioVisualizerApp"
PROJECT_DIR="$(pwd)"
APP_DIR="$PROJECT_DIR/$PROJECT_NAME"

echo "Creating iOS app project structure..."

# Create the app directory if it doesn't exist
mkdir -p "$APP_DIR"

# Check if .xcodeproj already exists
if [ -d "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" ]; then
    echo "Xcode project already exists. Opening it..."
    open "$PROJECT_DIR/$PROJECT_NAME.xcodeproj"
    exit 0
fi

echo ""
echo "To create the Xcode project, please follow these steps:"
echo ""
echo "1. Open Xcode"
echo "2. File > New > Project"
echo "3. Choose iOS > App"
echo "4. Product Name: $PROJECT_NAME"
echo "5. Interface: SwiftUI"
echo "6. Language: Swift"
echo "7. Save it in: $PROJECT_DIR"
echo ""
echo "8. After creating the project:"
echo "   - Delete the default ContentView.swift (if created)"
echo "   - Copy $APP_DIR/AudioVisualizerApp.swift to your app target"
echo "   - Copy $APP_DIR/Info.plist settings to your project's Info.plist"
echo "   - File > Add Package Dependencies > Add Local..."
echo "   - Select: $PROJECT_DIR"
echo "   - Add the AudioVisualizer product to your app target"
echo ""
echo "Alternatively, you can use Xcode's File > Open to open Package.swift"
echo "and then create an app target within that workspace."
echo ""

# Try to open Xcode
if command -v open &> /dev/null; then
    echo "Opening Xcode..."
    open -a Xcode
fi

