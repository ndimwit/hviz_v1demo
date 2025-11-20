# Screen Test App

A minimal test app to experiment with different techniques for achieving full-screen display that extends past safe areas on iOS.

## Purpose

This app tests various approaches to make a view extend to the top and bottom of the screen, ignoring safe areas (status bar, notch, home indicator).

## Test Methods

The app includes 5 different test methods that can be selected via a picker:

1. **ignoresSafeArea** - Uses `.ignoresSafeArea(.all, edges: .all)` modifier
2. **fullScreenCover** - Presents view as a full screen cover modal
3. **contentMargins** - Uses `.contentMargins()` with negative values (iOS 17+)
4. **UIViewController** - Uses UIViewController with `additionalSafeAreaInsets = .zero`
5. **GeometryReader** - Uses GeometryReader with explicit frame calculations

## Building

### Option 1: Create Xcode Project Manually

1. Open Xcode
2. File > New > Project
3. Choose iOS > App
4. Product Name: `ScreenTestApp`
5. Interface: SwiftUI
6. Language: Swift
7. Add the `ScreenTestApp.swift` file to the project
8. Update Info.plist with the provided content

### Option 2: Use XcodeGen (if available)

Create a `project.yml` file and run `xcodegen generate`.

## Testing

1. Build and run on a physical iPhone device
2. Use the segmented control to switch between test methods
3. Observe which method successfully extends to the top and bottom
4. Check for any black bands or gaps

## Expected Results

- **ignoresSafeArea**: Should work but may still show safe area padding
- **fullScreenCover**: Should work but creates a modal presentation
- **contentMargins**: May work on iOS 17+ but behavior may vary
- **UIViewController**: Should work by removing safe area insets
- **GeometryReader**: Should work with explicit frame calculations

## Notes

- Test on a physical device with a notch (iPhone X or later) for best results
- Different iOS versions may behave differently
- Some methods may work better than others depending on the use case

