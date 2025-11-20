# Implementation Guide: Path 1 - Runtime Text File Loading with True Hotswapping

This document provides a complete implementation plan for enabling hotswappable MSL shader presets using runtime text file loading. All code changes, file structures, and migration steps are detailed below.

---

## Overview

**Goal:** Enable shaders to be loaded from `.metal` text files at runtime, allowing hotswapping without rebuilding the application.

**Key Features:**
- Load shaders from text files in app bundle or Documents directory
- Automatic file change detection and recompilation
- Caching to avoid unnecessary recompilation
- Graceful fallback to embedded shaders
- Support for macOS, iPad, and iPhone

---

## File Structure Changes

### New Directory Structure

```
Sources/AudioVisualizer/
├── Shaders/
│   ├── Source/                    # NEW: Runtime-loadable shader source files
│   │   ├── MSLVisualizer.metal
│   │   ├── MSLDisplace.metal
│   │   ├── MSLWaveform.metal
│   │   └── ...
│   └── HLSL/                      # Existing: Build-time HLSL conversion
│       └── HLSLVisualizerShader.hlsl
├── ShaderManager.swift            # NEW: Core shader loading and management
├── ShaderMetadata.swift           # NEW: Shader metadata and configuration
└── Presets/
    └── [Existing preset files - will be modified]
```

### Resource Bundle Structure

For runtime file loading, shaders should be included as resources:

```
App Bundle/
├── Shaders/
│   ├── MSLVisualizer.metal
│   ├── MSLDisplace.metal
│   ├── MSLWaveform.metal
│   └── ...
```

---

## Implementation Steps

### Step 1: Create ShaderManager Class

**File:** `Sources/AudioVisualizer/ShaderManager.swift`

