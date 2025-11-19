import ComposableArchitecture
import Foundation

// MARK: - State

/// State for the Audio Visualizer feature
public struct AudioVisualizerFeature: Reducer {
    
    public struct State: Equatable {
        /// FFT magnitudes from audio analysis (raw, from FFT calculation)
        public var fftMagnitudes: [Float] = []
        
        /// Smoothed/interpolated FFT magnitudes for display
        public var displayMagnitudes: [Float] = []
        
        /// Raw audio samples for time-domain visualization (oscilloscope)
        public var rawAudioSamples: [Float] = []
        
        /// Previous FFT magnitudes for interpolation (the starting point for interpolation)
        private var previousFFTMagnitudes: [Float] = []
        
        /// Last FFT result we received (for detecting new updates)
        private var lastReceivedFFT: [Float] = []
        
        /// Timestamp of last FFT update
        private var lastFFTUpdateTime: Date?
        
        /// Interpolation progress (0.0 to 1.0) between previous and current magnitudes
        private var interpolationProgress: Double = 0.0
        
        /// Whether audio monitoring is currently active
        public var isMonitoring = false
        
        /// Error message if any
        public var errorMessage: String?
        
        /// Selected visualizer preset
        public var selectedPreset: VisualizerPresetType = .lineChart
        
        /// Current frame rate (FPS) - rounded to 1 decimal place
        public var frameRate: Double = 0.0
        
        /// FPS history for the last second (timestamp, FPS pairs)
        var fpsHistory: [(timestamp: Date, fps: Double)] = []
        
        /// Selected audio buffer size (FFT buffer size, must be power of 2)
        public var bufferSize: Int = Constants.defaultBufferSize
        
        /// Number of FFT bands to display
        public var fftBandQuantity: Int = Constants.defaultFFTBandQuantity
        
        /// Timestamp of last magnitude update (not included in Equatable comparison)
        var lastUpdateTime: Date?
        
        /// FPS statistics for the last second
        public struct FPSStatistics {
            public let mean: Double
            public let min: Double
            public let max: Double
            
            public init(mean: Double, min: Double, max: Double) {
                self.mean = mean
                self.min = min
                self.max = max
            }
        }
        
        /// Calculate FPS statistics from the last second of data
        public var fpsStatistics: FPSStatistics {
            let oneSecondAgo = Date().addingTimeInterval(-1.0)
            let recentFPS = fpsHistory.filter { $0.timestamp >= oneSecondAgo }.map { $0.fps }
            
            guard !recentFPS.isEmpty else {
                return FPSStatistics(mean: 0, min: 0, max: 0)
            }
            
            let mean = recentFPS.reduce(0, +) / Double(recentFPS.count)
            let min = recentFPS.min() ?? 0
            let max = recentFPS.max() ?? 0
            
            return FPSStatistics(
                mean: round(mean * 10) / 10.0,
                min: round(min * 10) / 10.0,
                max: round(max * 10) / 10.0
            )
        }
        
        /// Maximum magnitude for chart scaling (use display magnitudes for smoother scaling)
        public var maxMagnitude: Float {
            max(displayMagnitudes.max() ?? fftMagnitudes.max() ?? 0, Constants.magnitudeLimit)
        }
        
        public init(
            fftMagnitudes: [Float] = [],
            displayMagnitudes: [Float] = [],
            isMonitoring: Bool = false,
            errorMessage: String? = nil,
            selectedPreset: VisualizerPresetType = .lineChart,
            frameRate: Double = 0.0,
            lastUpdateTime: Date? = nil,
            bufferSize: Int = Constants.defaultBufferSize,
            fftBandQuantity: Int = Constants.defaultFFTBandQuantity
        ) {
            self.fftMagnitudes = fftMagnitudes
            self.displayMagnitudes = displayMagnitudes.isEmpty ? fftMagnitudes : displayMagnitudes
            self.isMonitoring = isMonitoring
            self.errorMessage = errorMessage
            self.selectedPreset = selectedPreset
            self.frameRate = frameRate
            self.lastUpdateTime = lastUpdateTime
            self.bufferSize = bufferSize
            self.fftBandQuantity = fftBandQuantity
        }
        
        // Custom Equatable implementation to exclude lastUpdateTime, fpsHistory, and interpolation state from comparison
        public static func == (lhs: State, rhs: State) -> Bool {
            lhs.fftMagnitudes == rhs.fftMagnitudes &&
            lhs.displayMagnitudes == rhs.displayMagnitudes &&
            lhs.rawAudioSamples == rhs.rawAudioSamples &&
            lhs.isMonitoring == rhs.isMonitoring &&
            lhs.errorMessage == rhs.errorMessage &&
            lhs.selectedPreset == rhs.selectedPreset &&
            lhs.bufferSize == rhs.bufferSize &&
            lhs.fftBandQuantity == rhs.fftBandQuantity &&
            abs(lhs.frameRate - rhs.frameRate) < 0.1 // Consider equal if within 0.1 FPS
        }
        
