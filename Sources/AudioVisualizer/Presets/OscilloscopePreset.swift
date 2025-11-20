import SwiftUI
import Charts

/// Oscilloscope visualizer preset (time-domain waveform)
public struct OscilloscopePreset: VisualizerPreset {
    public let id = "oscilloscope"
    public let displayName = "Oscilloscope"
    
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
            // Scrolling mode: display as horizontal scrolling waveform
            // Each frame contains a single sample, displayed as a vertical line
            // New samples are introduced on the right, pushing old ones left
            GeometryReader { geometry in
                let chartWidth = geometry.size.width - (horizontalPadding * 2)
                let frameWidth = max(1.0, chartWidth / CGFloat(scrollingFrames.count))
                
                // Calculate max amplitude across all frames
                let maxAmplitude = scrollingFrames.flatMap { $0 }.reduce(0.0) { max(abs($0), abs($1)) }
                let normalizedMaxAmplitude = max(maxAmplitude, 0.01)
                
                HStack(spacing: 0) {
                    ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
                        let frame = scrollingFrames[frameIndex]
                        // Each frame should contain a single sample for oscilloscope scrolling
                        let sample = frame.first ?? 0.0
                        
                        // Draw vertical line at sample amplitude (0 in the middle)
                        GeometryReader { frameGeometry in
                            Path { path in
                                let width = frameGeometry.size.width
                                let height = frameGeometry.size.height
                                let centerX = width / 2
                                let centerY = height / 2
                                
                                // Normalize sample to [-1, 1] range based on max amplitude
                                let normalizedSample = CGFloat(sample / normalizedMaxAmplitude)
                                
                                // Calculate y position: 0 is at center, positive goes up, negative goes down
                                // In SwiftUI, y=0 is at top, so we invert
                                let yPosition = centerY - (normalizedSample * height / 2)
                                
                                // Draw vertical line from center (0) to sample position
                                path.move(to: CGPoint(x: centerX, y: centerY))
                                path.addLine(to: CGPoint(x: centerX, y: yPosition))
                            }
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.cyan, .blue, .purple]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: isRegularWidth ? 1.5 : 1
                            )
                        }
                        .frame(width: frameWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding)
            }
            .frame(height: chartHeight)
        } else if renderingMode == .continuous, let continuousSamples = continuousWaveformData, !continuousSamples.isEmpty {
            // Continuous mode: smooth, phase-continuous waveform display
            // Use the continuous waveform buffer which maintains a rolling window
            let targetPointCount = max(Int(availableWidth), continuousSamples.count)
            let downsampledSamples = downsampleMagnitudes(continuousSamples, to: targetPointCount)
            let maxAmplitude = max(abs(continuousSamples.max() ?? 0), abs(continuousSamples.min() ?? 0), 0.01)
            
            Chart(downsampledSamples.indices, id: \.self) { index in
                LineMark(
                    x: .value("Time", index),
                    y: .value("Amplitude", Double(downsampledSamples[index]))
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(
                    lineWidth: isRegularWidth ? 2 : 1.5
                ))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.cyan, .blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .chartYScale(domain: -maxAmplitude...maxAmplitude)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: chartHeight)
            .padding(.horizontal, horizontalPadding)
            .animation(.easeOut(duration: 0.1), value: downsampledSamples)
        } else {
            // Chunk mode: original oscilloscope display
            let samples = rawAudioSamples.isEmpty ? magnitudes : rawAudioSamples
            let targetPointCount = max(Int(availableWidth), samples.count)
            let downsampledSamples = downsampleMagnitudes(samples, to: targetPointCount)
            let maxAmplitude = max(abs(samples.max() ?? 0), abs(samples.min() ?? 0), 0.01)
            
            Chart(downsampledSamples.indices, id: \.self) { index in
                LineMark(
                    x: .value("Time", index),
                    y: .value("Amplitude", Double(downsampledSamples[index]))
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(
                    lineWidth: isRegularWidth ? 2 : 1.5
                ))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.cyan, .blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .chartYScale(domain: -maxAmplitude...maxAmplitude)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: chartHeight)
            .padding(.horizontal, horizontalPadding)
            .animation(.easeOut, value: downsampledSamples)
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