```swift
import Foundation
import Metal
import MetalKit

/// Manages loading and caching of Metal shaders from text files
public class ShaderManager {
    public static let shared = ShaderManager()
    
    // MARK: - Properties
    
    private var libraryCache: [String: MTLLibrary] = [:]
    private var fileModificationDates: [String: Date] = [:]
    private var compilationErrors: [String: Error] = [:]
    private let fileManager = FileManager.default
    private let cacheQueue = DispatchQueue(label: "com.audiovisualizer.shadercache", attributes: .concurrent)
    
    // MARK: - Configuration
    
    /// Search paths for shader files (in order of priority)
    public var searchPaths: [URL] {
        var paths: [URL] = []
        
        // 1. Documents directory (for user-created shaders)
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let shadersURL = documentsURL.appendingPathComponent("Shaders", isDirectory: true)
            paths.append(shadersURL)
        }
        
        // 2. App bundle resources
        if let bundleURL = Bundle.main.resourceURL {
            let shadersURL = bundleURL.appendingPathComponent("Shaders", isDirectory: true)
            paths.append(shadersURL)
        }
        
        // 3. Source directory (for development)
        #if DEBUG
        if let sourceURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioVisualizer/Shaders/Source", isDirectory: true) {
            paths.append(sourceURL)
        }
        #endif
        
        return paths
    }
    
    // MARK: - Initialization
    
    private init() {
        // Ensure Documents/Shaders directory exists
        setupDocumentsDirectory()
    }
    
    private func setupDocumentsDirectory() {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let shadersURL = documentsURL.appendingPathComponent("Shaders", isDirectory: true)
        
        if !fileManager.fileExists(atPath: shadersURL.path) {
            try? fileManager.createDirectory(at: shadersURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Shader Loading
    
    /// Load a shader library from a file
    /// - Parameters:
    ///   - name: Shader name (without extension)
    ///   - device: Metal device to compile for
    ///   - forceReload: If true, bypass cache and reload from file
    /// - Returns: Compiled MTLLibrary or nil if loading fails
    public func loadShader(
        name: String,
        device: MTLDevice,
        forceReload: Bool = false
    ) -> MTLLibrary? {
        let cacheKey = "\(name)_\(device.name)"
        
        // Check cache first (unless force reload)
        if !forceReload {
            if let cached = getCachedLibrary(key: cacheKey) {
                return cached
            }
        }
        
        // Find shader file
        guard let fileURL = findShaderFile(name: name) else {
            print("ERROR: Shader file not found: \(name).metal")
            print("  Searched paths:")
            for path in searchPaths {
                print("    - \(path.path)")
            }
            return nil
        }
        
        // Check if file was modified
        guard let fileModDate = getFileModificationDate(url: fileURL) else {
            print("ERROR: Could not get modification date for: \(fileURL.path)")
            return getCachedLibrary(key: cacheKey) // Return stale cache
        }
        
        // If file hasn't changed and we have a cache, return cached version
        if !forceReload,
           let cachedModDate = fileModificationDates[cacheKey],
           fileModDate <= cachedModDate,
           let cached = libraryCache[cacheKey] {
            return cached
        }
        
        // Load and compile shader
        guard let shaderSource = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("ERROR: Could not read shader file: \(fileURL.path)")
            return getCachedLibrary(key: cacheKey) // Return stale cache on error
        }
        
        // Compile shader
        let library: MTLLibrary?
        do {
            let compileOptions = MTLCompileOptions()
            compileOptions.fastMathEnabled = true
            library = try device.makeLibrary(source: shaderSource, options: compileOptions)
            print("✓ Shader compiled successfully: \(name)")
            
            // Cache the library
            cacheLibrary(library!, key: cacheKey, modificationDate: fileModDate)
            
            // Clear any previous errors
            compilationErrors.removeValue(forKey: cacheKey)
            
        } catch {
            print("ERROR: Failed to compile shader '\(name)': \(error)")
            compilationErrors[cacheKey] = error
            
            // Return stale cache if available
            return getCachedLibrary(key: cacheKey)
        }
        
        return library
    }
    
    /// Load shader with fallback chain: file → default library → embedded source
    /// - Parameters:
    ///   - name: Shader name
    ///   - device: Metal device
    ///   - defaultLibrary: Default Metal library (from bundle)
    ///   - embeddedSource: Fallback embedded shader source
    /// - Returns: Compiled MTLLibrary or nil
    public func loadShaderWithFallback(
        name: String,
        device: MTLDevice,
        defaultLibrary: MTLLibrary? = nil,
        embeddedSource: String? = nil
    ) -> MTLLibrary? {
        // 1. Try loading from file
        if let fileLibrary = loadShader(name: name, device: device) {
            return fileLibrary
        }
        
        // 2. Try default library
        if let defaultLib = defaultLibrary ?? device.makeDefaultLibrary() {
            // Check if it has the required functions
            if hasRequiredFunctions(library: defaultLib, name: name) {
                print("✓ Using shader from default library: \(name)")
                return defaultLib
            }
        }
        
        // 3. Try embedded source
        if let embedded = embeddedSource {
            do {
                let library = try device.makeLibrary(source: embedded, options: nil)
                print("✓ Using embedded shader source: \(name)")
                return library
            } catch {
                print("ERROR: Failed to compile embedded shader '\(name)': \(error)")
            }
        }
        
        return nil
    }
    
    // MARK: - File Discovery
    
    /// Find shader file in search paths
    public func findShaderFile(name: String) -> URL? {
        let fileName = name.hasSuffix(".metal") ? name : "\(name).metal"
        
        for searchPath in searchPaths {
            let fileURL = searchPath.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        
        return nil
    }
    
    /// Get all available shader files
    public func availableShaders() -> [String] {
        var shaders: Set<String> = []
        
        for searchPath in searchPaths {
            guard let files = try? fileManager.contentsOfDirectory(at: searchPath, includingPropertiesForKeys: nil) else {
                continue
            }
            
            for file in files {
                if file.pathExtension == "metal" {
                    let name = file.deletingPathExtension().lastPathComponent
                    shaders.insert(name)
                }
            }
        }
        
        return Array(shaders).sorted()
    }
    
    // MARK: - Cache Management
    
    private func getCachedLibrary(key: String) -> MTLLibrary? {
        return cacheQueue.sync {
            return libraryCache[key]
        }
    }
    
    private func cacheLibrary(_ library: MTLLibrary, key: String, modificationDate: Date) {
        cacheQueue.async(flags: .barrier) {
            self.libraryCache[key] = library
            self.fileModificationDates[key] = modificationDate
        }
    }
    
    /// Clear shader cache
    public func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.libraryCache.removeAll()
            self.fileModificationDates.removeAll()
            self.compilationErrors.removeAll()
        }
    }
    
    /// Clear cache for specific shader
    public func clearCache(for name: String, device: MTLDevice) {
        let key = "\(name)_\(device.name)"
        cacheQueue.async(flags: .barrier) {
            self.libraryCache.removeValue(forKey: key)
            self.fileModificationDates.removeValue(forKey: key)
            self.compilationErrors.removeValue(forKey: key)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getFileModificationDate(url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return modDate
    }
    
    private func hasRequiredFunctions(library: MTLLibrary, name: String) -> Bool {
        // Common function names to check (can be customized per shader)
        let commonFunctions = [
            "\(name)Vertex",
            "\(name)Fragment",
            "\(name)Compute",
            "msl\(name)",
            name.lowercased()
        ]
        
        let availableFunctions = Set(library.functionNames)
        return commonFunctions.contains { availableFunctions.contains($0) }
    }
    
    // MARK: - Error Reporting
    
    /// Get compilation error for a shader
    public func getError(for name: String, device: MTLDevice) -> Error? {
        let key = "\(name)_\(device.name)"
        return cacheQueue.sync {
            return compilationErrors[key]
        }
    }
    
    /// Check if shader file exists
    public func shaderFileExists(name: String) -> Bool {
        return findShaderFile(name: name) != nil
    }
}

```

