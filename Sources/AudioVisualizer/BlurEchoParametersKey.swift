import SwiftUI

/// Environment key for blur intensity (0.0 to 1.0)
struct BlurIntensityKey: EnvironmentKey {
    static let defaultValue: Float = 0.5
}

/// Environment key for echo intensity (0.0 to 1.0)
struct EchoIntensityKey: EnvironmentKey {
    static let defaultValue: Float = 0.5
}

/// Environment key for color transform intensity (0.0 to 1.0)
struct ColorTransformIntensityKey: EnvironmentKey {
    static let defaultValue: Float = 0.3
}

extension EnvironmentValues {
    var blurIntensity: Float {
        get { self[BlurIntensityKey.self] }
        set { self[BlurIntensityKey.self] = newValue }
    }
    
    var echoIntensity: Float {
        get { self[EchoIntensityKey.self] }
        set { self[EchoIntensityKey.self] = newValue }
    }
    
    var colorTransformIntensity: Float {
        get { self[ColorTransformIntensityKey.self] }
        set { self[ColorTransformIntensityKey.self] = newValue }
    }
}

