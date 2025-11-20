import SwiftUI
import Charts

/// Line chart visualizer preset (original implementation)
public struct LineChartPreset: VisualizerPreset {
    public let id = "line_chart"
    public let displayName = "Line Chart"
    
    private let chartGradient = LinearGradient(
        gradient: Gradient(colors: [.blue, .purple, .red]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
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
        if renderingMode == .scrolling, let scrollingFrames = scrollingData, !scrollingFrames.isEmpty {
            // Scrolling mode: display as horizontal scrolling waterfall
            // Each column represents a time point, showing frequency spectrum vertically
            GeometryReader { geometry in
                let chartWidth = geometry.size.width - (horizontalPadding * 2)
                let frameWidth = max(1.0, chartWidth / CGFloat(scrollingFrames.count))
                
                HStack(spacing: 0) {
                    ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
                        let frame = scrollingFrames[frameIndex]
                        // Downsample to fit vertical resolution
                        let downsampledFrame = downsampleMagnitudes(frame, to: Int(chartHeight))
                        
                        // Draw vertical slice showing frequency spectrum
                        GeometryReader { frameGeometry in
                            Path { path in
                                let width = frameGeometry.size.width
                                let height = frameGeometry.size.height
                                
                                if !downsampledFrame.isEmpty {
                                    let stepY = height / CGFloat(downsampledFrame.count - 1)
                                    var isFirst = true
                                    
                                    for (index, magnitude) in downsampledFrame.enumerated() {
                                        let normalizedMagnitude = CGFloat(magnitude / maxMagnitude)
                                        // Draw from center outward
                                        let x = width / 2 + (normalizedMagnitude * width / 2)
                                        let y = height - CGFloat(index) * stepY // Flip so low freq at bottom
                                        
                                        if isFirst {
                                            path.move(to: CGPoint(x: width / 2, y: y))
                                            isFirst = false
                                        }
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(chartGradient, lineWidth: isRegularWidth ? 1.5 : 1)
                        }
                        .frame(width: frameWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding)
            }
            .frame(height: chartHeight)
        } else {
            // Chunk mode: original line chart
            let targetPointCount = max(Int(availableWidth), magnitudes.count)
            let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetPointCount)
            
            Chart(downsampledMagnitudes.indices, id: \.self) { index in
                LineMark(
                    x: .value("Frequency", index),
                    y: .value("Magnitude", downsampledMagnitudes[index])
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(
                    lineWidth: isRegularWidth ? 4 : 3
                ))
                .foregroundStyle(chartGradient)
            }
            .chartYScale(domain: 0...maxMagnitude)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: chartHeight)
            .padding(.horizontal, horizontalPadding)
            .animation(.easeOut, value: downsampledMagnitudes)
        }
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

