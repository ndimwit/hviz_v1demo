import ComposableArchitecture
import Foundation

// MARK: - State

/// State for the Audio Visualizer feature
public struct AudioVisualizerFeature: Reducer {
    
    public struct State: Equatable {
        /// FFT magnitudes from audio analysis
        public var fftMagnitudes: [Float] = []
        
        /// Downsampled magnitudes for visualization
        public var downsampledMagnitudes: [Float] = []
        
        /// Whether audio monitoring is currently active
        public var isMonitoring = false
        
        /// Error message if any
        public var errorMessage: String?
        
        /// Maximum magnitude for chart scaling
        public var maxMagnitude: Float {
            max(fftMagnitudes.max() ?? 0, Constants.magnitudeLimit)
        }
        
        public init(
            fftMagnitudes: [Float] = [],
            downsampledMagnitudes: [Float] = [],
            isMonitoring: Bool = false,
            errorMessage: String? = nil
        ) {
            self.fftMagnitudes = fftMagnitudes
            self.downsampledMagnitudes = downsampledMagnitudes
            self.isMonitoring = isMonitoring
            self.errorMessage = errorMessage
        }
    }
    
    // MARK: - Action
    
    public enum Action: Equatable {
        /// User tapped start/stop button
        case toggleMonitoringTapped
        
        /// Audio monitoring started successfully
        case monitoringStarted
        
        /// Audio monitoring stopped
        case monitoringStopped
        
        /// FFT magnitudes were updated
        case magnitudesUpdated([Float])
        
        /// Downsampled magnitudes were updated
        case downsampledMagnitudesUpdated([Float])
        
        /// An error occurred
        case errorOccurred(String)
        
        /// Clear error message
        case clearError
    }
    
    // MARK: - Dependencies
    
    @Dependency(\.audioWaveformMonitor) var audioMonitor
    
    // MARK: - Reducer
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleMonitoringTapped:
                if state.isMonitoring {
                    return .run { [audioMonitor] send in
                        await audioMonitor.stopMonitoring()
                        await send(.monitoringStopped)
                    }
                } else {
                    return .run { [audioMonitor] send in
                        do {
                            try await audioMonitor.startMonitoring()
                            await send(.monitoringStarted)
                            
                            // Start observing magnitude updates
                            await observeMagnitudes(audioMonitor: audioMonitor, send: send)
                        } catch {
                            await send(.errorOccurred(error.localizedDescription))
                        }
                    }
                }
                
            case .monitoringStarted:
                state.isMonitoring = true
                state.errorMessage = nil
                return .none
                
            case .monitoringStopped:
                state.isMonitoring = false
                state.fftMagnitudes = []
                state.downsampledMagnitudes = []
                return .none
                
            case let .magnitudesUpdated(magnitudes):
                state.fftMagnitudes = magnitudes
                return .run { [audioMonitor] send in
                    let downsampled = await audioMonitor.downsampledMagnitudes
                    await send(.downsampledMagnitudesUpdated(downsampled))
                }
                
            case let .downsampledMagnitudesUpdated(magnitudes):
                state.downsampledMagnitudes = magnitudes
                return .none
                
            case let .errorOccurred(message):
                state.errorMessage = message
                state.isMonitoring = false
                return .none
                
            case .clearError:
                state.errorMessage = nil
                return .none
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Observe magnitude updates from the audio monitor
    private func observeMagnitudes(audioMonitor: AudioWaveformMonitor, send: Send<Action>) async {
        while await audioMonitor.isMonitoring {
            let magnitudes = await audioMonitor.fftMagnitudes
            await send(.magnitudesUpdated(magnitudes))
            
            // Update at ~30 FPS for smooth visualization
            try? await Task.sleep(nanoseconds: 33_333_333) // ~30ms
        }
    }
}

// MARK: - Dependency

extension DependencyValues {
    var audioWaveformMonitor: AudioWaveformMonitor {
        get { self[AudioWaveformMonitorKey.self] }
        set { self[AudioWaveformMonitorKey.self] = newValue }
    }
}

private struct AudioWaveformMonitorKey: @preconcurrency DependencyKey {
    static nonisolated(unsafe) var liveValue: AudioWaveformMonitor {
        AudioWaveformMonitor.shared
    }
}

