import Foundation

/// Configuration constants for audio waveform visualization
public enum Constants {
    /// Amount of frequency bins to keep after performing the FFT
    public static let sampleAmount: Int = 200
    
    /// Reduce the number of plotted points
    public static let downsampleFactor = 8
    
    /// Handle high spikes distortion in the chart
    public static let magnitudeLimit: Float = 100
}

