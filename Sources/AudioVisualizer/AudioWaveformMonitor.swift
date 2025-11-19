import AVFoundation
import Accelerate
import Foundation

/// Service responsible for monitoring audio input and performing FFT analysis
/// Uses AudioUnit for reliable Mac Catalyst support
@MainActor
final class AudioWaveformMonitor {
    
    // MARK: - Shared Instance
    
    static let shared = AudioWaveformMonitor()
    
    // MARK: - Properties
    
    /// AudioUnit-based monitor (reliable on Mac Catalyst)
    private let audioUnitMonitor = AudioUnitMonitor()
    
    /// Store the FFT magnitude results (delegated to AudioUnitMonitor)
    var fftMagnitudes: [Float] {
        audioUnitMonitor.fftMagnitudes
    }
    
    /// Track if audio monitoring is running (delegated to AudioUnitMonitor)
    var isMonitoring: Bool {
        audioUnitMonitor.isMonitoring
    }
    
    /// Pick a subset of fftMagnitudes at regular intervals according to the downsampleFactor
    var downsampledMagnitudes: [Float] {
        audioUnitMonitor.downsampledMagnitudes
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring audio input from the microphone
    /// Delegates to AudioUnitMonitor for reliable Mac Catalyst support
    /// - Parameters:
    ///   - bufferSize: FFT buffer size (must be power of 2, defaults to 8192)
    ///   - fftBandQuantity: Number of FFT bands to display (defaults to Constants.defaultFFTBandQuantity)
    func startMonitoring(bufferSize: Int = 8192, fftBandQuantity: Int = Constants.defaultFFTBandQuantity) async throws {
        try await audioUnitMonitor.startMonitoring(bufferSize: bufferSize, fftBandQuantity: fftBandQuantity)
    }
    
    /// Stop monitoring audio input
    /// Delegates to AudioUnitMonitor
    func stopMonitoring() async {
        await audioUnitMonitor.stopMonitoring()
    }
    
    /// Change the buffer size, stopping and restarting monitoring if needed
    /// - Parameter bufferSize: New FFT buffer size (must be power of 2)
    func changeBufferSize(_ bufferSize: Int) async throws {
        try await audioUnitMonitor.changeBufferSize(bufferSize)
    }
    
    /// Change the FFT band quantity, stopping and restarting monitoring if needed
    /// - Parameter fftBandQuantity: New number of FFT bands to display
    func changeFFTBandQuantity(_ fftBandQuantity: Int) async throws {
        try await audioUnitMonitor.changeFFTBandQuantity(fftBandQuantity)
    }
}

// MARK: - Errors

public enum AudioVisualizerError: LocalizedError {
    case microphonePermissionDenied
    case fftSetupFailed
    case invalidAudioFormat
    
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable microphone access in Settings."
        case .fftSetupFailed:
            return "Failed to set up FFT processing."
        case .invalidAudioFormat:
            return "Invalid audio format detected. Please try again."
        }
    }
}