---

### Step 2: Create Shader Metadata System

**File:** `Sources/AudioVisualizer/ShaderMetadata.swift`

```swift
import Foundation

/// Metadata for a shader preset
public struct ShaderMetadata: Codable {
    public let name: String
    public let displayName: String
    public let description: String?
    public let author: String?
    public let version: String?
    public let requiredFunctions: [String]
    public let shaderFile: String
    
    public init(
        name: String,
        displayName: String,
        description: String? = nil,
        author: String? = nil,
        version: String? = nil,
        requiredFunctions: [String],
        shaderFile: String
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.author = author
        self.version = version
        self.requiredFunctions = requiredFunctions
        self.shaderFile = shaderFile
    }
}

/// Manages shader metadata
public class ShaderMetadataManager {
    public static let shared = ShaderMetadataManager()
    
    private var metadataCache: [String: ShaderMetadata] = [:]
    
    private init() {}
    
    /// Load metadata for a shader
    public func loadMetadata(for shaderName: String) -> ShaderMetadata? {
        if let cached = metadataCache[shaderName] {
            return cached
        }
        
        // Try to load from JSON file
        let metadataFileName = "\(shaderName).json"
        let fileManager = FileManager.default
        
        // Search in same locations as shader files
        var searchPaths: [URL] = []
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            searchPaths.append(documentsURL.appendingPathComponent("Shaders"))
        }
        if let bundleURL = Bundle.main.resourceURL {
            searchPaths.append(bundleURL.appendingPathComponent("Shaders"))
        }
        
        for path in searchPaths {
            let metadataURL = path.appendingPathComponent(metadataFileName)
            if let data = try? Data(contentsOf: metadataURL),
               let metadata = try? JSONDecoder().decode(ShaderMetadata.self, from: data) {
                metadataCache[shaderName] = metadata
                return metadata
            }
        }
        
        // Return default metadata
        let defaultMetadata = ShaderMetadata(
            name: shaderName,
            displayName: shaderName,
            requiredFunctions: [],
            shaderFile: "\(shaderName).metal"
        )
        metadataCache[shaderName] = defaultMetadata
        return defaultMetadata
    }
}
```

---

### Step 3: Extract Shader Source Files

**Action:** Move embedded shader source code from Swift files to separate `.metal` files.

#### 3.1: Create MSLVisualizer.metal

**File:** `Sources/AudioVisualizer/Shaders/Source/MSLVisualizer.metal`

