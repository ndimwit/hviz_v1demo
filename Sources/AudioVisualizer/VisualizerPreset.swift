import SwiftUI
import Charts

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
    
    public var id: String { rawValue }
    
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
        }
    }
}

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
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat,
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> any View {
        if renderingMode == .scrolling, let scrollingFrames = scrollingData, !scrollingFrames.isEmpty {
            // Scrolling mode: display as horizontal scrolling waveform
            // Each column represents a time point, showing waveform amplitude vertically
            GeometryReader { geometry in
                let chartWidth = geometry.size.width - (horizontalPadding * 2)
                let frameWidth = max(1.0, chartWidth / CGFloat(scrollingFrames.count))
                let centerY = chartHeight / 2.0
                
                // Calculate max amplitude across all frames
                let maxAmplitude = scrollingFrames.flatMap { $0 }.reduce(0.0) { max(abs($0), abs($1)) }
                let normalizedMaxAmplitude = max(maxAmplitude, 0.01)
                
                HStack(spacing: 0) {
                    ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
                        let frame = scrollingFrames[frameIndex]
                        // Downsample to fit vertical resolution
                        let downsampledFrame = downsampleMagnitudes(frame, to: Int(chartHeight))
                        
                        // Draw vertical slice of waveform (centered)
                        GeometryReader { frameGeometry in
                            Path { path in
                                let width = frameGeometry.size.width
                                let height = frameGeometry.size.height
                                let centerX = width / 2
                                
                                if !downsampledFrame.isEmpty {
                                    let stepY = height / CGFloat(downsampledFrame.count - 1)
                                    
                                    for (index, sample) in downsampledFrame.enumerated() {
                                        let normalizedSample = CGFloat(sample / normalizedMaxAmplitude)
                                        let x = centerX + (normalizedSample * width / 2)
                                        let y = height - CGFloat(index) * stepY
                                        
                                        // Draw line from center to sample position
                                        path.move(to: CGPoint(x: centerX, y: y))
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.cyan, .blue, .purple]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: isRegularWidth ? 1 : 0.5
                            )
                        }
                        .frame(width: frameWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding)
            }
            .frame(height: chartHeight)
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

/// Stereo field analyzer preset (shows stereo imaging/panning)
public struct StereoFieldPreset: VisualizerPreset {
    public let id = "stereo_field"
    public let displayName = "Stereo Field"
    
    @ViewBuilder
    public func makeView(
        magnitudes: [Float],
        rawAudioSamples: [Float],
        maxMagnitude: Float,
        renderingMode: RenderingMode,
        scrollingData: [[Float]]?,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat,
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> any View {
        GeometryReader { geometry in
            let chartWidth = geometry.size.width - (horizontalPadding * 2)
            let centerX = chartWidth / 2.0
            let centerY = chartHeight / 2.0
            
            if renderingMode == .scrolling, let scrollingFrames = scrollingData, !scrollingFrames.isEmpty {
                // Scrolling mode: display as horizontal scrolling stereo field
                let frameWidth = chartWidth / CGFloat(max(scrollingFrames.count, 1))
                
                ZStack {
                    // Center line
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1)
                        .position(x: centerX + horizontalPadding, y: centerY)
                    
                    HStack(spacing: 0) {
                        ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
                            let frame = scrollingFrames[frameIndex]
                            let downsampledFrame = downsampleMagnitudes(frame, to: Int(chartHeight))
                            
                            // Draw vertical slice showing stereo field
                            VStack(spacing: 0) {
                                ForEach(downsampledFrame.indices, id: \.self) { bandIndex in
                                    let magnitude = downsampledFrame[bandIndex]
                                    let normalizedMagnitude = CGFloat(magnitude / maxMagnitude)
                                    
                                    // Simulate stereo width based on frequency
                                    let frequencyIndex = Double(bandIndex) / Double(max(downsampledFrame.count - 1, 1))
                                    let width = frameWidth * (0.3 + 0.7 * (1.0 - frequencyIndex))
                                    
                                    // Color based on frequency
                                    let color = Color(
                                        hue: Double(bandIndex) / Double(downsampledFrame.count) * 0.7,
                                        saturation: 0.8,
                                        brightness: 0.8
                                    )
                                    
                                    Rectangle()
                                        .fill(color.opacity(0.6))
                                        .frame(width: width * normalizedMagnitude, height: chartHeight / CGFloat(downsampledFrame.count))
                                }
                            }
                            .frame(width: frameWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    
                    // Labels
                    VStack {
                        HStack {
                            Text("L")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("C")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("R")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, horizontalPadding)
                        Spacer()
                    }
                }
            } else {
                // Chunk mode: stereo field display using actual left/right channels
                makeStereoFieldChunkView(
                    chartWidth: chartWidth,
                    centerX: centerX,
                    centerY: centerY,
                    chartHeight: chartHeight,
                    horizontalPadding: horizontalPadding,
                    maxMagnitude: maxMagnitude,
                    magnitudes: magnitudes,
                    leftChannelSamples: leftChannelSamples,
                    rightChannelSamples: rightChannelSamples
                )
            }
        }
        .frame(height: chartHeight)
    }
    
    /// Calculate stereo field data from left and right channels
    private func calculateStereoFieldData(
        leftSamples: [Float],
        rightSamples: [Float],
        chartWidth: CGFloat,
        maxMagnitude: Float
    ) -> [(pan: CGFloat, width: CGFloat, magnitude: CGFloat)] {
        let targetPointCount = max(Int(chartWidth), min(leftSamples.count, 512))
        let downsampledLeft = downsampleMagnitudes(leftSamples, to: targetPointCount)
        let downsampledRight = downsampleMagnitudes(rightSamples, to: targetPointCount)
        
        return zip(downsampledLeft, downsampledRight).map { left, right in
            let leftMag = abs(left)
            let rightMag = abs(right)
            let sum = leftMag + rightMag
            // Calculate pan: rightMag - leftMag so that:
            // - Positive pan (rightMag > leftMag) = panned RIGHT
            // - Negative pan (leftMag > rightMag) = panned LEFT
            let diff = rightMag - leftMag
            
            // Panning: -1.0 (fully left) to 1.0 (fully right), 0.0 = center
            let pan = sum > 0.001 ? CGFloat(diff / sum) : 0.0
            
            // Stereo width: 0.0 (mono) to 1.0 (wide stereo)
            let correlation = sum > 0.001 ? 1.0 - abs(diff / sum) : 0.0
            let width = CGFloat(correlation)
            
            // Overall magnitude for visualization
            let magnitude = CGFloat(max(leftMag, rightMag))
            
            return (pan: pan, width: width, magnitude: magnitude)
        }
    }
    
    /// Create stereo field chunk view
    @ViewBuilder
    private func makeStereoFieldChunkView(
        chartWidth: CGFloat,
        centerX: CGFloat,
        centerY: CGFloat,
        chartHeight: CGFloat,
        horizontalPadding: CGFloat,
        maxMagnitude: Float,
        magnitudes: [Float],
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> some View {
        // Calculate stereo field information from left and right channels
        let stereoData: [(pan: CGFloat, width: CGFloat, magnitude: CGFloat)]
        let effectiveMaxMagnitude: CGFloat
        
        if let leftSamples = leftChannelSamples, let rightSamples = rightChannelSamples,
           !leftSamples.isEmpty && !rightSamples.isEmpty && leftSamples.count == rightSamples.count {
            let data = calculateStereoFieldData(
                leftSamples: leftSamples,
                rightSamples: rightSamples,
                chartWidth: chartWidth,
                maxMagnitude: maxMagnitude
            )
            // Calculate max magnitude from the stereo data itself for proper normalization
            let maxMag = data.map { $0.magnitude }.max() ?? 1.0
            stereoData = data
            effectiveMaxMagnitude = max(maxMag, 0.001)
        } else {
            // Fallback: use magnitudes if stereo data not available
            // Create a simple visualization showing magnitude distribution
            let targetPointCount = max(Int(chartWidth / 4), min(magnitudes.count, 128))
            let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetPointCount)
            let maxMag = max(downsampledMagnitudes.max() ?? 1.0, maxMagnitude, 0.001)
            stereoData = downsampledMagnitudes.map { mag in
                let normalizedMag = CGFloat(mag / maxMag)
                // Center all bars when no stereo data available
                return (pan: 0.0, width: 0.5, magnitude: normalizedMag)
            }
            effectiveMaxMagnitude = CGFloat(maxMag)
        }
        
        return ZStack {
            // Center line
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
                .position(x: centerX + horizontalPadding, y: centerY)
            
            if !stereoData.isEmpty {
                ForEach(0..<stereoData.count, id: \.self) { index in
                    let data = stereoData[index]
                    // Normalize using the max magnitude from stereo data itself
                    let normalizedMagnitude = min(data.magnitude / effectiveMaxMagnitude, 1.0)
                    
                    // Calculate bar dimensions
                    // Each frequency band gets a horizontal row
                    let barRowHeight = chartHeight / CGFloat(stereoData.count)
                    let yPosition = centerY - chartHeight / 2 + CGFloat(index) * barRowHeight + barRowHeight / 2
                    let centerXPos = centerX + horizontalPadding
                    
                    // Maximum bar length (half the chart width, leaving some margin)
                    let maxBarLength = chartWidth / 2.0 * 0.95
                    
                    // Bar length should be primarily based on magnitude
                    // Pan amount determines how far from center, but we always show something if there's magnitude
                    let panAmount = abs(data.pan)
                    
                    // Base bar length on magnitude (this ensures bars are visible)
                    // Pan amount scales how far it extends, but we ensure minimum visibility
                    let baseLength = maxBarLength * normalizedMagnitude
                    
                    // Scale by pan amount, but ensure minimum length even for centered audio
                    // If pan is 0 (mono), show a small centered bar
                    // If pan is non-zero, extend proportionally
                    let barLength: CGFloat = {
                        if panAmount < 0.01 {
                            // Center/mono - show small centered bar
                            return max(baseLength * 0.3, 5.0)
                        } else {
                            // Panned - extend based on pan amount
                            return max(baseLength * (0.5 + panAmount * 0.5), baseLength * 0.2, 3.0)
                        }
                    }()
                    
                    let finalBarLength = barLength
                    
                    // Bar height (vertical thickness) - represents the frequency band row
                    // Use most of the row height, with small gaps between bands
                    let barHeight = barRowHeight * 0.85
                    
                    // Color based on panning: blue for left, red for right, purple for center
                    let hue = 0.7 + (data.pan * 0.3) // 0.7 (blue) to 1.0 (red)
                    let color = Color(hue: Double(hue), saturation: 0.8, brightness: 0.8)
                    
                    // Draw bar extending from center line if there's any magnitude
                    // Lower threshold to ensure more bars are visible
                    if normalizedMagnitude > 0.0001 || data.magnitude > 0.0001 {
                        if data.pan < -0.001 {
                            // Bar extends LEFT from center line
                            // Position: start at center, extend leftward
                            Rectangle()
                                .fill(color.opacity(0.8))
                                .frame(width: finalBarLength, height: barHeight)
                                .position(
                                    x: centerXPos - finalBarLength / 2.0, // Center of bar is left of center line
                                    y: yPosition
                                )
                        } else if data.pan > 0.001 {
                            // Bar extends RIGHT from center line
                            // Position: start at center, extend rightward
                            Rectangle()
                                .fill(color.opacity(0.8))
                                .frame(width: finalBarLength, height: barHeight)
                                .position(
                                    x: centerXPos + finalBarLength / 2.0, // Center of bar is right of center line
                                    y: yPosition
                                )
                        } else {
                            // Center (mono) - draw small centered bar
                            let centerBarWidth = max(finalBarLength * 0.5, 3.0)
                            Rectangle()
                                .fill(color.opacity(0.8))
                                .frame(width: centerBarWidth, height: barHeight)
                                .position(x: centerXPos, y: yPosition)
                        }
                    }
                }
            }
            
            // Labels
            VStack {
                HStack {
                    Text("L")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("C")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("R")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, horizontalPadding)
                Spacer()
            }
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
