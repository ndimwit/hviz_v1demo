import SwiftUI

/// Protocol defining a visualizer preset
public protocol VisualizerPreset {
    /// Unique identifier for the preset
    var id: String { get }
    
    /// Display name for the preset
    var displayName: String { get }
    
    /// Creates the view for this preset
    @ViewBuilder
    func makeView(
        magnitudes: [Float],
        rawAudioSamples: [Float],
        maxMagnitude: Float,
        renderingMode: RenderingMode,
        scrollingData: [[Float]]?,
        continuousWaveformData: [Float]?,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat,
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> any View
}

/// Available visualizer presets
public enum VisualizerPresetType: String, CaseIterable, Identifiable {
    case lineChart = "line_chart"
    case histogramBands = "histogram_bands"
    case oscilloscope = "oscilloscope"
    case stereoField = "stereo_field"
    case quadrant = "quadrant"
    case hlslVisualizer = "hlsl_visualizer"
    case mslVisualizer = "msl_visualizer"
    case cameraVisualizer = "camera_visualizer"
    case hlslTest = "hlsl_test"
    case mslTest = "msl_test"
    case mslDisplace = "msl_displace"
    case mslWaveform = "msl_waveform"
    
    public var id: String { rawValue }
    
    /// Default presets (non-shader based)
    public static var defaultPresets: [VisualizerPresetType] {
        [.lineChart, .histogramBands, .oscilloscope, .stereoField, .quadrant, .cameraVisualizer]
    }
    
    /// HLSL shader presets
    public static var hlslPresets: [VisualizerPresetType] {
        [.hlslVisualizer, .hlslTest]
    }
    
    /// MSL shader presets
    public static var mslPresets: [VisualizerPresetType] {
        [.mslVisualizer, .mslTest, .mslDisplace, .mslWaveform]
    }
    
    public var displayName: String {
        switch self {
        case .lineChart:
            return "Line Chart"
        case .histogramBands:
            return "Histogram Bands"
        case .oscilloscope:
            return "Oscilloscope"
        case .stereoField:
            return "Stereo Field"
        case .quadrant:
            return "Quadrant View"
        case .hlslVisualizer:
            return "HLSL Blur Echo"
        case .mslVisualizer:
            return "MSL Blur Echo"
        case .cameraVisualizer:
            return "Camera + Line Chart"
        case .hlslTest:
            return "HLSL Test (Simple)"
        case .mslTest:
            return "MSL Test (Simple)"
        case .mslDisplace:
            return "MSL Displace"
        case .mslWaveform:
            return "MSL Waveform"
        }
    }
    
    public var preset: VisualizerPreset {
        switch self {
        case .lineChart:
            return LineChartPreset()
        case .histogramBands:
            return HistogramBandsPreset()
        case .oscilloscope:
            return OscilloscopePreset()
        case .stereoField:
            return StereoFieldPreset()
        case .quadrant:
            return QuadrantPreset()
        case .hlslVisualizer:
            return HLSLVisualizerPreset()
        case .mslVisualizer:
            return MSLVisualizerPreset()
        case .cameraVisualizer:
            return CameraVisualizerPreset()
        case .hlslTest:
            return HLSLTestPreset()
        case .mslTest:
            return MSLTestPreset()
        case .mslDisplace:
            return MSLDisplacePreset()
        case .mslWaveform:
            return MSLWaveformPreset()
        }
    }
}
