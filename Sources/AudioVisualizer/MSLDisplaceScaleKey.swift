import SwiftUI

/// Environment key for MSL Displace scale
struct MSLDisplaceScaleKey: EnvironmentKey {
    static let defaultValue: Float = 0.15
}

extension EnvironmentValues {
    var mslDisplaceScale: Float {
        get { self[MSLDisplaceScaleKey.self] }
        set { self[MSLDisplaceScaleKey.self] = newValue }
    }
}

