#!/bin/bash

# Audio Visualizer Setup Script
# This script checks for and installs all required dependencies for building and running the app

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

echo "=========================================="
echo "Audio Visualizer Setup Script"
echo "=========================================="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script is designed for macOS only."
    exit 1
fi

# Track what needs to be installed
NEEDS_XCODE=false
NEEDS_BREW=false
NEEDS_XCODEGEN=false
NEEDS_PYTHON=false
NEEDS_PYTHON_DEPS=false

# 1. Check for Xcode Command Line Tools
print_info "Checking for Xcode Command Line Tools..."
if ! xcode-select -p &> /dev/null; then
    print_warning "Xcode Command Line Tools not found"
    NEEDS_XCODE=true
else
    print_status "Xcode Command Line Tools installed"
fi

# 2. Check for Xcode (full app)
print_info "Checking for Xcode app..."
if ! command -v xcodebuild &> /dev/null; then
    print_warning "Xcode app not found in PATH"
    if [ ! -d "/Applications/Xcode.app" ]; then
        print_warning "Xcode.app not found in /Applications"
        NEEDS_XCODE=true
    else
        print_status "Xcode.app found (may need to be added to PATH)"
    fi
else
    XCODE_VERSION=$(xcodebuild -version 2>&1 | head -n 1)
    print_status "Xcode found: $XCODE_VERSION"
fi

# 3. Check for Homebrew
print_info "Checking for Homebrew..."
if ! command -v brew &> /dev/null; then
    print_warning "Homebrew not found"
    NEEDS_BREW=true
else
    print_status "Homebrew installed"
fi

# 4. Check for XcodeGen (optional but recommended)
print_info "Checking for XcodeGen..."
if ! command -v xcodegen &> /dev/null; then
    print_warning "XcodeGen not found (optional but recommended for project generation)"
    NEEDS_XCODEGEN=true
else
    print_status "XcodeGen installed"
fi

# 5. Check for Python 3
print_info "Checking for Python 3..."
if ! command -v python3 &> /dev/null; then
    print_warning "Python 3 not found"
    NEEDS_PYTHON=true
else
    PYTHON_VERSION=$(python3 --version 2>&1)
    print_status "Python 3 found: $PYTHON_VERSION"
    
    # Check for required Python packages
    print_info "Checking for Python dependencies (numpy, scipy)..."
    if ! python3 -c "import numpy" &> /dev/null || ! python3 -c "import scipy" &> /dev/null; then
        print_warning "Python dependencies (numpy, scipy) not found"
        NEEDS_PYTHON_DEPS=true
    else
        print_status "Python dependencies installed"
    fi
fi

# 6. Check for Swift Package Manager
print_info "Checking for Swift Package Manager..."
if ! command -v swift &> /dev/null; then
    print_warning "Swift not found (should come with Xcode)"
    NEEDS_XCODE=true
else
    SWIFT_VERSION=$(swift --version 2>&1 | head -n 1)
    print_status "Swift found: $SWIFT_VERSION"
fi

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="

