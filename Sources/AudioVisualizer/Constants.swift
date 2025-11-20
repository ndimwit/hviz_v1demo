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
    public static let defaultBufferSize: Int = 512
    
    /// Available FFT window sizes (must be powers of 2, starting from 8)
    public static let availableFFTWindowSizes: [Int] = [8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
    
    /// Default FFT window size
    public static let defaultFFTWindowSize: Int = 512
    
    /// Available FFT band quantities (number of frequency bands to display)
    /// Matches availableBufferSizes to keep them in sync
    public static let availableFFTBandQuantities: [Int] = availableBufferSizes
    
    /// Default FFT band quantity
    public static let defaultFFTBandQuantity: Int = 512
    
    /// Available scrolling update rates (frames per second)
    public static let availableScrollingRates: [Double] = [1, 2, 5, 10, 15, 20, 30, 60]
    
    /// Default scrolling update rate (frames per second)
    public static let defaultScrollingRate: Double = 30
    
    /// Available scrolling frame limit sizes (must be multiples of 2)
    public static let availableScrollingFrameLimits: [Int] = [2, 4, 8, 16, 32, 64, 128]
    
    /// Default scrolling frame limit
    public static let defaultScrollingFrameLimit: Int = 16
    
    /// Available scrolling frame limit sizes for Oscilloscope (up to 32k)
    public static let availableOscilloscopeScrollingFrameLimits: [Int] = [128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
    
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
    
    /// Calculate appropriate FFT window size from desired band quantity
    /// For better frequency resolution, we use 4x the band quantity as the window size
    /// This doubles the previous relationship (which was 2x) to provide better frequency resolution
    /// - Parameter bandQuantity: The desired number of frequency bands
    /// - Returns: The appropriate FFT window size (power of 2, rounded up)
    public static func calculateFFTWindowSize(for bandQuantity: Int) -> Int {
        // For N bands, we want 4*N window size (doubled from the previous 2*N relationship)
        // This gives us better frequency resolution
        let desiredWindowSize = 4 * bandQuantity
        
        // Round up to next power of 2
        var size = 8  // Minimum window size
        while size < desiredWindowSize {
            size *= 2
            // Safety check: don't exceed maximum available size
            if size > availableFFTWindowSizes.last! {
                return availableFFTWindowSizes.last!
            }
        }
        
        // Ensure it's at least the minimum
        return max(size, 8)
    }
    
    /// Calculate appropriate FFT band quantity for a given FFT window size
    /// For a real FFT, we get N/2+1 unique bins from N samples
    /// We should NEVER exceed N/2+1 to avoid mirroring artifacts
    /// Returns the appropriate band quantity based on the Nyquist setting
    /// - Parameters:
    ///   - windowSize: The FFT window size
    ///   - includeNyquist: If true, includes the +1 band (Nyquist frequency bin)
    public static func calculateAppropriateFFTBandQuantity(for windowSize: Int, includeNyquist: Bool = false) -> Int {
        // For window size N, we get N/2+1 unique bins
        // We must never exceed this to avoid mirroring
        let maxUniqueBands = windowSize / 2 + 1
        
        if includeNyquist {
            // If including Nyquist, use N/2+1 (all unique bins including Nyquist)
            // Return the exact value even if it's not in the available list
            return maxUniqueBands
        } else {
            // If not including Nyquist, use N/2 (safe, avoids mirroring, and is a nice round number)
            let halfWindow = windowSize / 2
            // Try to use a value from the available list if possible
            if availableFFTBandQuantities.contains(halfWindow) && halfWindow <= maxUniqueBands {
                return halfWindow
            }
            // Otherwise return the exact half value (it's always valid)
            return halfWindow
        }
    }
}

