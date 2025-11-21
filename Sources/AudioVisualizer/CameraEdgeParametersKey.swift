import SwiftUI

/// Environment key for camera edge displacement scale
struct CameraEdgeDisplacementScaleKey: EnvironmentKey {
    static let defaultValue: Float = 0.2
}

/// Environment key for camera edge detection threshold
struct CameraEdgeThresholdKey: EnvironmentKey {
    static let defaultValue: Float = 0.1
}

/// Environment key for camera edge detection sensitivity
struct CameraEdgeSensitivityKey: EnvironmentKey {
    static let defaultValue: Float = 1.0
}

/// Environment key for camera edge color intensity (Version 2 only)
struct CameraEdgeColorIntensityKey: EnvironmentKey {
    static let defaultValue: Float = 1.0
}

extension EnvironmentValues {
    var cameraEdgeDisplacementScale: Float {
        get { self[CameraEdgeDisplacementScaleKey.self] }
        set { self[CameraEdgeDisplacementScaleKey.self] = newValue }
    }
    
    var cameraEdgeThreshold: Float {
        get { self[CameraEdgeThresholdKey.self] }
        set { self[CameraEdgeThresholdKey.self] = newValue }
    }
    
    var cameraEdgeSensitivity: Float {
        get { self[CameraEdgeSensitivityKey.self] }
        set { self[CameraEdgeSensitivityKey.self] = newValue }
    }
    
    var cameraEdgeColorIntensity: Float {
        get { self[CameraEdgeColorIntensityKey.self] }
        set { self[CameraEdgeColorIntensityKey.self] = newValue }
    }
}