        /// Update display magnitudes with interpolation/smoothing
        mutating func updateDisplayMagnitudes() {
            let now = Date()
            
            // If we have new FFT data, start interpolation
            if !fftMagnitudes.isEmpty {
                // Check if this is a new FFT update by comparing with last received FFT
                let isNewUpdate = lastReceivedFFT.isEmpty || 
                                 fftMagnitudes.count != lastReceivedFFT.count ||
                                 (lastReceivedFFT.count == fftMagnitudes.count && 
                                  zip(fftMagnitudes, lastReceivedFFT).contains { abs($0 - $1) > 0.01 })
                
                if isNewUpdate {
                    // New FFT data arrived - start interpolation from current display position
                    if previousFFTMagnitudes.isEmpty {
                        // First update - initialize everything
                        previousFFTMagnitudes = fftMagnitudes
                        displayMagnitudes = fftMagnitudes
                        lastReceivedFFT = fftMagnitudes
                    } else {
                        // New FFT data - start interpolating from current display to new FFT
                        // Update previous to current display (where we are now)
                        if displayMagnitudes.count == fftMagnitudes.count {
                            previousFFTMagnitudes = displayMagnitudes
                        } else {
                            // Size mismatch - use last received FFT as starting point
                            previousFFTMagnitudes = lastReceivedFFT
                            displayMagnitudes = lastReceivedFFT
                        }
                        // Update last received to track this new FFT
                        lastReceivedFFT = fftMagnitudes
                    }
                    // Reset interpolation timer
                    lastFFTUpdateTime = now
                    interpolationProgress = 0.0
                }
                
                // Calculate interpolation progress based on time since last FFT update
                // Use a longer interpolation duration to smooth out slower FFT updates
                // For 1024 buffer at 44.1kHz, FFT updates ~every 23ms, so use ~50ms for smooth transition
                if let lastFFTTime = lastFFTUpdateTime {
                    let timeSinceFFT = now.timeIntervalSince(lastFFTTime)
                    let interpolationDuration = 0.05 // 50ms - allows smooth interpolation even with slower FFT
                    interpolationProgress = min(timeSinceFFT / interpolationDuration, 1.0)
                } else {
                    // No timestamp yet - initialize it
                    lastFFTUpdateTime = now
                    interpolationProgress = 0.0
                }
                
                // Interpolate between previous (starting point) and current FFT (target)
                if !previousFFTMagnitudes.isEmpty && previousFFTMagnitudes.count == fftMagnitudes.count {
                    displayMagnitudes = zip(previousFFTMagnitudes, fftMagnitudes).map { prev, curr in
                        // Linear interpolation with smoothstep easing for smoother transitions
                        let t = Float(interpolationProgress)
                        // Use smoothstep for easing (smooth S-curve)
                        let easedT = t * t * (3.0 - 2.0 * t)
                        return prev + (curr - prev) * easedT
                    }
                    
                    // Once interpolation is complete, update previous to current for next cycle
                    if interpolationProgress >= 1.0 {
                        previousFFTMagnitudes = fftMagnitudes
                    }
                } else if previousFFTMagnitudes.count != fftMagnitudes.count {
                    // Size mismatch - reset
                    displayMagnitudes = fftMagnitudes
                    previousFFTMagnitudes = fftMagnitudes
                    lastReceivedFFT = fftMagnitudes
                } else if previousFFTMagnitudes.isEmpty {
                    // No previous data - use current directly
                    displayMagnitudes = fftMagnitudes
                    previousFFTMagnitudes = fftMagnitudes
                    lastReceivedFFT = fftMagnitudes
                }
            } else {
                displayMagnitudes = []
                previousFFTMagnitudes = []
                lastReceivedFFT = []
            }
        }
        