```metal
#include <metal_stdlib>
using namespace metal;

/// Metal Shader Language (MSL) visualizer shader
/// Direct MSL implementation for histogram bands with enhanced effects

struct VertexIn {
    float2 position;
    float magnitude;
    float frequencyIndex;
};

struct VertexOut {
    float4 position [[position]];
    float magnitude;
    float frequencyIndex;
    float2 uv;
};

/// Vertex shader for histogram bars
vertex VertexOut mslHistogramVertex(
    device const VertexIn* vertices [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    VertexIn in = vertices[vid];
    
    // Convert to normalized device coordinates
    float2 pos = (in.position / viewportSize) * 2.0 - 1.0;
    pos.y = -pos.y; // Flip Y for Metal coordinate system
    
    out.position = float4(pos, 0.0, 1.0);
    out.magnitude = in.magnitude;
    out.frequencyIndex = in.frequencyIndex;
    out.uv = in.position / viewportSize;
    
    return out;
}

/// Fragment shader with enhanced visual effects
fragment float4 mslHistogramFragment(
    VertexOut in [[stage_in]],
    constant float& time [[buffer(0)]],
    constant float& maxMagnitude [[buffer(1)]]
) {
    // Normalize magnitude
    float normalizedMag = in.magnitude / max(maxMagnitude, 0.001);
    
    // Frequency-based color gradient
    float colorIndex = in.frequencyIndex;
    float3 baseColor = float3(
        min(1.0, colorIndex * 2.0),      // Red component
        sin(colorIndex * 3.14159) * 0.5, // Green component (sine wave)
        max(0.0, 1.0 - colorIndex * 2.0) // Blue component
    );
    
    // Add pulsing animation based on magnitude and time
    float pulse = sin(time * 3.0 + in.frequencyIndex * 10.0) * 0.15 + 0.85;
    float magnitudePulse = normalizedMag * 0.3 + 0.7;
    
    // Create gradient effect from bottom to top
    float gradient = in.uv.y;
    float3 color = baseColor * pulse * magnitudePulse;
    color += float3(0.1, 0.1, 0.2) * (1.0 - gradient); // Darker at bottom
    
    // Add glow effect for high magnitudes
    float glow = smoothstep(0.7, 1.0, normalizedMag);
    color += float3(0.3, 0.3, 0.5) * glow;
    
    return float4(color, 1.0);
}

/// Compute shader for processing audio magnitudes
kernel void mslProcessAudio(
    device const float* magnitudes [[buffer(0)]],
    device VertexIn* vertices [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    constant float2& viewportSize [[buffer(3)]],
    constant float& maxMagnitude [[buffer(4)]],
    constant float& barWidth [[buffer(5)]],
    constant float& barSpacing [[buffer(6)]],
    constant float& chartHeight [[buffer(7)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) return;
    
    float magnitude = magnitudes[id];
    float normalizedMag = magnitude / max(maxMagnitude, 0.001);
    
    // Calculate bar position
    float xPos = float(id) * (barWidth + barSpacing) + barWidth * 0.5;
    float barHeight = normalizedMag * chartHeight;
    
    // Create vertices for the bar (two triangles forming a rectangle)
    float frequencyIndex = float(id) / float(max(count - 1u, 1u));
    
    // Bottom-left
    vertices[id * 4 + 0] = VertexIn{
        float2(xPos - barWidth * 0.5, 0.0),
        normalizedMag,
        frequencyIndex
    };
    
    // Bottom-right
    vertices[id * 4 + 1] = VertexIn{
        float2(xPos + barWidth * 0.5, 0.0),
        normalizedMag,
        frequencyIndex
    };
    
    // Top-right
    vertices[id * 4 + 2] = VertexIn{
        float2(xPos + barWidth * 0.5, barHeight),
        normalizedMag,
        frequencyIndex
    };
    
    // Top-left
    vertices[id * 4 + 3] = VertexIn{
        float2(xPos - barWidth * 0.5, barHeight),
        normalizedMag,
        frequencyIndex
    };
}
```

#### 3.2: Copy Existing Metal Files

Copy the existing `.metal` files to the Source directory:
- `MSLDisplaceShader.metal` → `Shaders/Source/MSLDisplace.metal`
- `MSLWaveformShader.metal` → `Shaders/Source/MSLWaveform.metal`

