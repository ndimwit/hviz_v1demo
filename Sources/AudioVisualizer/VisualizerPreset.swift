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
        maxMagnitude: Float,
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
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .lineChart:
            return "Line Chart"
        case .histogramBands:
            return "Histogram Bands"
        }
    }
    
    public var preset: VisualizerPreset {
        switch self {
        case .lineChart:
            return LineChartPreset()
        case .histogramBands:
            return HistogramBandsPreset()
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
        maxMagnitude: Float,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> any View {
        // Calculate how many points we need to fill the available width
        // Use 1 point per pixel for smooth rendering
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
        maxMagnitude: Float,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> any View {
        GeometryReader { geometry in
            let chartWidth = geometry.size.width - (horizontalPadding * 2)
            // Calculate how many bars we can fit based on minimum bar width
            let minBarWidth: CGFloat = isRegularWidth ? 2 : 1
            let barSpacing: CGFloat = isRegularWidth ? 2 : 1
            let maxBars = max(1, Int((chartWidth + barSpacing) / (minBarWidth + barSpacing)))
            
            // Downsample magnitudes to fit the available width
            let targetBarCount = min(maxBars, magnitudes.count)
            let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetBarCount)
            
            let totalSpacing = CGFloat(max(downsampledMagnitudes.count - 1, 0)) * barSpacing
            let barWidth = max(minBarWidth, (chartWidth - totalSpacing) / CGFloat(max(downsampledMagnitudes.count, 1)))
            
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(downsampledMagnitudes.indices, id: \.self) { index in
                    let magnitude = downsampledMagnitudes[index]
                    let normalizedHeight = CGFloat(magnitude / maxMagnitude)
                    let barHeight = max(normalizedHeight * chartHeight, 2) // Minimum 2pt height
                    
                    // Color based on frequency band (low to high: blue -> purple -> red)
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