        /// Update frame rate based on current time
        mutating func updateFrameRate() {
            let now = Date()
            if let lastTime = lastUpdateTime {
                let timeDelta = now.timeIntervalSince(lastTime)
                // Only calculate FPS if timeDelta is reasonable (at least 1ms = 0.001 seconds)
                // This prevents unrealistic FPS values from rapid successive updates
                // Minimum timeDelta of 0.001 seconds = max 1000 FPS (which we'll cap at 120)
                if timeDelta >= 0.001 {
                    // Calculate FPS and cap at reasonable maximum (120 FPS for display)
                    // This represents a realistic maximum frame rate for most displays
                    let fps = min(1.0 / timeDelta, 120.0)
                    frameRate = round(fps * 10) / 10.0
                    
                    // Add to FPS history
                    fpsHistory.append((timestamp: now, fps: frameRate))
                    
                    // Remove entries older than 1 second
                    let oneSecondAgo = now.addingTimeInterval(-1.0)
                    fpsHistory.removeAll { $0.timestamp < oneSecondAgo }
                }
                // If timeDelta is too small (< 1ms), skip this measurement
                // but still update lastUpdateTime to prevent accumulation
            }
            // Always update lastUpdateTime to track when we last checked
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
        
        /// Periodic update for interpolation (called even when no new FFT data)
        case interpolationTick
        
        /// Raw audio samples were updated
        case rawSamplesUpdated([Float])
        
        /// An error occurred
        case errorOccurred(String)
        
        /// Clear error message
        case clearError
        
        /// Preset selection changed
        case presetSelected(VisualizerPresetType)
        
        /// Buffer size selection changed
        case bufferSizeSelected(Int)
        
        /// FFT band quantity selection changed
        case fftBandQuantitySelected(Int)
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
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftBandQuantity = state.fftBandQuantity] send in
                        do {
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftBandQuantity: fftBandQuantity)
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
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftBandQuantity = state.fftBandQuantity] send in
                        do {
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftBandQuantity: fftBandQuantity)
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
                state.displayMagnitudes = []
                state.rawAudioSamples = []
                // previousFFTMagnitudes will be reset automatically when updateDisplayMagnitudes is called with empty data
                state.frameRate = 0.0
                state.fpsHistory.removeAll()
                state.lastUpdateTime = nil
                // Reset interpolation state by calling updateDisplayMagnitudes
                state.updateDisplayMagnitudes()
                return .none
                
            case let .magnitudesUpdated(magnitudes):
                state.fftMagnitudes = magnitudes
                state.updateDisplayMagnitudes()
                state.updateFrameRate()
                return .none
                
            case .interpolationTick:
                // Continuously update interpolation even when no new FFT data arrives
                state.updateDisplayMagnitudes()
                state.updateFrameRate()
                return .none
                
            case let .rawSamplesUpdated(samples):
                state.rawAudioSamples = samples
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
                
            case let .bufferSizeSelected(newBufferSize):
                // Only change if different
                guard newBufferSize != state.bufferSize else {
                    return .none
                }
                
                let wasMonitoring = state.isMonitoring
                let currentBandQuantity = state.fftBandQuantity
                state.bufferSize = newBufferSize
                
                // If monitoring, restart with new buffer size
                if wasMonitoring {
                    // Set monitoring to false temporarily to reflect the stop
                    state.isMonitoring = false
                    
                    return .run { [audioMonitor, bufferSize = newBufferSize, fftBandQuantity = currentBandQuantity] send in
                        do {
                            // Stop and restart with new buffer size, preserving band quantity
                            await audioMonitor.stopMonitoring()
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftBandQuantity: fftBandQuantity)
                            await send(.monitoringStarted)
                            
                            // Start observing magnitude updates
                            await observeMagnitudes(audioMonitor: audioMonitor, send: send)
                        } catch {
                            await send(.errorOccurred(error.localizedDescription))
                        }
                    }
                }
                
                return .none
                
            case let .fftBandQuantitySelected(newBandQuantity):
                // Only change if different
                guard newBandQuantity != state.fftBandQuantity else {
                    return .none
                }
                
                let wasMonitoring = state.isMonitoring
                state.fftBandQuantity = newBandQuantity
                
                // If monitoring, restart with new band quantity
                if wasMonitoring {
                    // Set monitoring to false temporarily to reflect the stop
                    state.isMonitoring = false
                    
                    return .run { [audioMonitor, bandQuantity = newBandQuantity] send in
                        do {
                            // Change FFT band quantity (this will stop and restart internally)
                            try await audioMonitor.changeFFTBandQuantity(bandQuantity)
                            await send(.monitoringStarted)
                            
                            // Start observing magnitude updates
                            await observeMagnitudes(audioMonitor: audioMonitor, send: send)
                        } catch {
                            await send(.errorOccurred(error.localizedDescription))
                        }
                    }
                }
                
                return .none
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Observe magnitude updates from the audio monitor
    private func observeMagnitudes(audioMonitor: AudioWaveformMonitor, send: Send<Action>) async {
        // Start a separate task for periodic interpolation updates
        let interpolationTask = Task {
            while await audioMonitor.isMonitoring {
                await send(.interpolationTick)
                // Update at ~60 FPS for smooth interpolation
                try? await Task.sleep(nanoseconds: 16_666_666) // ~16.67ms = 60 FPS
            }
        }
        
        // Main loop: check for new FFT data and raw samples
        while await audioMonitor.isMonitoring {
            let magnitudes = await audioMonitor.fftMagnitudes
            let rawSamples = await audioMonitor.rawAudioSamples
            await send(.magnitudesUpdated(magnitudes))
            await send(.rawSamplesUpdated(rawSamples))
            
            // Check for updates at ~60 FPS
            try? await Task.sleep(nanoseconds: 16_666_666) // ~16.67ms = 60 FPS
        }
        
        // Cancel interpolation task when monitoring stops
        interpolationTask.cancel()
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

