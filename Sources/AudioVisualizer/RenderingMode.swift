import Foundation

/// Rendering mode for audio visualization
public enum RenderingMode: String, CaseIterable, Identifiable {
    case chunk = "chunk"
    case scrolling = "scrolling"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .chunk:
            return "Chunk"
        case .scrolling:
            return "Scrolling (Full)"
        }
    }
}

