import SwiftUI

/// Histogram bands visualizer preset (vertical bars)
public struct HistogramBandsPreset: VisualizerPreset {
    public let id = "histogram_bands"
    public let displayName = "Histogram Bands"
    
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
            let chartWidth = geometry.size.width - (horizontalPadding * 2)
            
            if renderingMode == .scrolling, let scrollingFrames = scrollingData, !scrollingFrames.isEmpty {
                // Scrolling mode: display as horizontal scrolling waterfall
                let frameWidth = chartWidth / CGFloat(max(scrollingFrames.count, 1))
                
                HStack(spacing: 0) {
                    ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
                        let frame = scrollingFrames[frameIndex]
                        let downsampledFrame = downsampleMagnitudes(frame, to: Int(chartHeight))
                        
                        // Draw vertical bars for each frame
                        VStack(spacing: 0) {
                            ForEach(downsampledFrame.indices, id: \.self) { bandIndex in
                                let magnitude = downsampledFrame[bandIndex]
                                let normalizedHeight = CGFloat(magnitude / maxMagnitude)
                                let barHeight = chartHeight / CGFloat(downsampledFrame.count)
                                
                                // Color based on frequency band
                                let colorIndex = Double(bandIndex) / Double(max(downsampledFrame.count - 1, 1))
                                let color = Color(
                                    red: min(1.0, colorIndex * 2.0),
                                    green: 0.0,
                                    blue: max(0.0, 1.0 - colorIndex * 2.0)
                                )
                                
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [color.opacity(0.8), color]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: frameWidth, height: barHeight)
                                    .opacity(normalizedHeight)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, horizontalPadding)
            } else {
                // Chunk mode: original histogram bands
                let minBarWidth: CGFloat = isRegularWidth ? 2 : 1
                let barSpacing: CGFloat = isRegularWidth ? 2 : 1
                let maxBars = max(1, Int((chartWidth + barSpacing) / (minBarWidth + barSpacing)))
                
                let targetBarCount = min(maxBars, magnitudes.count)
                let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetBarCount)
                
                let totalSpacing = CGFloat(max(downsampledMagnitudes.count - 1, 0)) * barSpacing
                let barWidth = max(minBarWidth, (chartWidth - totalSpacing) / CGFloat(max(downsampledMagnitudes.count, 1)))
                
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(downsampledMagnitudes.indices, id: \.self) { index in
                        let magnitude = downsampledMagnitudes[index]
                        let normalizedHeight = CGFloat(magnitude / maxMagnitude)
                        let barHeight = max(normalizedHeight * chartHeight, 2)
                        
                        let colorIndex = Double(index) / Double(max(downsampledMagnitudes.count - 1, 1))
                        let color = Color(
                            red: min(1.0, colorIndex * 2.0),
                            green: 0.0,
                            blue: max(0.0, 1.0 - colorIndex * 2.0)
                        )
                        
                        RoundedRectangle(cornerRadius: isRegularWidth ? 4 : 2)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [color.opacity(0.8), color]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: barWidth)
                            .frame(height: barHeight)
                            .animation(.easeOut(duration: 0.1), value: magnitude)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, horizontalPadding)
            }
        }
        .frame(height: chartHeight)
    }
    
    /// Downsample magnitudes to fit the target number of points
    private func downsampleMagnitudes(_ magnitudes: [Float], to targetCount: Int) -> [Float] {
        guard !magnitudes.isEmpty && targetCount > 0 else {
            return magnitudes
        }
        
        if magnitudes.count <= targetCount {
            return magnitudes
        }
        
        // Use linear interpolation to downsample
        var result = [Float]()
        let step = Double(magnitudes.count - 1) / Double(targetCount - 1)
        
        for i in 0..<targetCount {
            let position = Double(i) * step
            let lowerIndex = Int(position)
            let upperIndex = min(lowerIndex + 1, magnitudes.count - 1)
            let fraction = position - Double(lowerIndex)
            
            let interpolated = Float(Double(magnitudes[lowerIndex]) * (1.0 - fraction) + Double(magnitudes[upperIndex]) * fraction)
            result.append(interpolated)
        }
        
        return result
    }
}

