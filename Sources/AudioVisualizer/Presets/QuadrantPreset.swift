import SwiftUI

/// Quadrant view preset (displays all 4 presets in 4 quadrants)
public struct QuadrantPreset: VisualizerPreset {
    public let id = "quadrant"
    public let displayName = "Quadrant View"
    
    private let lineChartPreset = LineChartPreset()
    private let histogramBandsPreset = HistogramBandsPreset()
    private let oscilloscopePreset = OscilloscopePreset()
    private let stereoFieldPreset = StereoFieldPreset()
    
    @ViewBuilder
    public func makeView(
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
    ) -> any View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let totalHeight = chartHeight
            let quadrantWidth = (totalWidth - horizontalPadding * 2) / 2.0
            let quadrantHeight = totalHeight / 2.0
            let quadrantPadding: CGFloat = isRegularWidth ? 8 : 4
            
            VStack(spacing: 0) {
                // Top row: Line Chart (left) and Histogram Bands (right)
                HStack(spacing: 0) {
                    // Top-left: Line Chart
                    VStack(spacing: 2) {
                        Text("Line Chart")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, quadrantPadding)
                        
                        AnyView(
                            lineChartPreset.makeView(
                                magnitudes: magnitudes,
                                rawAudioSamples: rawAudioSamples,
                                maxMagnitude: maxMagnitude,
                                renderingMode: renderingMode,
                                scrollingData: scrollingData,
                                continuousWaveformData: continuousWaveformData,
                                isRegularWidth: isRegularWidth,
                                chartHeight: quadrantHeight - 20,
                                availableWidth: quadrantWidth - quadrantPadding * 2,
                                horizontalPadding: quadrantPadding,
                                leftChannelSamples: leftChannelSamples,
                                rightChannelSamples: rightChannelSamples
                            )
                        )
                    }
                    .frame(width: quadrantWidth, height: quadrantHeight)
                    .padding(quadrantPadding)
                    
                    // Top-right: Histogram Bands
                    VStack(spacing: 2) {
                        Text("Histogram Bands")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, quadrantPadding)
                        
                        AnyView(
                            histogramBandsPreset.makeView(
                                magnitudes: magnitudes,
                                rawAudioSamples: rawAudioSamples,
                                maxMagnitude: maxMagnitude,
                                renderingMode: renderingMode,
                                scrollingData: scrollingData,
                                continuousWaveformData: continuousWaveformData,
                                isRegularWidth: isRegularWidth,
                                chartHeight: quadrantHeight - 20,
                                availableWidth: quadrantWidth - quadrantPadding * 2,
                                horizontalPadding: quadrantPadding,
                                leftChannelSamples: leftChannelSamples,
                                rightChannelSamples: rightChannelSamples
                            )
                        )
                    }
                    .frame(width: quadrantWidth, height: quadrantHeight)
                    .padding(quadrantPadding)
                }
                
                // Bottom row: Oscilloscope (left) and Stereo Field (right)
                HStack(spacing: 0) {
                    // Bottom-left: Oscilloscope
                    VStack(spacing: 2) {
                        Text("Oscilloscope")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, quadrantPadding)
                        
                        AnyView(
                            oscilloscopePreset.makeView(
                                magnitudes: magnitudes,
                                rawAudioSamples: rawAudioSamples,
                                maxMagnitude: maxMagnitude,
                                renderingMode: renderingMode,
                                scrollingData: scrollingData,
                                continuousWaveformData: continuousWaveformData,
                                isRegularWidth: isRegularWidth,
                                chartHeight: quadrantHeight - 20,
                                availableWidth: quadrantWidth - quadrantPadding * 2,
                                horizontalPadding: quadrantPadding,
                                leftChannelSamples: leftChannelSamples,
                                rightChannelSamples: rightChannelSamples
                            )
                        )
                    }
                    .frame(width: quadrantWidth, height: quadrantHeight)
                    .padding(quadrantPadding)
                    
                    // Bottom-right: Stereo Field
                    VStack(spacing: 2) {
                        Text("Stereo Field")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, quadrantPadding)
                        
                        AnyView(
                            stereoFieldPreset.makeView(
                                magnitudes: magnitudes,
                                rawAudioSamples: rawAudioSamples,
                                maxMagnitude: maxMagnitude,
                                renderingMode: renderingMode,
                                scrollingData: scrollingData,
                                continuousWaveformData: continuousWaveformData,
                                isRegularWidth: isRegularWidth,
                                chartHeight: quadrantHeight - 20,
                                availableWidth: quadrantWidth - quadrantPadding * 2,
                                horizontalPadding: quadrantPadding,
                                leftChannelSamples: leftChannelSamples,
                                rightChannelSamples: rightChannelSamples
                            )
                        )
                    }
                    .frame(width: quadrantWidth, height: quadrantHeight)
                    .padding(quadrantPadding)
                }
            }
            .frame(width: totalWidth, height: totalHeight)
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: chartHeight)
    }
}

