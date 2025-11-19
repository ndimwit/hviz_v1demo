import AVFoundation
import Accelerate
import Foundation

/// Service responsible for monitoring audio input and performing FFT analysis
@MainActor
final class AudioWaveformMonitor {
    
    // MARK: - Shared Instance
    
    static let shared = AudioWaveformMonitor()
    
    // MARK: - Properties
    
    /// Audio engine for accessing microphone input
    private var audioEngine = AVAudioEngine()
    
    /// FFT configuration buffer size
    private let bufferSize = 8192
    
    /// FFT configuration setup
    private var fftSetup: OpaquePointer?
    
    /// Store the FFT magnitude results
    var fftMagnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
    
    /// Track if audio monitoring is running
    var isMonitoring = false
    
    /// Pick a subset of fftMagnitudes at regular intervals according to the downsampleFactor
    var downsampledMagnitudes: [Float] {
        fftMagnitudes.lazy.enumerated().compactMap { index, value in
            index.isMultiple(of: Constants.downsampleFactor) ? value : nil
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring audio input from the microphone
    func startMonitoring() async throws {
        guard !isMonitoring else { return }
        
        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw AudioVisualizerError.microphonePermissionDenied
        }
        
        // Set up the input node from the audio engine
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create FFT setup
        fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            UInt(bufferSize),
            .FORWARD
        )
        
        guard fftSetup != nil else {
            throw AudioVisualizerError.fftSetupFailed
        }
        
        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: UInt32(bufferSize),
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert buffer to Float array
            guard let channelData = buffer.floatChannelData else { return }
            let channelDataValue = channelData.pointee
            let frameLength = Int(buffer.frameLength)
            let audioData = Array(UnsafeBufferPointer(
                start: channelDataValue,
                count: frameLength
            ))
            
            // Perform FFT asynchronously
            Task { @MainActor in
                let magnitudes = await self.performFFT(data: audioData)
                self.fftMagnitudes = magnitudes
            }
        }
        
        // Start the audio engine
        try audioEngine.start()
        isMonitoring = true
    }
    
    /// Stop monitoring audio input
    func stopMonitoring() async {
        guard isMonitoring else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            self.fftSetup = nil
        }
        
        // Reset magnitudes
        fftMagnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
        isMonitoring = false
    }
    
    // MARK: - Private Methods
    
    /// Request microphone permission
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Perform Fast Fourier Transform on audio data
    private func performFFT(data: [Float]) async -> [Float] {
        guard data.count >= bufferSize else {
            return [Float](repeating: 0, count: Constants.sampleAmount)
        }
        
        guard let fftSetup = fftSetup else {
            return [Float](repeating: 0, count: Constants.sampleAmount)
        }
        
        // Prepare input data (only use first bufferSize samples)
        let inputData = Array(data.prefix(bufferSize))
        
        // Allocate memory for FFT input (imaginary part is zero for real input)
        let inputImag = [Float](repeating: 0, count: bufferSize)
        
        // Allocate memory for FFT output
        var realOut = [Float](repeating: 0, count: bufferSize)
        var imagOut = [Float](repeating: 0, count: bufferSize)
        var magnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
        
        // Perform FFT using Accelerate framework
        inputData.withUnsafeBufferPointer { inputPtr in
            inputImag.withUnsafeBufferPointer { inputImagPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        // Execute DFT
                        vDSP_DFT_Execute(
                            fftSetup,
                            inputPtr.baseAddress!,
                            inputImagPtr.baseAddress!,
                            realOutPtr.baseAddress!,
                            imagOutPtr.baseAddress!
                        )
                    
                        // Hold the DFT output
                        var complex = DSPSplitComplex(
                            realp: realOutPtr.baseAddress!,
                            imagp: imagOutPtr.baseAddress!
                        )
                        
                        // Compute and save the magnitude of each frequency component
                        vDSP_zvabs(
                            &complex,
                            1,
                            &magnitudes,
                            1,
                            UInt(Constants.sampleAmount)
                        )
                    }
                }
            }
        }
        
        // Limit magnitudes to prevent distortion
        return magnitudes.map { min($0, Constants.magnitudeLimit) }
    }
}

// MARK: - Errors

public enum AudioVisualizerError: LocalizedError {
    case microphonePermissionDenied
    case fftSetupFailed
    
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable microphone access in Settings."
        case .fftSetupFailed:
            return "Failed to set up FFT processing."
        }
    }
}