---

### Step 4: Update Package.swift for Resources

**File:** `Package.swift`

Add shader files as resources:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioVisualizer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AudioVisualizer",
            targets: ["AudioVisualizer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "AudioVisualizer",
            dependencies: [
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                ),
            ],
            resources: [
                .process("Shaders/HLSLVisualizerShader.hlsl"),
                .process("Shaders/Source"),  // ADD THIS: Include all .metal files
            ]
        ),
        .testTarget(
            name: "AudioVisualizerTests",
            dependencies: ["AudioVisualizer"],
            path: "Tests/AudioVisualizerTests"
        ),
    ]
)
```

---

### Step 5: Update MSLVisualizerPreset

**File:** `Sources/AudioVisualizer/Presets/MSLVisualizerPreset.swift`

Replace the `setupMetal` method:

```swift
func setupMetal(device: MTLDevice, view: MTKView) {
    self.device = device
    
    guard let commandQueue = device.makeCommandQueue() else {
        print("ERROR: Failed to create Metal command queue")
        return
    }
    self.commandQueue = commandQueue
    
    // Load shader using ShaderManager with fallback
    let embeddedSource = """
    #include <metal_stdlib>
    using namespace metal;
    
    // ... [keep existing embedded source as fallback] ...
    """
    
    library = ShaderManager.shared.loadShaderWithFallback(
        name: "MSLVisualizer",
        device: device,
        defaultLibrary: device.makeDefaultLibrary(),
        embeddedSource: embeddedSource
    )
    
    guard let finalLibrary = library else {
        print("ERROR: Failed to create Metal library")
        print("  - Device: \(device.name)")
        print("  - Check that MSLVisualizer.metal exists in Shaders directory")
        return
    }
    
    print("✓ Metal library loaded successfully")
    
    // Create compute pipeline
    guard let computeFunction = finalLibrary.makeFunction(name: "mslProcessAudio") else {
        print("Warning: mslProcessAudio function not found, using fallback rendering")
        return
    }
    
    do {
        computePipelineState = try device.makeComputePipelineState(function: computeFunction)
    } catch {
        print("Failed to create compute pipeline: \(error)")
    }
    
    // Create render pipeline (keep existing simple shader code)
    // ... [rest of existing code] ...
}
```

**Add reload method:**

```swift
/// Reload shader from file (for hotswapping)
func reloadShader() {
    ShaderManager.shared.clearCache(for: "MSLVisualizer", device: device)
    
    let embeddedSource = """
    // ... [embedded source] ...
    """
    
    library = ShaderManager.shared.loadShaderWithFallback(
        name: "MSLVisualizer",
        device: device,
        defaultLibrary: device.makeDefaultLibrary(),
        embeddedSource: embeddedSource
    )
    
    // Recreate pipelines if library loaded successfully
    if let finalLibrary = library {
        // Recreate compute pipeline
        if let computeFunction = finalLibrary.makeFunction(name: "mslProcessAudio") {
            do {
                computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            } catch {
                print("Failed to recreate compute pipeline: \(error)")
            }
        }
        
        // Recreate render pipeline
        // ... [recreate render pipeline] ...
    }
}
```

---

### Step 6: Update MSLDisplacePreset

**File:** `Sources/AudioVisualizer/Presets/MSLDisplacePreset.swift`

Similar changes to Step 5:

```swift
func setupMetal(device: MTLDevice, view: MTKView) {
    // ... [existing setup code] ...
    
    // Replace library loading section:
    library = ShaderManager.shared.loadShaderWithFallback(
        name: "MSLDisplace",
        device: device,
        defaultLibrary: device.makeDefaultLibrary(),
        embeddedSource: embeddedSource  // Keep existing embedded source
    )
    
    // ... [rest of existing code] ...
}

