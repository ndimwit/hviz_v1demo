import SwiftUI

/// Environment key for MSL shader opacity
struct MSLShaderOpacityKey: EnvironmentKey {
    static let defaultValue: Float = 1.0
}

extension EnvironmentValues {
    var mslShaderOpacity: Float {
        get { self[MSLShaderOpacityKey.self] }
        set { self[MSLShaderOpacityKey.self] = newValue }
    }
}

