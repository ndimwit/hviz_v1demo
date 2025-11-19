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
        
        /// Selected visualizer preset
        public var selectedPreset: VisualizerPresetType = .lineChart
        
        /// Current frame rate (FPS) - rounded to 1 decimal place
        public var frameRate: Double = 0.0
        
        /// Timestamp of last magnitude update (not included in Equatable comparison)
        var lastUpdateTime: Date?
        
        /// Maximum magnitude for chart scaling
        public var maxMagnitude: Float {
            max(fftMagnitudes.max() ?? 0, Constants.magnitudeLimit)
        }
        
        public init(
            fftMagnitudes: [Float] = [],
            downsampledMagnitudes: [Float] = [],
            isMonitoring: Bool = false,
            errorMessage: String? = nil,
            selectedPreset: VisualizerPresetType = .lineChart,
            frameRate: Double = 0.0,
            lastUpdateTime: Date? = nil
        ) {
            self.fftMagnitudes = fftMagnitudes
            self.downsampledMagnitudes = downsampledMagnitudes
            self.isMonitoring = isMonitoring
            self.errorMessage = errorMessage
            self.selectedPreset = selectedPreset
            self.frameRate = frameRate
            self.lastUpdateTime = lastUpdateTime
        }
        
        // Custom Equatable implementation to exclude lastUpdateTime from comparison
        public static func == (lhs: State, rhs: State) -> Bool {
            lhs.fftMagnitudes == rhs.fftMagnitudes &&
            lhs.downsampledMagnitudes == rhs.downsampledMagnitudes &&
            lhs.isMonitoring == rhs.isMonitoring &&
            lhs.errorMessage == rhs.errorMessage &&
            lhs.selectedPreset == rhs.selectedPreset &&
            abs(lhs.frameRate - rhs.frameRate) < 0.1 // Consider equal if within 0.1 FPS
        }
        
        /// Update frame rate based on current time
        mutating func updateFrameRate() {
            let now = Date()
            if let lastTime = lastUpdateTime {
                let timeDelta = now.timeIntervalSince(lastTime)
                if timeDelta > 0 {
                    // Calculate FPS and round to 1 decimal place
                    let fps = 1.0 / timeDelta
                    frameRate = round(fps * 10) / 10.0
                }
            }
            lastUpdateTime = now
        }
    }
    
    // MARK: - Action
    
    public enum Action: Equatable {
        /// View appeared - auto-start monitoring
        case onAppear
        
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
        
        /// Preset selection changed
        case presetSelected(VisualizerPresetType)
    }
    
    // MARK: - Dependencies
    
    @Dependency(\.audioWaveformMonitor) var audioMonitor
    
    // MARK: - Reducer
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Auto-start monitoring if not already monitoring
                if !state.isMonitoring {
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
                return .none
                
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
                state.frameRate = 0.0
                state.lastUpdateTime = nil
                return .none
                
            case let .magnitudesUpdated(magnitudes):
                state.fftMagnitudes = magnitudes
                return .run { [audioMonitor] send in
                    let downsampled = await audioMonitor.downsampledMagnitudes
                    await send(.downsampledMagnitudesUpdated(downsampled))
                }
                
            case let .downsampledMagnitudesUpdated(magnitudes):
                state.downsampledMagnitudes = magnitudes
                state.updateFrameRate()
                return .none
                
            case let .errorOccurred(message):
                state.errorMessage = message
                state.isMonitoring = false
                return .none
                
            case .clearError:
                state.errorMessage = nil
                return .none
                
            case let .presetSelected(preset):
                state.selectedPreset = preset
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