func reloadShader() {
    ShaderManager.shared.clearCache(for: "MSLDisplace", device: device)
    // ... [reload logic similar to MSLVisualizerPreset] ...
}
```

---

### Step 7: Update MSLWaveformPreset

**File:** `Sources/AudioVisualizer/Presets/MSLWaveformPreset.swift`

Similar changes:

```swift
func setupMetal(device: MTLDevice, view: MTKView) {
    // ... [existing setup code] ...
    
    library = ShaderManager.shared.loadShaderWithFallback(
        name: "MSLWaveform",
        device: device,
        defaultLibrary: device.makeDefaultLibrary(),
        embeddedSource: embeddedSource
    )
    
    // ... [rest of existing code] ...
}
```

---

### Step 8: Add Hotswapping UI (Optional)

**File:** `Sources/AudioVisualizer/ShaderHotswapView.swift` (NEW)

```swift
import SwiftUI

/// UI for managing and hotswapping shaders
public struct ShaderHotswapView: View {
    @State private var availableShaders: [String] = []
    @State private var selectedShader: String = ""
    @State private var reloadMessage: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shader Hotswap")
                .font(.headline)
            
            Text("Available Shaders:")
                .font(.subheadline)
            
            List(availableShaders, id: \.self) { shader in
                HStack {
                    Text(shader)
                    Spacer()
                    if shader == selectedShader {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedShader = shader
                }
            }
            .frame(height: 200)
            
            HStack {
                Button("Reload Selected") {
                    reloadShader(selectedShader)
                }
                .disabled(selectedShader.isEmpty)
                
                Button("Reload All") {
                    reloadAllShaders()
                }
                
                Spacer()
                
                Button("Refresh List") {
                    refreshShaderList()
                }
            }
            
            if !reloadMessage.isEmpty {
                Text(reloadMessage)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .onAppear {
            refreshShaderList()
        }
    }
    
    private func refreshShaderList() {
        availableShaders = ShaderManager.shared.availableShaders()
    }
    
    private func reloadShader(_ name: String) {
        // This would need to be connected to the preset system
        // For now, just clear the cache
        if let device = MTLCreateSystemDefaultDevice() {
            ShaderManager.shared.clearCache(for: name, device: device)
            reloadMessage = "Cache cleared for \(name). Restart preset to reload."
        }
    }
    
    private func reloadAllShaders() {
        ShaderManager.shared.clearCache()
        reloadMessage = "All shader caches cleared."
    }
}
```

---

### Step 9: Add File Watching (macOS Only)

**File:** `Sources/AudioVisualizer/ShaderFileWatcher.swift` (NEW)

```swift
import Foundation

#if os(macOS)
import AppKit

/// Watches shader files for changes and triggers reload
@available(macOS 10.13, *)
public class ShaderFileWatcher {
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "com.audiovisualizer.shaderwatcher")
    public var onFileChanged: ((String) -> Void)?
    
    public static let shared = ShaderFileWatcher()
    
    private init() {}
    
    /// Start watching a shader file
    public func watchShader(name: String) {
        guard let fileURL = ShaderManager.shared.findShaderFile(name: name) else {
            return
        }
        
        let fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.onFileChanged?(name)
            }
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        fileWatchers[name] = source
    }
    
    /// Stop watching a shader file
    public func stopWatching(name: String) {
        fileWatchers[name]?.cancel()
        fileWatchers.removeValue(forKey: name)
    }
    
    /// Stop watching all files
    public func stopAll() {
        for (_, watcher) in fileWatchers {
            watcher.cancel()
        }
        fileWatchers.removeAll()
    }
}

#endif
```

---

### Step 10: Update Xcode Project Configuration

#### 10.1: Add Shader Files to Bundle Resources

1. Open Xcode project
2. Select the `AudioVisualizer` target
3. Go to "Build Phases" → "Copy Bundle Resources"
4. Add all `.metal` files from `Shaders/Source/` directory

#### 10.2: Create Shaders Directory in App Bundle

Add a Run Script build phase (before "Copy Bundle Resources"):

```bash
# Create Shaders directory in app bundle
SHADERS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Shaders"
mkdir -p "${SHADERS_DIR}"

# Copy shader files
if [ -d "${SRCROOT}/Sources/AudioVisualizer/Shaders/Source" ]; then
    cp -R "${SRCROOT}/Sources/AudioVisualizer/Shaders/Source/"*.metal "${SHADERS_DIR}/" 2>/dev/null || true
