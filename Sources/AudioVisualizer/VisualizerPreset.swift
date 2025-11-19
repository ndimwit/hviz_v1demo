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
        downsampledMagnitudes: [Float],
        maxMagnitude: Float,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
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
        downsampledMagnitudes: [Float],
        maxMagnitude: Float,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        horizontalPadding: CGFloat
    ) -> any View {
        Chart(downsampledMagnitudes.indices, id: \.self) { index in
            LineMark(
                x: .value("Frequency", index * Constants.downsampleFactor),
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

/// Histogram bands visualizer preset (vertical bars)
public struct HistogramBandsPreset: VisualizerPreset {
    public let id = "histogram_bands"
    public let displayName = "Histogram Bands"
    
    @ViewBuilder
    public func makeView(
        magnitudes: [Float],
        downsampledMagnitudes: [Float],
        maxMagnitude: Float,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        horizontalPadding: CGFloat
    ) -> any View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let totalSpacing = CGFloat(max(downsampledMagnitudes.count - 1, 0)) * (isRegularWidth ? 2 : 1)
            let barWidth = max(1.0, (availableWidth - totalSpacing) / CGFloat(max(downsampledMagnitudes.count, 1)))
            let barSpacing: CGFloat = isRegularWidth ? 2 : 1
            
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
}

