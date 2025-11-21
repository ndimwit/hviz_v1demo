import SwiftUI

/// Environment key for MSL Template shader code
public struct MSLTemplateShaderCodeKey: EnvironmentKey {
    public static let defaultValue: String = ""
}

/// Environment key for MSL Template reload trigger
public struct MSLTemplateReloadTriggerKey: EnvironmentKey {
    public static let defaultValue: Int = 0
}

extension EnvironmentValues {
    /// Current shader code for MSL Template preset
    public var mslTemplateShaderCode: String {
        get { self[MSLTemplateShaderCodeKey.self] }
        set { self[MSLTemplateShaderCodeKey.self] = newValue }
    }
    
    /// Reload trigger for MSL Template preset (increment to trigger reload)
    public var mslTemplateReloadTrigger: Int {
        get { self[MSLTemplateReloadTriggerKey.self] }
        set { self[MSLTemplateReloadTriggerKey.self] = newValue }
    }
}