fi
```

---

## Migration Checklist

- [ ] Create `ShaderManager.swift`
- [ ] Create `ShaderMetadata.swift`
- [ ] Extract shader source to `Shaders/Source/` directory
  - [ ] `MSLVisualizer.metal`
  - [ ] `MSLDisplace.metal`
  - [ ] `MSLWaveform.metal`
- [ ] Update `Package.swift` to include shader resources
- [ ] Update `MSLVisualizerPreset.swift` to use ShaderManager
- [ ] Update `MSLDisplacePreset.swift` to use ShaderManager
- [ ] Update `MSLWaveformPreset.swift` to use ShaderManager
- [ ] Add shader files to Xcode bundle resources
- [ ] Test shader loading on macOS
- [ ] Test shader loading on iPad
- [ ] Test shader loading on iPhone
- [ ] Test hotswapping (modify .metal file, reload)
- [ ] Test fallback mechanisms
- [ ] Add error handling and logging
- [ ] (Optional) Add file watching for macOS
- [ ] (Optional) Add hotswap UI

---

## Testing Guide

### Test 1: Basic Loading
1. Build and run the app
2. Select an MSL preset (e.g., MSL Visualizer)
3. Verify shader loads from file
4. Check console for "✓ Shader compiled successfully" message

### Test 2: Hotswapping
1. While app is running, modify a shader file (e.g., `MSLVisualizer.metal`)
2. Change a color value or add a comment
3. Save the file
4. In the app, trigger a reload (or restart the preset)
5. Verify changes are reflected

### Test 3: Fallback Chain
1. Rename or delete a shader file
2. Run the app
3. Verify it falls back to embedded source
4. Check console for fallback messages

### Test 4: Cache Behavior
1. Load a shader (should compile)
2. Load the same shader again (should use cache)
3. Modify the shader file
4. Force reload (should recompile)

### Test 5: Error Handling
1. Create a shader file with syntax errors
2. Try to load it
3. Verify error is logged
4. Verify fallback is used

---

## Performance Considerations

### Compilation Time
- First load: 5-50ms depending on device
- Cached loads: <1ms
- Recompilation: Only when file changes

### Memory
- Each compiled library: ~100KB-1MB
- Cache size: Limited by number of shaders

### Battery Impact
- One-time compilation per shader: Minimal
- Repeated recompilation: May impact battery

---

## Platform-Specific Notes

### macOS
- Full file system access
- Can watch files for changes
- Best performance for runtime compilation

### iPad
- Sandboxed file system
- Can access Documents directory
- Good performance on M-series, acceptable on A-series

### iPhone
- Most restricted file system
- Documents directory accessible
- Prefer precompiled for production

---

## Troubleshooting

### Shader Not Found
- Check file is in `Shaders/Source/` directory
- Verify file is included in bundle resources
- Check search paths in console output

### Compilation Errors
- Check Metal shader syntax
- Verify function names match
- Check console for detailed error messages

### Cache Issues
- Clear cache: `ShaderManager.shared.clearCache()`
- Force reload: `loadShader(name:forceReload: true)`

### Performance Issues
- Use precompiled shaders for production
- Limit number of shaders loaded simultaneously
- Consider caching compiled libraries

---

## Future Enhancements

1. **Shader Editor UI:** Built-in editor for modifying shaders
2. **Shader Marketplace:** Download community shaders
3. **Shader Validation:** Pre-compile check before loading
4. **Performance Profiling:** Track compilation times
5. **Shader Templates:** Starter templates for common effects
6. **Version Control:** Track shader versions and changes

---

## Summary

This implementation enables:
- ✅ Runtime loading of shaders from text files
- ✅ True hotswapping without app rebuilds
- ✅ Automatic caching for performance
- ✅ Graceful fallback to embedded shaders
- ✅ Cross-platform support (macOS, iPad, iPhone)
- ✅ Error handling and logging
- ✅ File discovery and management

The system is designed to be flexible, performant, and developer-friendly while maintaining backward compatibility with existing embedded shaders.

