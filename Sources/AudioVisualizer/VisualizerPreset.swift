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
        horizontalPadding: CGFloat
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
        horizontalPadding: CGFloat
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
        horizontalPadding: CGFloat
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
        horizontalPadding: CGFloat
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
        horizontalPadding: CGFloat
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
                // Chunk mode: original stereo field display
                let samples = rawAudioSamples.isEmpty ? magnitudes : rawAudioSamples
                let targetPointCount = max(Int(chartWidth), magnitudes.count)
                let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetPointCount)
                
                ZStack {
                    // Center line
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1)
                        .position(x: centerX + horizontalPadding, y: centerY)
                    
                    if !downsampledMagnitudes.isEmpty {
                        ForEach(downsampledMagnitudes.indices, id: \.self) { index in
                            let magnitude = downsampledMagnitudes[index]
                            let normalizedMagnitude = CGFloat(magnitude / maxMagnitude)
                            
                            let frequencyIndex = Double(index) / Double(max(downsampledMagnitudes.count - 1, 1))
                            let width = chartWidth * (0.3 + 0.7 * (1.0 - frequencyIndex))
                            let xPosition = centerX + horizontalPadding
                            
                            let color = Color(
                                hue: Double(index) / Double(downsampledMagnitudes.count) * 0.7,
                                saturation: 0.8,
                                brightness: 0.8
                            )
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.6))
                                .frame(width: width * normalizedMagnitude, height: chartHeight / CGFloat(downsampledMagnitudes.count))
                                .position(
                                    x: xPosition,
                                    y: centerY - chartHeight / 2 + CGFloat(index) * (chartHeight / CGFloat(downsampledMagnitudes.count)) + chartHeight / CGFloat(downsampledMagnitudes.count) / 2
                                )
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
