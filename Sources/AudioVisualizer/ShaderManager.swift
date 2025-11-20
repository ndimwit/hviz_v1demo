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
        let sourceURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioVisualizer/Shaders/Source", isDirectory: true)
        if fileManager.fileExists(atPath: sourceURL.path) {
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
            print("ERROR: Shader file not found: \(name).msl (or \(name).metal)")
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
        // Read shader source - support both .msl and .metal files
        guard let shaderSource = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("ERROR: Could not read shader file: \(fileURL.path)")
            return getCachedLibrary(key: cacheKey) // Return stale cache on error
        }
        
        // If file is .msl, it needs to be compiled at runtime
        // If file is .metal, it should already be in the default library (but we're loading from file for hotswapping)
        
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
        // Try .msl first (runtime-loadable), then .metal (compiled)
        let fileName = name.hasSuffix(".msl") || name.hasSuffix(".metal") ? name : "\(name).msl"
        
        for searchPath in searchPaths {
            // Try .msl first
            let fileURL = searchPath.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            // Fallback to .metal if .msl not found
            if !fileName.hasSuffix(".metal") {
                let metalURL = searchPath.appendingPathComponent("\(name).metal")
                if fileManager.fileExists(atPath: metalURL.path) {
                    return metalURL
                }
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
                if file.pathExtension == "msl" || file.pathExtension == "metal" {
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

