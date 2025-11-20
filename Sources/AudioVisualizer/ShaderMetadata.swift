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

