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
        
        /// Left channel audio samples for stereo visualization
        public var leftChannelSamples: [Float] = []
        
        /// Right channel audio samples for stereo visualization
        public var rightChannelSamples: [Float] = []
        
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
        
        /// Rendering mode (chunk or scrolling)
        public var renderingMode: RenderingMode = .chunk
        
        /// Scrolling update rate (frames per second)
        public var scrollingRate: Double = Constants.defaultScrollingRate
        
        /// Maximum number of frames to keep in scrolling buffer
        public var maxScrollingFrames: Int = Constants.defaultScrollingFrameLimit
        
        /// Scrolling buffer for historical frames (for scrolling mode)
        /// Circular buffer with fixed size to avoid reallocation
        /// Each element is a frame of data (magnitudes or samples)
        private var scrollingBuffer: [[Float]] = []
        
        /// Write index for circular buffer (points to next slot to write)
        private var scrollingBufferWriteIndex: Int = 0
        
        /// Number of frames currently stored in the circular buffer
        private var scrollingBufferCount: Int = 0
        
        /// Timestamp of last scrolling buffer update (not included in Equatable comparison)
        private var lastScrollingUpdateTime: Date?
        
        /// Continuous waveform buffer for smooth oscilloscope display (for continuous mode)
        /// Maintains a fixed-size rolling window of samples for phase-continuous display
        private var continuousWaveformBuffer: [Float] = []
        
        /// Maximum number of samples to keep in continuous waveform buffer
        /// This should be large enough to show multiple cycles of low-frequency signals
        private let maxContinuousSamples = 8192
        
        /// Last seen raw audio samples (tail portion) to detect new samples
        /// We track the last portion to identify where new samples start
        private var lastSeenSamples: [Float] = []
        
        /// Number of samples to compare for detecting new data (overlap window)
        private let overlapWindowSize = 512
        
        /// Last seen raw audio samples for oscilloscope scrolling mode
        /// Used to detect new samples since last frame update
        private var lastSeenOscilloscopeSamples: [Float] = []
        
        /// Current frame rate (FPS) - rounded to 1 decimal place
        public var frameRate: Double = 0.0
        
        /// FPS history for the last second (timestamp, FPS pairs)
        var fpsHistory: [(timestamp: Date, fps: Double)] = []
        
        /// Selected audio buffer size (FFT buffer size, must be power of 2)
        public var bufferSize: Int = Constants.defaultBufferSize
        
        /// FFT window size (must be power of 2, starting from 8)
        public var fftWindowSize: Int = Constants.defaultFFTWindowSize
        
        /// Whether to include the +1 band (Nyquist frequency bin)
        public var includeNyquistBand: Bool = false
        
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
            renderingMode: RenderingMode = .chunk,
            frameRate: Double = 0.0,
            lastUpdateTime: Date? = nil,
            bufferSize: Int = Constants.defaultBufferSize,
            fftBandQuantity: Int? = nil
        ) {
            self.fftMagnitudes = fftMagnitudes
            self.displayMagnitudes = displayMagnitudes.isEmpty ? fftMagnitudes : displayMagnitudes
            self.isMonitoring = isMonitoring
            self.errorMessage = errorMessage
            self.selectedPreset = selectedPreset
            self.renderingMode = renderingMode
            self.frameRate = frameRate
            self.lastUpdateTime = lastUpdateTime
            self.bufferSize = bufferSize
            self.fftWindowSize = Constants.defaultFFTWindowSize
            self.includeNyquistBand = false
            // Use provided band quantity or calculate appropriate one for the default FFT window size
            self.fftBandQuantity = fftBandQuantity ?? Constants.calculateAppropriateFFTBandQuantity(for: Constants.defaultFFTWindowSize, includeNyquist: false)
            self.scrollingRate = Constants.defaultScrollingRate
            self.maxScrollingFrames = Constants.defaultScrollingFrameLimit
        }
        
        // Custom Equatable implementation to exclude lastUpdateTime, fpsHistory, and interpolation state from comparison
        public static func == (lhs: State, rhs: State) -> Bool {
            lhs.fftMagnitudes == rhs.fftMagnitudes &&
            lhs.displayMagnitudes == rhs.displayMagnitudes &&
            lhs.rawAudioSamples == rhs.rawAudioSamples &&
            lhs.leftChannelSamples == rhs.leftChannelSamples &&
            lhs.rightChannelSamples == rhs.rightChannelSamples &&
            lhs.isMonitoring == rhs.isMonitoring &&
            lhs.errorMessage == rhs.errorMessage &&
            lhs.selectedPreset == rhs.selectedPreset &&
            lhs.renderingMode == rhs.renderingMode &&
            lhs.scrollingRate == rhs.scrollingRate &&
            lhs.maxScrollingFrames == rhs.maxScrollingFrames &&
            lhs.bufferSize == rhs.bufferSize &&
            lhs.fftWindowSize == rhs.fftWindowSize &&
            lhs.includeNyquistBand == rhs.includeNyquistBand &&
            lhs.fftBandQuantity == rhs.fftBandQuantity &&
            abs(lhs.frameRate - rhs.frameRate) < 0.1 // Consider equal if within 0.1 FPS
        }
        
        /// Update scrolling buffer with new frame data (rate-controlled)
        /// Uses a circular buffer to avoid reallocating memory
        mutating func updateScrollingBuffer(rawSamples: [Float]) {
            guard renderingMode == .scrolling else {
                // Clear buffer when not in scrolling mode
                scrollingBuffer.removeAll(keepingCapacity: false)
                scrollingBufferWriteIndex = 0
                scrollingBufferCount = 0
                lastScrollingUpdateTime = nil
                return
            }
            
            // Rate control: only update if enough time has passed
            let now = Date()
            if let lastUpdate = lastScrollingUpdateTime {
                let timeSinceLastUpdate = now.timeIntervalSince(lastUpdate)
                let minInterval = 1.0 / scrollingRate // Minimum time between updates
                
                // Skip update if not enough time has passed
                if timeSinceLastUpdate < minInterval {
                    return
                }
            }
            
            // For scrolling mode, determine which data to store based on preset
            // Oscilloscope uses rawSamples (time-domain), others use displayMagnitudes (frequency-domain)
            switch selectedPreset {
            case .oscilloscope:
                // Oscilloscope: store individual samples, introducing new ones since last frame
                let samplesToProcess = rawSamples.isEmpty ? displayMagnitudes : rawSamples
                
                if !samplesToProcess.isEmpty {
                    // Initialize buffer to fixed size if needed
                    if scrollingBuffer.count < maxScrollingFrames {
                        scrollingBuffer.reserveCapacity(maxScrollingFrames)
                        while scrollingBuffer.count < maxScrollingFrames {
                            scrollingBuffer.append([])
                        }
                    }
                    
                    // Detect new samples since last update
                    // Find where the tail of lastSeenOscilloscopeSamples overlaps with the beginning of samplesToProcess
                    let newSamples: [Float]
                    if lastSeenOscilloscopeSamples.isEmpty {
                        // First time - use all samples
                        newSamples = samplesToProcess
                    } else {
                        // Find the longest matching suffix of lastSeen that matches a prefix of current
                        let lastSeenTail = Array(lastSeenOscilloscopeSamples.suffix(min(overlapWindowSize, lastSeenOscilloscopeSamples.count)))
                        let searchWindow = min(overlapWindowSize, samplesToProcess.count)
                        
                        var bestMatchLength = 0
                        // Try different suffix lengths from lastSeenTail
                        for suffixLength in 1...min(lastSeenTail.count, searchWindow) {
                            let suffix = Array(lastSeenTail.suffix(suffixLength))
                            let prefix = Array(samplesToProcess.prefix(suffixLength))
                            
                            // Check if they match (with tolerance for floating point)
                            var matches = true
                            for i in 0..<suffixLength {
                                if abs(suffix[i] - prefix[i]) > 0.0001 {
                                    matches = false
                                    break
                                }
                            }
                            
                            if matches {
                                bestMatchLength = suffixLength
                            } else {
                                // Once we find a mismatch, no longer suffix will match
                                break
                            }
                        }
                        
                        if bestMatchLength > 0 && bestMatchLength < samplesToProcess.count {
                            // Extract new samples (everything after the overlap)
                            newSamples = Array(samplesToProcess[bestMatchLength...])
                        } else {
                            // No clear overlap found - use all samples (fallback)
                            newSamples = samplesToProcess
                        }
                    }
                    
                    // Store each new sample as a separate frame (earliest first)
                    // This way, new samples push old frames left
                    for sample in newSamples {
                        // Each frame contains a single sample value
                        scrollingBuffer[scrollingBufferWriteIndex] = [sample]
                        
                        // Update write index (wrap around)
                        scrollingBufferWriteIndex = (scrollingBufferWriteIndex + 1) % maxScrollingFrames
                        
                        // Update count (don't exceed max)
                        if scrollingBufferCount < maxScrollingFrames {
                            scrollingBufferCount += 1
                        }
                    }
                    
                    // Update last seen samples (keep tail for next comparison)
                    lastSeenOscilloscopeSamples = samplesToProcess
                    let tailSize = min(overlapWindowSize, samplesToProcess.count)
                    if lastSeenOscilloscopeSamples.count > tailSize {
                        lastSeenOscilloscopeSamples = Array(lastSeenOscilloscopeSamples.suffix(tailSize))
                    }
                    
                    // Update timestamp
                    lastScrollingUpdateTime = now
                }
                
            default:
                // Frequency-domain presets: use displayMagnitudes
                let currentFrame = displayMagnitudes.isEmpty ? fftMagnitudes : displayMagnitudes
                
                if !currentFrame.isEmpty {
                    // Initialize buffer to fixed size if needed
                    // Pre-allocate to avoid reallocation during runtime
                    if scrollingBuffer.count < maxScrollingFrames {
                        scrollingBuffer.reserveCapacity(maxScrollingFrames)
                        while scrollingBuffer.count < maxScrollingFrames {
                            scrollingBuffer.append([])
                        }
                    }
                    
                    // Write to circular buffer (reuse existing slot, no allocation)
                    // This overwrites the array reference, reusing the slot
                    scrollingBuffer[scrollingBufferWriteIndex] = currentFrame
                    
                    // Update write index (wrap around)
                    scrollingBufferWriteIndex = (scrollingBufferWriteIndex + 1) % maxScrollingFrames
                    
                    // Update count (don't exceed max)
                    if scrollingBufferCount < maxScrollingFrames {
                        scrollingBufferCount += 1
                    }
                    
                    // Update timestamp
                    lastScrollingUpdateTime = now
                }
            }
        }
        
        /// Clear the scrolling buffer
        mutating func clearScrollingBuffer() {
            scrollingBuffer.removeAll(keepingCapacity: false)
            scrollingBufferWriteIndex = 0
            scrollingBufferCount = 0
            lastScrollingUpdateTime = nil
            lastSeenOscilloscopeSamples = []
        }
        
        /// Resize the scrolling buffer to a new maximum frame limit
        /// This will clear the buffer and reinitialize it with the new size
        /// - Parameter newLimit: The new maximum number of frames
        /// - Parameter oldLimit: The previous maximum number of frames (for preserving data)
        mutating func resizeScrollingBuffer(to newLimit: Int, oldLimit: Int) {
            guard newLimit > 0 else {
                return
            }
            
            // If buffer is already initialized and new limit is different, resize it
            if scrollingBuffer.count > 0 {
                // If new limit is smaller, we need to adjust the buffer
                if newLimit < oldLimit {
                    // Truncate buffer to new size, preserving the most recent frames
                    // Since we're using a circular buffer, we need to extract the most recent frames
                    let oldBuffer = scrollingBuffer
                    let oldCount = scrollingBufferCount
                    let oldWriteIndex = scrollingBufferWriteIndex
                    
                    // Clear and reinitialize
                    scrollingBuffer.removeAll(keepingCapacity: false)
                    scrollingBuffer.reserveCapacity(newLimit)
                    while scrollingBuffer.count < newLimit {
                        scrollingBuffer.append([])
                    }
                    
                    // Copy the most recent frames (up to newLimit)
                    let framesToKeep = min(oldCount, newLimit)
                    if framesToKeep > 0 {
                        // Calculate starting index for old buffer (oldest frame to keep)
                        let startIndex = oldCount == oldLimit 
                            ? (oldWriteIndex + (oldCount - framesToKeep)) % oldLimit
                            : oldCount - framesToKeep
                        
                        // Copy frames to new buffer
                        for i in 0..<framesToKeep {
                            let oldIndex = (startIndex + i) % oldLimit
                            scrollingBuffer[i] = oldBuffer[oldIndex]
                        }
                        
                        scrollingBufferCount = framesToKeep
                        scrollingBufferWriteIndex = framesToKeep % newLimit
                    } else {
                        scrollingBufferCount = 0
                        scrollingBufferWriteIndex = 0
                    }
                } else if newLimit > oldLimit {
                    // Expand buffer to new size
                    scrollingBuffer.reserveCapacity(newLimit)
                    while scrollingBuffer.count < newLimit {
                        scrollingBuffer.append([])
                    }
                    // Adjust write index if needed (shouldn't be necessary, but be safe)
                    scrollingBufferWriteIndex = scrollingBufferWriteIndex % newLimit
                }
            }
            // If buffer is empty, it will be initialized on next update with the new limit
        }
        
        /// Clear the continuous waveform buffer
        mutating func clearContinuousWaveformBuffer() {
            continuousWaveformBuffer.removeAll()
            lastSeenSamples.removeAll()
        }
        
        /// Reset the scrolling update timer (allows immediate update)
        mutating func resetScrollingUpdateTimer() {
            lastScrollingUpdateTime = nil
        }
        
        /// Get scrolling data (read-only)
        /// Returns frames in chronological order (oldest to newest)
        public var scrollingData: [[Float]]? {
            guard renderingMode == .scrolling && scrollingBufferCount > 0 else {
                return nil
            }
            
            // Return frames in chronological order (oldest to newest)
            // Start from the oldest frame and wrap around
            var result: [[Float]] = []
            result.reserveCapacity(scrollingBufferCount)
            
            // Calculate the starting index (oldest frame)
            // If buffer is full, oldest is at writeIndex (next to be overwritten)
            // If buffer is not full, oldest is at index 0
            let startIndex: Int
            if scrollingBufferCount == maxScrollingFrames {
                // Buffer is full, oldest frame is at writeIndex
                startIndex = scrollingBufferWriteIndex
            } else {
                // Buffer is not full, oldest frame is at index 0
                startIndex = 0
            }
            
            // Collect frames in chronological order
            for i in 0..<scrollingBufferCount {
                let index = (startIndex + i) % maxScrollingFrames
                result.append(scrollingBuffer[index])
            }
            
            return result
        }
        
        /// Update continuous waveform buffer with new samples
        /// Maintains a rolling window for smooth, phase-continuous waveform display
        mutating func updateContinuousWaveformBuffer(newSamples: [Float]) {
            guard renderingMode == .continuous else {
                // Clear buffer when not in continuous mode
                if !continuousWaveformBuffer.isEmpty {
                    continuousWaveformBuffer.removeAll()
                }
                lastSeenSamples.removeAll()
                return
            }
            
            guard !newSamples.isEmpty else {
                return
            }
            
            // Since rawAudioSamples is a rolling window that appends new samples to the end
            // and removes old ones from the front, we need to find where new data starts.
            // We do this by comparing the tail of what we last saw with the beginning of newSamples.
            
            if lastSeenSamples.isEmpty {
                // First time - initialize with all samples
                continuousWaveformBuffer = newSamples
                // Store the tail for next comparison
                let tailSize = min(overlapWindowSize, newSamples.count)
                lastSeenSamples = Array(newSamples.suffix(tailSize))
                return
            }
            
            // Find where lastSeenSamples (the tail we saw) appears in the new buffer
            // This tells us where the overlap ends and new data begins
            var newDataStartIndex = 0
            var foundOverlap = false
            
            // Search for lastSeenSamples at the beginning of newSamples
            // The tail we saw should appear somewhere near the start of the new buffer
            let searchLimit = min(newSamples.count, lastSeenSamples.count + overlapWindowSize)
            
            for startIndex in 0..<searchLimit {
                let remaining = newSamples.count - startIndex
                if remaining < lastSeenSamples.count {
                    break
                }
                
                // Compare lastSeenSamples with a slice of newSamples starting at startIndex
                let slice = Array(newSamples[startIndex..<(startIndex + lastSeenSamples.count)])
                let matches = zip(lastSeenSamples, slice).allSatisfy { abs($0 - $1) < 0.0001 }
                
                if matches {
                    // Found overlap - new data starts after this match
                    newDataStartIndex = startIndex + lastSeenSamples.count
                    foundOverlap = true
                    break
                }
            }
            
            // If no overlap found, the buffer might have been reset or changed significantly
            // In this case, add all samples as new data
            if !foundOverlap {
                // Check if buffer was completely replaced (different size or no match)
                // Add all samples as new
                newDataStartIndex = 0
            }
            
            // Extract and add only the new samples
            if newDataStartIndex < newSamples.count {
                let newSamplesToAdd = Array(newSamples[newDataStartIndex...])
                if !newSamplesToAdd.isEmpty {
                    continuousWaveformBuffer.append(contentsOf: newSamplesToAdd)
                    
                    // Maintain fixed-size rolling window
                    if continuousWaveformBuffer.count > maxContinuousSamples {
                        let samplesToRemove = continuousWaveformBuffer.count - maxContinuousSamples
                        continuousWaveformBuffer.removeFirst(samplesToRemove)
                    }
                }
            }
            
            // Update last seen samples (store tail of new buffer for next comparison)
            let tailSize = min(overlapWindowSize, newSamples.count)
            lastSeenSamples = Array(newSamples.suffix(tailSize))
        }
        
        /// Get continuous waveform data (read-only)
        public var continuousWaveformData: [Float]? {
            guard renderingMode == .continuous && !continuousWaveformBuffer.isEmpty else {
                return nil
            }
            return continuousWaveformBuffer
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
        
        /// Stereo channel samples were updated
        case stereoSamplesUpdated(left: [Float], right: [Float])
        
        /// An error occurred
        case errorOccurred(String)
        
        /// Clear error message
        case clearError
        
        /// Preset selection changed
        case presetSelected(VisualizerPresetType)
        
        /// Rendering mode selection changed
        case renderingModeSelected(RenderingMode)
        
        /// Scrolling rate selection changed
        case scrollingRateSelected(Double)
        
        /// Maximum scrolling frames selection changed
        case maxScrollingFramesSelected(Int)
        
        /// Buffer size selection changed
        case bufferSizeSelected(Int)
        
        /// FFT window size selection changed
        case fftWindowSizeSelected(Int)
        
        /// FFT band quantity selection changed
        case fftBandQuantitySelected(Int)
        
        /// Include Nyquist band toggle changed
        case includeNyquistBandToggled(Bool)
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
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftWindowSize = state.fftWindowSize, fftBandQuantity = state.fftBandQuantity] send in
                        do {
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftWindowSize: fftWindowSize, fftBandQuantity: fftBandQuantity)
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
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftWindowSize = state.fftWindowSize, fftBandQuantity = state.fftBandQuantity] send in
                        do {
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftWindowSize: fftWindowSize, fftBandQuantity: fftBandQuantity)
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
                state.leftChannelSamples = []
                state.rightChannelSamples = []
                state.clearScrollingBuffer()
                // Clear continuous waveform buffer
                state.clearContinuousWaveformBuffer()
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
                state.updateScrollingBuffer(rawSamples: state.rawAudioSamples)
                state.updateFrameRate()
                return .none
                
            case .interpolationTick:
                // Continuously update interpolation even when no new FFT data arrives
                state.updateDisplayMagnitudes()
                state.updateScrollingBuffer(rawSamples: state.rawAudioSamples)
                state.updateFrameRate()
                return .none
                
            case let .rawSamplesUpdated(samples):
                state.rawAudioSamples = samples
                state.updateScrollingBuffer(rawSamples: samples)
                state.updateContinuousWaveformBuffer(newSamples: samples)
                return .none
                
            case let .stereoSamplesUpdated(left, right):
                state.leftChannelSamples = left
                state.rightChannelSamples = right
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
                // Clear scrolling buffer when switching presets to ensure clean transition
                state.clearScrollingBuffer()
                return .none
                
            case let .renderingModeSelected(mode):
                state.renderingMode = mode
                // Clear scrolling buffer when switching modes
                state.clearScrollingBuffer()
                // Clear continuous waveform buffer when switching modes
                state.clearContinuousWaveformBuffer()
                return .none
                
            case let .scrollingRateSelected(rate):
                state.scrollingRate = rate
                // Reset update timer to allow immediate update with new rate
                state.resetScrollingUpdateTimer()
                return .none
                
            case let .maxScrollingFramesSelected(newLimit):
                // Only change if different
                guard newLimit != state.maxScrollingFrames else {
                    return .none
                }
                let oldLimit = state.maxScrollingFrames
                state.maxScrollingFrames = newLimit
                // Resize the buffer (preserves recent frames if possible)
                state.resizeScrollingBuffer(to: newLimit, oldLimit: oldLimit)
                return .none
                
            case let .bufferSizeSelected(newBufferSize):
                // Only change if different
                guard newBufferSize != state.bufferSize else {
                    return .none
                }
                
                let wasMonitoring = state.isMonitoring
                state.bufferSize = newBufferSize
                
                // Buffer size does NOT change FFT band quantity - only affects audio accumulation rate
                // If monitoring, restart with new buffer size (preserving FFT window size and band quantity)
                if wasMonitoring {
                    // Set monitoring to false temporarily to reflect the stop
                    state.isMonitoring = false
                    
                    return .run { [audioMonitor, bufferSize = newBufferSize, fftWindowSize = state.fftWindowSize, fftBandQuantity = state.fftBandQuantity] send in
                        do {
                            // Stop and restart with new buffer size
                            await audioMonitor.stopMonitoring()
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftWindowSize: fftWindowSize, fftBandQuantity: fftBandQuantity)
                            await send(.monitoringStarted)
                            
                            // Start observing magnitude updates
                            await observeMagnitudes(audioMonitor: audioMonitor, send: send)
                        } catch {
                            await send(.errorOccurred(error.localizedDescription))
                        }
                    }
                }
                
                return .none
                
            case let .fftWindowSizeSelected(newWindowSize):
                // Only change if different
                guard newWindowSize != state.fftWindowSize else {
                    return .none
                }
                
                let wasMonitoring = state.isMonitoring
                state.fftWindowSize = newWindowSize
                
                // Auto-select appropriate FFT band quantity for the new window size
                let appropriateBandQuantity = Constants.calculateAppropriateFFTBandQuantity(for: newWindowSize, includeNyquist: state.includeNyquistBand)
                state.fftBandQuantity = appropriateBandQuantity
                
                // Clear magnitude buffers and interpolation state to prevent mirroring from stale data
                // This ensures a clean transition when window size changes
                state.fftMagnitudes = []
                state.displayMagnitudes = []
                state.updateDisplayMagnitudes() // This will reset interpolation state
                state.clearScrollingBuffer()
                
                // If monitoring, restart with new FFT window size and auto-selected band quantity
                if wasMonitoring {
                    // Set monitoring to false temporarily to reflect the stop
                    state.isMonitoring = false
                    
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftWindowSize = newWindowSize, fftBandQuantity = appropriateBandQuantity] send in
                        do {
                            // Stop and restart with new FFT window size and appropriate band quantity
                            await audioMonitor.stopMonitoring()
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftWindowSize: fftWindowSize, fftBandQuantity: fftBandQuantity)
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
                
                // Clear magnitude buffers and interpolation state to prevent mirroring from stale data
                // This ensures a clean transition when band quantity changes
                state.fftMagnitudes = []
                state.displayMagnitudes = []
                state.updateDisplayMagnitudes() // This will reset interpolation state
                state.clearScrollingBuffer()
                
                // If monitoring, restart with new FFT band quantity
                if wasMonitoring {
                    // Set monitoring to false temporarily to reflect the stop
                    state.isMonitoring = false
                    
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftWindowSize = state.fftWindowSize, fftBandQuantity = newBandQuantity] send in
                        do {
                            // Stop and restart with new FFT band quantity
                            await audioMonitor.stopMonitoring()
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftWindowSize: fftWindowSize, fftBandQuantity: fftBandQuantity)
                            await send(.monitoringStarted)
                            
                            // Start observing magnitude updates
                            await observeMagnitudes(audioMonitor: audioMonitor, send: send)
                        } catch {
                            await send(.errorOccurred(error.localizedDescription))
                        }
                    }
                }
                
                return .none
                
            case let .includeNyquistBandToggled(includeNyquist):
                // Only change if different
                guard includeNyquist != state.includeNyquistBand else {
                    return .none
                }
                
                let wasMonitoring = state.isMonitoring
                state.includeNyquistBand = includeNyquist
                
                // Recalculate FFT band quantity with new Nyquist setting
                let appropriateBandQuantity = Constants.calculateAppropriateFFTBandQuantity(for: state.fftWindowSize, includeNyquist: includeNyquist)
                print("🔄 [AudioVisualizer] Nyquist toggle changed: includeNyquist=\(includeNyquist), windowSize=\(state.fftWindowSize), newBandQuantity=\(appropriateBandQuantity)")
                state.fftBandQuantity = appropriateBandQuantity
                
                // Clear magnitude buffers and interpolation state when Nyquist setting changes
                state.fftMagnitudes = []
                state.displayMagnitudes = []
                state.updateDisplayMagnitudes() // This will reset interpolation state
                state.clearScrollingBuffer()
                
                // If monitoring, restart with new band quantity
                if wasMonitoring {
                    // Set monitoring to false temporarily to reflect the stop
                    state.isMonitoring = false
                    
                    return .run { [audioMonitor, bufferSize = state.bufferSize, fftWindowSize = state.fftWindowSize, fftBandQuantity = appropriateBandQuantity] send in
                        do {
                            // Stop and restart with new band quantity
                            await audioMonitor.stopMonitoring()
                            try await audioMonitor.startMonitoring(bufferSize: bufferSize, fftWindowSize: fftWindowSize, fftBandQuantity: fftBandQuantity)
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
            let leftSamples = await audioMonitor.leftChannelSamples
            let rightSamples = await audioMonitor.rightChannelSamples
            await send(.magnitudesUpdated(magnitudes))
            await send(.rawSamplesUpdated(rawSamples))
            await send(.stereoSamplesUpdated(left: leftSamples, right: rightSamples))
            
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

