import Foundation

/// Configuration constants for audio waveform visualization
public enum Constants {
    /// Amount of frequency bins to keep after performing the FFT
    public static let sampleAmount: Int = 200
    
    /// Reduce the number of plotted points
    public static let downsampleFactor = 8
    
    /// Handle high spikes distortion in the chart
    public static let magnitudeLimit: Float = 100
    
    /// Available buffer sizes for FFT (must be powers of 2)
    public static let availableBufferSizes: [Int] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
    
    /// Default buffer size
    public static let defaultBufferSize: Int = 8192
    
    /// Available FFT band quantities (number of frequency bands to display)
    /// Matches availableBufferSizes to keep them in sync
    public static let availableFFTBandQuantities: [Int] = availableBufferSizes
    
    /// Default FFT band quantity
    public static let defaultFFTBandQuantity: Int = 8192
    
    /// Calculate required FFT buffer size from desired number of bands
    /// For a real FFT, we get N/2+1 bins from N samples
    /// To get at least 'bands' bins, we need at least 2*bands-2 samples
    /// We round up to the next power of 2 for efficiency
    public static func calculateFFTBufferSize(for bands: Int) -> Int {
        // For N bands, we need at least 2*N-2 samples
        // Round up to next power of 2
        let minSamples = max(2 * bands - 2, 1)
        var size = 1
        while size < minSamples {
            size *= 2
        }
        return size
    }
}