if [ "$NEEDS_XCODE" = true ] || [ "$NEEDS_BREW" = true ] || [ "$NEEDS_XCODEGEN" = true ] || [ "$NEEDS_PYTHON" = true ] || [ "$NEEDS_PYTHON_DEPS" = true ]; then
    echo ""
    print_info "The following will be installed/configured:"
    
    if [ "$NEEDS_XCODE" = true ]; then
        echo "  - Xcode Command Line Tools (required)"
    fi
    
    if [ "$NEEDS_BREW" = true ]; then
        echo "  - Homebrew (required for optional tools)"
    fi
    
    if [ "$NEEDS_XCODEGEN" = true ]; then
        echo "  - XcodeGen (optional, for automated project generation)"
    fi
    
    if [ "$NEEDS_PYTHON" = true ]; then
        echo "  - Python 3 (required for test audio generation)"
    fi
    
    if [ "$NEEDS_PYTHON_DEPS" = true ]; then
        echo "  - Python packages: numpy, scipy (required for test audio generation)"
    fi
    
    echo ""
    read -p "Continue with installation? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    echo ""
    
    # Install Xcode Command Line Tools
    if [ "$NEEDS_XCODE" = true ]; then
        print_info "Installing Xcode Command Line Tools..."
        print_warning "This will open a dialog. Please follow the prompts."
        xcode-select --install || {
            print_error "Failed to install Xcode Command Line Tools"
            print_info "Please install manually from: https://developer.apple.com/xcode/"
            exit 1
        }
        print_warning "Please wait for Xcode Command Line Tools to finish installing, then run this script again."
        exit 0
    fi
    
    # Install Homebrew
    if [ "$NEEDS_BREW" = true ]; then
        print_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
            print_error "Failed to install Homebrew"
            exit 1
        }
        print_status "Homebrew installed"
        
        # Add Homebrew to PATH if needed
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f "/usr/local/bin/brew" ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    
    # Install XcodeGen (optional)
    if [ "$NEEDS_XCODEGEN" = true ]; then
        if command -v brew &> /dev/null; then
            print_info "Installing XcodeGen..."
            brew install xcodegen || {
                print_warning "Failed to install XcodeGen. You can install it manually later with: brew install xcodegen"
            }
            if command -v xcodegen &> /dev/null; then
                print_status "XcodeGen installed"
            fi
        else
            print_warning "Skipping XcodeGen installation (Homebrew required)"
        fi
    fi
    
    # Install Python 3 (usually comes with macOS, but check)
    if [ "$NEEDS_PYTHON" = true ]; then
        if command -v brew &> /dev/null; then
            print_info "Installing Python 3..."
            brew install python3 || {
                print_error "Failed to install Python 3"
                exit 1
            }
            print_status "Python 3 installed"
        else
            print_error "Python 3 not found and Homebrew is required to install it"
            exit 1
        fi
    fi
    
    # Install Python dependencies
    if [ "$NEEDS_PYTHON_DEPS" = true ]; then
        print_info "Installing Python dependencies (numpy, scipy)..."
        if [ -f "test_audio_requirements.txt" ]; then
            python3 -m pip install --user -r test_audio_requirements.txt || {
                print_error "Failed to install Python dependencies"
                exit 1
            }
        else
            python3 -m pip install --user numpy scipy || {
                print_error "Failed to install Python dependencies"
                exit 1
            }
        fi
        print_status "Python dependencies installed"
    fi
    
    echo ""
    print_status "All dependencies installed successfully!"
else
    print_status "All dependencies are already installed!"
fi

echo ""
echo "=========================================="
echo "Project Setup"
echo "=========================================="

# Resolve Swift Package dependencies
print_info "Resolving Swift Package dependencies..."
if swift package resolve &> /dev/null; then
    print_status "Swift Package dependencies resolved"
else
    print_warning "Failed to resolve Swift Package dependencies. This is okay if you're using Xcode."
fi

# Generate Xcode project if XcodeGen is available
if command -v xcodegen &> /dev/null && [ -f "project.yml" ]; then
    print_info "Generating Xcode project with XcodeGen..."
    if xcodegen generate; then
        print_status "Xcode project generated successfully"
    else
        print_warning "Failed to generate Xcode project with XcodeGen"
    fi
else
    if [ ! -f "project.yml" ]; then
        print_info "project.yml not found, skipping XcodeGen"
    fi
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
print_status "You can now:"
echo ""
echo "  1. Open the project in Xcode:"
echo "     open AudioVisualizerApp.xcodeproj"
echo "     (or open Package.swift if the .xcodeproj doesn't exist)"
echo ""
echo "  2. Build and run the app:"
echo "     - Select a physical iOS device (simulator doesn't support microphone)"
echo "     - Press Cmd+R to build and run"
echo ""
echo "  3. Generate test audio files (optional):"
echo "     python3 generate_test_audio.py"
echo ""
echo "For more information, see README.md"
echo ""

