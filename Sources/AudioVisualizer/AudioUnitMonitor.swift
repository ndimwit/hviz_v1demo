import AVFoundation
import Accelerate
import Foundation
import AudioUnit
#if targetEnvironment(macCatalyst) || os(macOS)
import CoreAudio
#endif

// MARK: - Verbose FFT Debugging
// To enable verbose FFT debugging messages, add the compiler flag "VERBOSE_FFT_DEBUG" to your Xcode project:
// 1. Select your project in Xcode
// 2. Select your target
// 3. Go to Build Settings
// 4. Search for "Other Swift Flags" or "Swift Compiler - Custom Flags"
// 5. Add "-D VERBOSE_FFT_DEBUG" to the flags for Debug configuration (or both Debug and Release)
// See VERBOSE_FFT_DEBUG_SETUP.md for detailed instructions.

/// AudioUnit-based monitor for reliable microphone access on Mac Catalyst
/// Uses RemoteIO AudioUnit for direct hardware access, bypassing AVAudioEngine issues
/// Note: C callbacks run on background threads, so we handle thread safety internally
final class AudioUnitMonitor {
    
    // MARK: - Properties
    
    /// Audio unit instance (needs to be accessible from C callback)
    var audioUnit: AudioUnit?
    
    /// Audio buffer size (must be power of 2)
    private var bufferSize: Int = Constants.defaultBufferSize
    
    /// FFT window size (must be power of 2, starting from 8)
    private var fftWindowSize: Int = Constants.defaultFFTWindowSize
    
    /// Number of FFT bands to display
    /// Initialized to appropriate value for default window size to avoid mirroring
    private var fftBandQuantity: Int = Constants.calculateAppropriateFFTBandQuantity(for: Constants.defaultFFTWindowSize, includeNyquist: false)
    
    /// FFT configuration setup
    private var fftSetup: OpaquePointer?
    
    /// Store the FFT magnitude results (thread-safe access via MainActor)
    @MainActor private(set) var fftMagnitudes: [Float] = []
    
    /// Store recent raw audio samples for time-domain visualization (oscilloscope)
    /// Keeps a rolling window of the most recent samples
    @MainActor private(set) var rawAudioSamples: [Float] = []
    
    /// Maximum number of raw samples to keep for visualization
    private let maxRawSamples = 4096
    
    /// Track if audio monitoring is running
    var isMonitoring = false
    
    /// Audio format description
    private var audioFormat: AudioStreamBasicDescription?
    
    /// Buffer for accumulating audio samples
    private var sampleBuffer: [Float] = []
    
    /// Lock for thread-safe buffer access
    private let bufferLock = NSLock()
    
    /// Counter for render callback invocations (for debugging)
    private var callbackInvocationCount: Int = 0
    
    /// Counter for processAudioBuffer calls (for debugging)
    private var processCallbackCount: Int = 0
    
    /// Pick a subset of fftMagnitudes at regular intervals according to the downsampleFactor
    @MainActor var downsampledMagnitudes: [Float] {
        fftMagnitudes.lazy.enumerated().compactMap { index, value in
            index.isMultiple(of: Constants.downsampleFactor) ? value : nil
        }
    }
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        // Clean up FFT setup if object is deallocated
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring audio input from the microphone
    /// - Parameters:
    ///   - bufferSize: Audio buffer size (must be power of 2, defaults to Constants.defaultBufferSize)
    ///   - fftWindowSize: FFT window size (must be power of 2, starting from 8, defaults to Constants.defaultFFTWindowSize)
    ///   - fftBandQuantity: Number of FFT bands to display (defaults to appropriate value for window size to avoid mirroring)
    func startMonitoring(bufferSize: Int = Constants.defaultBufferSize, fftWindowSize: Int = Constants.defaultFFTWindowSize, fftBandQuantity: Int? = nil) async throws {
        // Validate buffer size is a power of 2
        guard bufferSize > 0 && (bufferSize & (bufferSize - 1)) == 0 else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        // Validate FFT window size is a power of 2 and at least 8
        guard fftWindowSize >= 8 && (fftWindowSize & (fftWindowSize - 1)) == 0 else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        self.bufferSize = bufferSize
        
        // If band quantity is provided, calculate window size from it (4x relationship for better resolution)
        // Otherwise, use the provided window size and calculate band quantity from it
        if let requestedBandQuantity = fftBandQuantity {
            // Calculate window size from band quantity (4x for better frequency resolution)
            self.fftWindowSize = Constants.calculateFFTWindowSize(for: requestedBandQuantity)
            self.fftBandQuantity = requestedBandQuantity
        } else {
            // Use provided window size and calculate appropriate band quantity
            self.fftWindowSize = fftWindowSize
            self.fftBandQuantity = Constants.calculateAppropriateFFTBandQuantity(for: fftWindowSize, includeNyquist: false)
        }
        
        // Initialize magnitudes array with correct size
        await MainActor.run {
            fftMagnitudes = [Float](repeating: 0, count: self.fftBandQuantity)
        }
        print("🚀 [AudioUnit] startMonitoring() called")
        guard !isMonitoring else {
            print("⚠️ [AudioUnit] Already monitoring, returning")
            return
        }
        
        // Request microphone permission
        print("🎤 [AudioUnit] Requesting microphone permission...")
        let permissionGranted = await requestMicrophonePermission()
        print("🎤 [AudioUnit] Permission granted: \(permissionGranted)")
        guard permissionGranted else {
            print("❌ [AudioUnit] Microphone permission denied")
            throw AudioVisualizerError.microphonePermissionDenied
        }
        
        // Configure audio session - CRITICAL for Mac Catalyst
        #if targetEnvironment(macCatalyst) || os(macOS)
        print("🎤 [AudioUnit] Configuring audio session...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set category BEFORE activating
            print("🎤 [AudioUnit] Setting category to .playAndRecord")
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            
            // Activate with options to ensure it takes effect
            print("🎤 [AudioUnit] Activating audio session...")
            try audioSession.setActive(true, options: [])
            print("✅ [AudioUnit] Audio session activated")
            
            // Log audio session info
            print("📊 [AudioUnit] Audio Session Info:")
            print("   Category: \(audioSession.category.rawValue)")
            print("   Mode: \(audioSession.mode.rawValue)")
            print("   Sample Rate: \(audioSession.sampleRate) Hz")
            print("   Input Available: \(audioSession.isInputAvailable)")
            print("   Input Gain: \(audioSession.inputGain)")
            
            // Check available inputs
            if let inputs = audioSession.availableInputs {
                print("📊 [AudioUnit] Available Inputs: \(inputs.count)")
                for (index, input) in inputs.enumerated() {
                    print("   Input \(index): \(input.portName) (type: \(input.portType.rawValue))")
                }
            } else {
                print("⚠️ [AudioUnit] No available inputs reported by AVAudioSession")
            }
            
            // Verify audio session is active
            guard audioSession.isOtherAudioPlaying == false || audioSession.category == .playAndRecord else {
                print("❌ [AudioUnit] Audio session validation failed")
                throw AudioVisualizerError.invalidAudioFormat
            }
            
            // Small delay to ensure audio session is fully initialized
            print("⏳ [AudioUnit] Waiting 100ms for audio session to initialize...")
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            print("✅ [AudioUnit] Audio session ready")
        } catch {
            print("❌ [AudioUnit] Audio session setup failed: \(error)")
            throw AudioVisualizerError.invalidAudioFormat
        }
        #endif
        
        // Safety check: Ensure band quantity doesn't exceed the maximum unique bins (N/2+1) to avoid mirroring
        // With the new 4x relationship (windowSize = 4 * bandQuantity), this should never trigger,
        // but we keep it as a safety measure in case window size is manually set too small
        let maxUniqueBands = self.fftWindowSize / 2 + 1
        if self.fftBandQuantity > maxUniqueBands {
            print("⚠️ [AudioUnit] Band quantity \(self.fftBandQuantity) exceeds maximum unique bins \(maxUniqueBands) for window size \(self.fftWindowSize). Limiting to \(maxUniqueBands) to avoid mirroring.")
            self.fftBandQuantity = maxUniqueBands
        }
        
        // Destroy old FFT setup if it exists
        if let oldSetup = fftSetup {
            vDSP_DFT_DestroySetup(oldSetup)
            fftSetup = nil
        }
        
        // Create DFT setup following the tutorial approach
        // vDSP_DFT_zrop_CreateSetup creates a setup for real-to-complex Discrete Fourier Transform
        fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftWindowSize), vDSP_DFT_Direction.FORWARD)
        
        guard fftSetup != nil else {
            print("❌ [AudioUnit] Failed to create DFT setup with window size: \(fftWindowSize), band quantity: \(fftBandQuantity)")
            throw AudioVisualizerError.fftSetupFailed
        }
        
        #if VERBOSE_FFT_DEBUG
        print("✅ [AudioUnit] Created FFT setup - buffer size: \(bufferSize), FFT window size: \(fftWindowSize), band quantity: \(fftBandQuantity)")
        #endif
        
        // Set up AudioUnit with proper cleanup on error
        do {
            print("🔧 [AudioUnit] Setting up AudioUnit...")
            try setupAudioUnit()
            print("✅ [AudioUnit] AudioUnit setup complete")
            
            // Start AudioUnit
            print("▶️ [AudioUnit] Starting AudioUnit...")
            let status = AudioOutputUnitStart(audioUnit!)
            if status == noErr {
                print("✅ [AudioUnit] AudioUnit started successfully")
                isMonitoring = true
            } else {
                print("❌ [AudioUnit] Failed to start AudioUnit (status: \(status))")
                // Clean up FFT setup before throwing
                if let setup = fftSetup {
                    vDSP_DFT_DestroySetup(setup)
                    fftSetup = nil
                }
                throw AudioVisualizerError.invalidAudioFormat
            }
        } catch let error {
            // Clean up FFT setup if setupAudioUnit() or AudioOutputUnitStart() failed
            if let setup = fftSetup {
                vDSP_DFT_DestroySetup(setup)
                fftSetup = nil
            }
            throw error
        }
    }
    
    /// Stop monitoring audio input
    func stopMonitoring() async {
        guard isMonitoring else { return }
        
        if let audioUnit = audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
        }
        
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            self.fftSetup = nil
        }
        
        bufferLock.lock()
        sampleBuffer.removeAll()
        bufferLock.unlock()
        
        // Reset magnitudes and samples on MainActor
        await MainActor.run {
            fftMagnitudes = [Float](repeating: 0, count: fftBandQuantity)
            rawAudioSamples = []
        }
        isMonitoring = false
    }
    
    /// Change the buffer size, stopping and restarting monitoring if needed
    /// - Parameter newBufferSize: New audio buffer size (must be power of 2)
    func changeBufferSize(_ newBufferSize: Int) async throws {
        // Validate buffer size is a power of 2
        guard newBufferSize > 0 && (newBufferSize & (newBufferSize - 1)) == 0 else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        let wasMonitoring = isMonitoring
        let currentWindowSize = fftWindowSize
        let currentBandQuantity = fftBandQuantity
        
        // Stop monitoring if it's running
        if wasMonitoring {
            await stopMonitoring()
        }
        
        // Restart monitoring if it was running
        if wasMonitoring {
            try await startMonitoring(bufferSize: newBufferSize, fftWindowSize: currentWindowSize, fftBandQuantity: currentBandQuantity)
        } else {
            self.bufferSize = newBufferSize
        }
    }
    
    /// Change the FFT band quantity, stopping and restarting monitoring if needed
    /// Window size will be automatically calculated as 4x the band quantity for better frequency resolution
    /// - Parameter newBandQuantity: New number of FFT bands to display
    func changeFFTBandQuantity(_ newBandQuantity: Int) async throws {
        guard newBandQuantity > 0 else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        let wasMonitoring = isMonitoring
        let currentBufferSize = bufferSize
        
        // Stop monitoring if it's running
        if wasMonitoring {
            await stopMonitoring()
        }
        
        // Restart monitoring if it was running
        // Pass band quantity only - window size will be calculated automatically (4x relationship)
        if wasMonitoring {
            try await startMonitoring(bufferSize: currentBufferSize, fftWindowSize: Constants.defaultFFTWindowSize, fftBandQuantity: newBandQuantity)
        } else {
            // Calculate window size from band quantity and update both
            self.fftBandQuantity = newBandQuantity
            self.fftWindowSize = Constants.calculateFFTWindowSize(for: newBandQuantity)
            await MainActor.run {
                fftMagnitudes = [Float](repeating: 0, count: newBandQuantity)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Log all available input devices for debugging
    private func logAvailableInputDevices() {
        #if targetEnvironment(macCatalyst) || os(macOS)
        print("🔍 [AudioUnit] Scanning for available input devices...")
        
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size of device list
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            print("❌ [AudioUnit] Failed to get device list size (status: \(status))")
            return
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        print("📊 [AudioUnit] Found \(deviceCount) total audio devices")
        
        // Get device list (AudioDeviceID is UInt32)
        var deviceIDs = [UInt32](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("❌ [AudioUnit] Failed to get device list (status: \(status))")
            return
        }
        
        // Check each device for input capability
        var inputDeviceCount = 0
        for deviceID in deviceIDs {
            if deviceHasInput(deviceID: deviceID) {
                inputDeviceCount += 1
                logDeviceInfo(deviceID: deviceID, label: "Input Device #\(inputDeviceCount)")
            }
        }
        
        print("📊 [AudioUnit] Found \(inputDeviceCount) input-capable devices")
        #endif
    }
    
    /// Check if a device has input capability
    #if targetEnvironment(macCatalyst) || os(macOS)
    private func deviceHasInput(deviceID: UInt32) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        return status == noErr && propertySize > 0
    }
    
    /// Log detailed information about a specific device
    private func logDeviceInfo(deviceID: UInt32, label: String) {
        print("📱 [AudioUnit] \(label):")
        print("   Device ID: \(deviceID)")
        
        // Get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString
        
        var status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceName
        )
        
        if status == noErr {
            print("   Name: \(deviceName)")
        } else {
            // Try alternative method for device name
            propertyAddress.mSelector = kAudioObjectPropertyName
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &propertySize,
                &deviceName
            )
            if status == noErr {
                print("   Name: \(deviceName)")
            } else {
                print("   Name: (unavailable, status: \(status))")
            }
        }
        
        // Get device UID
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
        var deviceUID: CFString = "" as CFString
        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceUID
        )
        if status == noErr {
            print("   UID: \(deviceUID)")
        }
        
        // Get sample rate
        propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
        propertyAddress.mScope = kAudioObjectPropertyScopeInput
        var sampleRate: Float64 = 0
        propertySize = UInt32(MemoryLayout<Float64>.size)
        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        if status == noErr {
            print("   Sample Rate: \(sampleRate) Hz")
        }
        
        // Check if it's the default input
        var defaultInputID: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultInputID
        )
        if status == noErr && defaultInputID == deviceID {
            print("   ⭐ This is the DEFAULT INPUT device")
        }
    }
    #else
    private func deviceHasInput(deviceID: UInt32) -> Bool {
        return false
    }
    private func logDeviceInfo(deviceID: UInt32, label: String) {
        // No-op on iOS
    }
    #endif
    
    /// Set up the AudioUnit with RemoteIO (iOS) or HALOutput (macOS/Mac Catalyst)
    private func setupAudioUnit() throws {
        // Use RemoteIO on iOS, HALOutput on macOS/Mac Catalyst
        #if targetEnvironment(macCatalyst) || os(macOS)
        let subType = kAudioUnitSubType_HALOutput
        #else
        let subType = kAudioUnitSubType_RemoteIO
        #endif
        
        // Describe the audio component
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // Find the component
        guard let audioComponent = AudioComponentFindNext(nil, &componentDescription) else {
            throw AudioVisualizerError.fftSetupFailed
        }
        
        // Create instance
        var audioUnitInstance: AudioUnit?
        let status = AudioComponentInstanceNew(audioComponent, &audioUnitInstance)
        guard status == noErr, let unit = audioUnitInstance else {
            throw AudioVisualizerError.fftSetupFailed
        }
        
        self.audioUnit = unit
        
        #if targetEnvironment(macCatalyst) || os(macOS)
        // For HALOutput on macOS/Mac Catalyst, we need to set the input device
        // First, list all available input devices for debugging
        logAvailableInputDevices()
        
        // Get the default input device (AudioDeviceID is UInt32)
        var inputDeviceID: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        print("🔍 [AudioUnit] Attempting to get default input device...")
        var status2 = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &inputDeviceID
        )
        
        if status2 == noErr && inputDeviceID != 0 {
            print("✅ [AudioUnit] Got default input device ID: \(inputDeviceID)")
            logDeviceInfo(deviceID: inputDeviceID, label: "Default Input Device")
        } else {
            print("⚠️ [AudioUnit] Could not get default input device (status: \(status2)), deviceID: \(inputDeviceID)")
        }
        
        // Only set the device if we got a valid device ID
        if inputDeviceID != 0 {
            print("🔧 [AudioUnit] Setting AudioUnit current device to input device ID: \(inputDeviceID)")
            // Set the current device to the input device
            status2 = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &inputDeviceID,
                UInt32(MemoryLayout<UInt32>.size)
            )
            if status2 == noErr {
                print("✅ [AudioUnit] Successfully set input device")
            } else {
                print("❌ [AudioUnit] Failed to set input device (status: \(status2))")
            }
        } else {
            print("⚠️ [AudioUnit] No valid input device ID, continuing with default device")
        }
        
        // Enable input (bus 1) and disable output (bus 0) for HALOutput
        var enableInput: UInt32 = 1
        var enableOutput: UInt32 = 0
        
        status2 = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // bus 1 = input
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        status2 = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // bus 0 = output
            &enableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        #else
        // For RemoteIO on iOS
        var enableInput: UInt32 = 1
        var enableOutput: UInt32 = 0
        
        var status2 = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // bus 1 = input
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        status2 = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // bus 0 = output
            &enableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        #endif
        
        // First, try to get the actual hardware format to see what it provides
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var hardwareFormat = AudioStreamBasicDescription()
        
        var status3 = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &hardwareFormat,
            &propertySize
        )
        
        if status3 == noErr {
            print("📊 [AudioUnit] Hardware input format:")
            print("   Sample Rate: \(hardwareFormat.mSampleRate) Hz")
            print("   Channels: \(Int(hardwareFormat.mChannelsPerFrame))")
            print("   Format Flags: \(hardwareFormat.mFormatFlags)")
            let isInterleaved = (hardwareFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            print("   Interleaved: \(isInterleaved ? "Yes" : "No")")
        } else {
            print("⚠️ [AudioUnit] Could not get hardware format (status: \(status3)), will use requested format")
        }
        
        // Request stereo format (2 channels) so we get both left and right
        // We'll convert to mono in processAudioBuffer by averaging channels
        // This ensures we capture audio from both channels even if panned
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2, // Request stereo to get both channels
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        self.audioFormat = audioFormat
        
        status2 = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1, // bus 1 = input
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        if status2 == noErr {
            print("✅ [AudioUnit] Set format to stereo (2 channels) - will convert to mono in processing")
        } else {
            print("⚠️ [AudioUnit] Failed to set stereo format (status: \(status2)), trying mono...")
            // Fallback to mono if stereo isn't supported
            audioFormat.mChannelsPerFrame = 1
            status2 = AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &audioFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )
            guard status2 == noErr else {
                throw AudioVisualizerError.invalidAudioFormat
            }
            print("✅ [AudioUnit] Set format to mono (1 channel)")
        }
        
        // Set render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        status2 = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
        }
        
        // Initialize the audio unit
        status2 = AudioUnitInitialize(unit)
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
        }
    }
    
    /// Render callback - processes audio buffers (called from C callback)
    func processAudioBuffer(_ ioData: UnsafeMutablePointer<AudioBufferList>, _ inNumberFrames: UInt32) {
        processCallbackCount += 1
        
        // Log first few callbacks to verify it's being called
        if processCallbackCount <= 5 {
            print("🎵 [AudioUnit] Process callback #\(processCallbackCount) - \(inNumberFrames) frames")
        }
        
        let bufferListPtr = UnsafeMutableAudioBufferListPointer(ioData)
        guard let audioBufferList = bufferListPtr.first else {
            if processCallbackCount <= 5 {
                print("❌ [AudioUnit] No audio buffer list in callback")
            }
            return
        }
        
        // Get audio data
        let channelData = audioBufferList.mData?.assumingMemoryBound(to: Float.self)
        guard let channelData = channelData else {
            if processCallbackCount <= 5 {
                print("❌ [AudioUnit] No channel data in buffer")
            }
            return
        }
        
        // Handle mono or stereo audio
        // For non-interleaved stereo, we have multiple buffers (one per channel)
        // For interleaved stereo, we have one buffer with 2 channels
        let numBuffers = bufferListPtr.count
        let channelsPerBuffer = Int(audioBufferList.mNumberChannels)
        
        if processCallbackCount <= 5 {
            print("📊 [AudioUnit] Buffer info: \(numBuffers) buffers, \(channelsPerBuffer) channels per buffer")
        }
        
        let samples: [Float]
        if numBuffers > 1 && bufferListPtr[1].mData != nil {
            // Non-interleaved stereo: separate buffers for left and right
            let leftChannel = Array(UnsafeBufferPointer(start: channelData, count: Int(inNumberFrames)))
            let rightChannelData = bufferListPtr[1].mData?.assumingMemoryBound(to: Float.self)
            
            if let rightChannelData = rightChannelData {
                let rightChannel = Array(UnsafeBufferPointer(start: rightChannelData, count: Int(inNumberFrames)))
                
                // Debug: check if we're actually getting different data in left vs right
                if processCallbackCount <= 5 {
                    let leftMax = leftChannel.map { abs($0) }.max() ?? 0
                    let rightMax = rightChannel.map { abs($0) }.max() ?? 0
                    print("📊 [AudioUnit] Left channel max: \(leftMax), Right channel max: \(rightMax)")
                }
                
                // Average left and right to create mono
                samples = zip(leftChannel, rightChannel).map { ($0 + $1) / 2.0 }
                
                if processCallbackCount <= 5 {
                    print("📊 [AudioUnit] Converted non-interleaved stereo to mono: \(samples.count) samples")
                }
            } else {
                if processCallbackCount <= 5 {
                    print("⚠️ [AudioUnit] Right channel data is nil, using left only")
                }
                // Fallback to mono (left channel only)
                samples = leftChannel
            }
        } else if channelsPerBuffer == 2 {
            // Interleaved stereo: samples alternate L, R, L, R, ...
            let interleavedCount = Int(inNumberFrames) * 2
            let interleavedSamples = Array(UnsafeBufferPointer(start: channelData, count: interleavedCount))
            // Extract and average left and right channels
            var monoResult: [Float] = []
            monoResult.reserveCapacity(Int(inNumberFrames))
            for i in 0..<Int(inNumberFrames) {
                let left = interleavedSamples[i * 2]
                let right = interleavedSamples[i * 2 + 1]
                monoResult.append((left + right) / 2.0)
            }
            samples = monoResult
            
            if processCallbackCount <= 5 {
                print("📊 [AudioUnit] Converted interleaved stereo to mono: \(samples.count) samples")
            }
        } else {
            // Mono: just copy the samples
            samples = Array(UnsafeBufferPointer(start: channelData, count: Int(inNumberFrames)))
            if processCallbackCount <= 5 {
                print("📊 [AudioUnit] Mono audio: \(samples.count) samples")
            }
        }
        
        // Check if we're getting actual audio data (not just silence)
        let maxSample = samples.max() ?? 0
        let minSample = samples.min() ?? 0
        if processCallbackCount <= 5 {
            print("📊 [AudioUnit] Sample range: \(minSample) to \(maxSample)")
        }
        
        bufferLock.lock()
        sampleBuffer.append(contentsOf: samples)
        let currentBufferSize = sampleBuffer.count
        
        // Process when we have enough samples
        // Process when we have enough samples for the FFT window
        // We need at least fftWindowSize samples to perform the FFT
        if sampleBuffer.count >= fftWindowSize {
            // Take fftWindowSize samples for FFT processing
            let audioData = Array(sampleBuffer.prefix(fftWindowSize))
            // Remove bufferSize samples to maintain rolling window (or all if less)
            let samplesToRemove = min(bufferSize, sampleBuffer.count)
            sampleBuffer.removeFirst(samplesToRemove)
            bufferLock.unlock()
            
            if processCallbackCount <= 10 {
                #if VERBOSE_FFT_DEBUG
                print("✅ [AudioUnit] Processing FFT with \(audioData.count) samples (buffer was \(currentBufferSize))")
                #endif
            }
            
            // Perform FFT asynchronously and update on main actor
            Task { @MainActor in
                do {
                    let magnitudes = await self.performFFT(data: audioData)
                    if magnitudes.isEmpty {
                        print("⚠️ [AudioUnit] FFT returned empty magnitudes array")
                    } else {
                        self.fftMagnitudes = magnitudes
                        
                        if processCallbackCount <= 10 {
                            let maxMagnitude = magnitudes.max() ?? 0
                            #if VERBOSE_FFT_DEBUG
                            print("📈 [AudioUnit] FFT complete - max magnitude: \(maxMagnitude)")
                            #endif
                        }
                    }
                } catch {
                    print("❌ [AudioUnit] FFT error: \(error)")
                }
                
                // Store raw audio samples for time-domain visualization
                // Keep a rolling window of recent samples
                self.rawAudioSamples.append(contentsOf: audioData)
                if self.rawAudioSamples.count > self.maxRawSamples {
                    self.rawAudioSamples.removeFirst(self.rawAudioSamples.count - self.maxRawSamples)
                }
            }
        } else {
            bufferLock.unlock()
        }
    }
    
    /// Request microphone permission
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Save array to text file for debugging
    private func saveArrayToFile(_ array: [Float], filename: String, sampleRate: Float, windowSize: Int) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        var content = "Index\tFrequency(Hz)\tMagnitude\n"
        let frequencyResolution = sampleRate / Float(windowSize)
        
        for (index, value) in array.enumerated() {
            let freq = Float(index) * frequencyResolution
            content += "\(index)\t\(String(format: "%.2f", freq))\t\(String(format: "%.6f", value))\n"
        }
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            #if VERBOSE_FFT_DEBUG
            print("💾 [FFT Debug] Saved \(array.count) values to \(filename) at \(fileURL.path)")
            #endif
        } catch {
            #if VERBOSE_FFT_DEBUG
            print("❌ [FFT Debug] Failed to save \(filename): \(error)")
            #endif
        }
    }
    
    /// Perform Fast Fourier Transform on audio data
    /// Uses vDSP_DFT_Execute following the tutorial approach
    private func performFFT(data: [Float]) async -> [Float] {
        guard data.count >= fftWindowSize else {
            print("⚠️ [FFT] Not enough data: \(data.count) < \(fftWindowSize)")
            return [Float](repeating: 0, count: fftBandQuantity)
        }
        
        guard let fftSetup = fftSetup else {
            print("⚠️ [FFT] FFT setup is nil")
            return [Float](repeating: 0, count: fftBandQuantity)
        }
        
        // Prepare input data (use first fftWindowSize samples)
        var inputData = Array(data.prefix(fftWindowSize))
        
        #if VERBOSE_FFT_DEBUG
        if processCallbackCount <= 3 {
            print("🔍 [FFT Debug] Input data size: \(inputData.count), fftWindowSize: \(fftWindowSize)")
            print("🔍 [FFT Debug] FFT setup was created with window size: \(fftWindowSize)")
            print("🔍 [FFT Debug] Input data range: min=\(inputData.min() ?? 0), max=\(inputData.max() ?? 0), RMS=\(sqrt(inputData.map { $0 * $0 }.reduce(0, +) / Float(inputData.count)))")
        }
        #endif
        
        // Apply windowing function to reduce spectral leakage
        // Using Hann window for better frequency resolution
        var window = [Float](repeating: 0, count: fftWindowSize)
        vDSP_hann_window(&window, vDSP_Length(fftWindowSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(inputData, 1, window, 1, &inputData, 1, vDSP_Length(fftWindowSize))
        
        // Following Apple's vDSP documentation for real-to-complex DFT:
        // vDSP_DFT_Execute outputs the full N-point complex result (N real + N imaginary values)
        // For a real input signal, the output has conjugate symmetry:
        //   - Bin 0: DC component (real only, imaginary = 0)
        //   - Bins 1 to N/2-1: Complex frequency components
        //   - Bin N/2: Nyquist frequency (real only, imaginary = 0)
        //   - Bins N/2+1 to N-1: Complex conjugates of bins N/2-1 to 1 (imaginary parts negated)
        // 
        // IMPORTANT: Bins N/2+1 to N-1 are NOT zeros - they contain the complex conjugates!
        // The magnitudes of bins k and N-k are the same, but the phases are opposite.
        // 
        // To avoid mirroring, we extract only the unique bins: 0 to N/2 (inclusive) = N/2+1 bins
        // However, if includeNyquist is false, we use N/2 bins (excluding Nyquist at bin N/2)
        // CRITICAL: We must extract bins 0 to N/2, NOT 0 to N/2-1, to avoid including mirrored data
        let maxUniqueBins = fftWindowSize / 2 + 1  // N/2+1 includes DC to Nyquist
        // CRITICAL FIX: Always extract ALL unique bins (N/2), then limit to fftBandQuantity later
        // Previously we were limiting here, which caused us to lose half the frequency data
        let fftOutputSize = fftWindowSize / 2  // Always extract all unique bins (excluding Nyquist)
        
        var realOut = [Float](repeating: 0, count: fftWindowSize)
        var imagOut = [Float](repeating: 0, count: fftWindowSize)
        var inputImag = [Float](repeating: 0, count: fftWindowSize) // Zero for real input
        var magnitudes = [Float](repeating: 0, count: fftOutputSize)
        
        #if VERBOSE_FFT_DEBUG
        if processCallbackCount <= 3 {
            print("🔍 [FFT Debug] Output arrays: realOut.count=\(realOut.count), imagOut.count=\(imagOut.count), inputImag.count=\(inputImag.count)")
            print("🔍 [FFT Debug] Expected output size: \(fftWindowSize), fftOutputSize (extracted): \(fftOutputSize)")
        }
        #endif
        
        // Execute DFT - vDSP_DFT_Execute requires both real and imaginary inputs and outputs
        // Even though input is real, we must provide imaginary input array (all zeros)
        inputData.withUnsafeBufferPointer { inputPtr in
            inputImag.withUnsafeBufferPointer { inputImagPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        vDSP_DFT_Execute(
                            fftSetup,
                            inputPtr.baseAddress!,
                            inputImagPtr.baseAddress!,
                            realOutPtr.baseAddress!,
                            imagOutPtr.baseAddress!
                        )
                        
                        // Debug: Check raw DFT output before computing magnitudes
                        #if VERBOSE_FFT_DEBUG
                        if processCallbackCount <= 3 {
                            print("🔍 [FFT Debug] Raw DFT output (first 10 real/imag pairs):")
                            for i in 0..<min(10, fftWindowSize) {
                                print("   bin[\(i)]: real=\(String(format: "%.4f", realOutPtr[i])), imag=\(String(format: "%.4f", imagOutPtr[i]))")
                            }
                            print("🔍 [FFT Debug] Raw DFT output (last 10 real/imag pairs):")
                            for i in max(0, fftWindowSize - 10)..<fftWindowSize {
                                print("   bin[\(i)]: real=\(String(format: "%.4f", realOutPtr[i])), imag=\(String(format: "%.4f", imagOutPtr[i]))")
                            }
                        }
                        #endif
                        
                        // Create split complex structure for magnitude calculation
                        // Note: We must keep realOut and imagOut in scope during this operation
                        var complex = DSPSplitComplex(
                            realp: realOutPtr.baseAddress!,
                            imagp: imagOutPtr.baseAddress!
                        )
                        
                        // Compute magnitudes for all N bins to verify mirroring
                        var allMagnitudes = [Float](repeating: 0, count: fftWindowSize)
                        allMagnitudes.withUnsafeMutableBufferPointer { allMagPtr in
                            vDSP_zvabs(&complex, 1, allMagPtr.baseAddress!, 1, vDSP_Length(fftWindowSize))
                            
                            #if VERBOSE_FFT_DEBUG
                            if processCallbackCount <= 3 {
                                print("🔍 [FFT Debug] Computed magnitudes for \(fftWindowSize) bins")
                                print("🔍 [FFT Debug] First 5 magnitudes: \(Array(allMagPtr.prefix(5)))")
                                print("🔍 [FFT Debug] Last 5 magnitudes: \(Array(UnsafeBufferPointer(start: allMagPtr.baseAddress!.advanced(by: fftWindowSize - 5), count: 5)))")
                            }
                            #endif
                            
                            // Debug: Save ALL magnitudes from the full DFT output to file
                            #if VERBOSE_FFT_DEBUG
                            if processCallbackCount <= 3 {
                                let allMagArray = Array(UnsafeBufferPointer(start: allMagPtr.baseAddress!, count: fftWindowSize))
                                saveArrayToFile(allMagArray, filename: "fft_debug_allMagnitudes_\(processCallbackCount).txt", sampleRate: 44100.0, windowSize: fftWindowSize)
                                
                                // Check for mirroring: compare bin k with bin N-k
                                // For real input, bins k and N-k should have the same magnitude (conjugate symmetry)
                                print("🔍 [FFT Debug] Mirroring check (comparing bin k with bin N-k):")
                                var mirroringIssues = 0
                                for k in 1..<min(50, fftWindowSize / 2) {
                                    let mirrorIdx = fftWindowSize - k
                                    let diff = abs(allMagPtr[k] - allMagPtr[mirrorIdx])
                                    if diff > 0.001 {  // Only print if there's a significant difference
                                        print("   ⚠️ bin[\(k)]=\(String(format: "%.4f", allMagPtr[k])) vs bin[\(mirrorIdx)]=\(String(format: "%.4f", allMagPtr[mirrorIdx])): diff=\(String(format: "%.4f", diff))")
                                        mirroringIssues += 1
                                    }
                                }
                                if mirroringIssues == 0 {
                                    print("   ✅ Mirroring check passed: bins k and N-k have matching magnitudes (as expected for real input)")
                                }
                            }
                            #else
                            // Save files even when verbose logging is disabled (less intrusive than console spam)
                            if processCallbackCount <= 3 {
                                let allMagArray = Array(UnsafeBufferPointer(start: allMagPtr.baseAddress!, count: fftWindowSize))
                                saveArrayToFile(allMagArray, filename: "fft_debug_allMagnitudes_\(processCallbackCount).txt", sampleRate: 44100.0, windowSize: fftWindowSize)
                            }
                            #endif
                            
                            // Extract only the first N/2 bins (DC to just before Nyquist) - these are the unique bins
                            // CRITICAL DISCOVERY: For a real input, the DFT output has conjugate symmetry:
                            //   - Bins 0 to N/2-1: Unique frequency components
                            //   - Bin N/2: Nyquist (real only)
                            //   - Bins N/2+1 to N-1: Complex conjugates of bins N/2-1 to 1 (same magnitude, negated imaginary)
                            // The test revealed that bins 250-255 (for N=512) are complex conjugates of bins 6-1
                            // We must extract ONLY bins 0 to N/2-1 to avoid including mirrored data
                            // Copy directly from allMagnitudes to magnitudes array (captured from outer scope)
                            magnitudes.withUnsafeMutableBufferPointer { magnitudesPtr in
                                for i in 0..<fftOutputSize {
                                    // Ensure we don't access beyond valid range
                                    // CRITICAL: fftOutputSize is N/2, so we extract bins 0 to N/2-1 (not including Nyquist)
                                    // This ensures we never include bins >= N/2 which would be mirrored data
                                    guard i < allMagPtr.count && i < magnitudesPtr.count else { break }
                                    // Double-check we're not extracting mirrored bins
                                    guard i < fftWindowSize / 2 else {
                                        #if VERBOSE_FFT_DEBUG
                                        print("⚠️ [FFT] Attempted to extract bin \(i) which is >= N/2 (\(fftWindowSize/2)), skipping to avoid mirroring")
                                        #endif
                                        break
                                    }
                                    magnitudesPtr[i] = allMagPtr[i]
                                }
                                
                                // Debug: Save the extracted magnitudes array to file
                                if processCallbackCount <= 3 {
                                    let extractedArray = Array(UnsafeBufferPointer(start: magnitudesPtr.baseAddress!, count: fftOutputSize))
                                    saveArrayToFile(extractedArray, filename: "fft_debug_extractedMagnitudes_\(processCallbackCount).txt", sampleRate: 44100.0, windowSize: fftWindowSize)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // The DFT outputs the full N-point transform, but we only computed magnitudes for the first N/2 bins
        // (DC to just before Nyquist) to avoid mirroring - the second half is a mirror for real input
        let fftMagnitudesFull = magnitudes
        
        // Debug: Save fftMagnitudesFull before extraction to file
        if processCallbackCount <= 3 {
            saveArrayToFile(fftMagnitudesFull, filename: "fft_debug_fftMagnitudesFull_\(processCallbackCount).txt", sampleRate: 44100.0, windowSize: fftWindowSize)
        }
        
        // Extract the desired number of bands (take first fftBandQuantity bins)
        // DFT outputs bins in order from DC (0 Hz) to just before Nyquist
        let bandsToUse = min(fftBandQuantity, fftMagnitudesFull.count)
        var resultMagnitudes = Array(fftMagnitudesFull.prefix(bandsToUse))
        
        // Debug: Save resultMagnitudes after extraction to file
        if processCallbackCount <= 3 {
            saveArrayToFile(resultMagnitudes, filename: "fft_debug_resultMagnitudes_\(processCallbackCount).txt", sampleRate: 44100.0, windowSize: fftWindowSize)
        }
        
        // Debug: Log detailed information to verify FFT output and extraction
        #if VERBOSE_FFT_DEBUG
        if processCallbackCount <= 10 {
            // Input data statistics
            let inputMin = inputData.min() ?? 0
            let inputMax = inputData.max() ?? 0
            let inputRMS = sqrt(inputData.map { $0 * $0 }.reduce(0, +) / Float(inputData.count))
            
            // Frequency bin mapping (assuming 44.1kHz sample rate)
            let sampleRate: Float = 44100.0
            let frequencyResolution = sampleRate / Float(fftWindowSize)
            
            // Show first 20 and last 20 bins with their frequencies
            var firstBinsInfo: [String] = []
            var lastBinsInfo: [String] = []
            for i in 0..<min(20, fftMagnitudesFull.count) {
                let freq = Float(i) * frequencyResolution
                firstBinsInfo.append("bin[\(i)]=\(String(format: "%.1f", freq))Hz:\(String(format: "%.3f", fftMagnitudesFull[i]))")
            }
            for i in max(0, fftMagnitudesFull.count - 20)..<fftMagnitudesFull.count {
                let freq = Float(i) * frequencyResolution
                lastBinsInfo.append("bin[\(i)]=\(String(format: "%.1f", freq))Hz:\(String(format: "%.3f", fftMagnitudesFull[i]))")
            }
            
            // Magnitude distribution
            let firstQuarter = resultMagnitudes.prefix(resultMagnitudes.count / 4)
            let secondQuarter = resultMagnitudes.dropFirst(resultMagnitudes.count / 4).prefix(resultMagnitudes.count / 4)
            let thirdQuarter = resultMagnitudes.dropFirst(resultMagnitudes.count / 2).prefix(resultMagnitudes.count / 4)
            let lastQuarter = resultMagnitudes.suffix(resultMagnitudes.count / 4)
            
            // Find bins with significant energy (> 0.1)
            let significantBins = fftMagnitudesFull.enumerated().filter { $0.element > 0.1 }
            var significantInfo: [String] = []
            for (index, magnitude) in significantBins.prefix(20) {
                let freq = Float(index) * frequencyResolution
                significantInfo.append("bin[\(index)]=\(String(format: "%.1f", freq))Hz:\(String(format: "%.3f", magnitude))")
            }
            
            print("🔍 [FFT Debug] ========== FFT Analysis #\(processCallbackCount) ==========")
            print("   Input: \(fftWindowSize) samples, min=\(String(format: "%.4f", inputMin)), max=\(String(format: "%.4f", inputMax)), RMS=\(String(format: "%.4f", inputRMS))")
            print("   Sample rate: \(sampleRate)Hz, Frequency resolution: \(String(format: "%.2f", frequencyResolution))Hz/bin")
            print("   FFT output: \(fftMagnitudesFull.count) bins (DC to just before Nyquist), Using: \(bandsToUse) bands")
            print("   First 20 bins (low freq):")
            for info in firstBinsInfo {
                print("      \(info)")
            }
            print("   Last 20 bins (high freq):")
            for info in lastBinsInfo {
                print("      \(info)")
            }
            print("   Magnitude distribution by quarter:")
            print("      Q1 (lowest): max=\(String(format: "%.3f", firstQuarter.max() ?? 0)), mean=\(String(format: "%.3f", firstQuarter.reduce(0, +) / Float(max(1, firstQuarter.count))))")
            print("      Q2: max=\(String(format: "%.3f", secondQuarter.max() ?? 0)), mean=\(String(format: "%.3f", secondQuarter.reduce(0, +) / Float(max(1, secondQuarter.count))))")
            print("      Q3: max=\(String(format: "%.3f", thirdQuarter.max() ?? 0)), mean=\(String(format: "%.3f", thirdQuarter.reduce(0, +) / Float(max(1, thirdQuarter.count))))")
            print("      Q4 (highest): max=\(String(format: "%.3f", lastQuarter.max() ?? 0)), mean=\(String(format: "%.3f", lastQuarter.reduce(0, +) / Float(max(1, lastQuarter.count))))")
            if !significantInfo.isEmpty {
                print("   Bins with significant energy (>0.1):")
                for info in significantInfo {
                    print("      \(info)")
                }
            }
            print("🔍 [FFT Debug] =================================================")
        }
        #endif
        
        // Pad with zeros if we need more bands than available (shouldn't happen if calculation is correct)
        // But this ensures we always return the expected array size
        if resultMagnitudes.count < fftBandQuantity {
            resultMagnitudes.append(contentsOf: [Float](repeating: 0, count: fftBandQuantity - resultMagnitudes.count))
        }
        
        // Limit magnitudes to prevent distortion (following tutorial approach)
        let finalMagnitudes = resultMagnitudes.map { min($0, Constants.magnitudeLimit) }
        
        // Debug: Save final magnitudes after limiting to file
        if processCallbackCount <= 3 {
            saveArrayToFile(finalMagnitudes, filename: "fft_debug_finalMagnitudes_\(processCallbackCount).txt", sampleRate: 44100.0, windowSize: fftWindowSize)
        }
        
        return finalMagnitudes
    }
}

// MARK: - C Callback

/// Global counter for render callback invocations (C function can't use instance properties)
private var globalCallbackCount: Int = 0
private let callbackCountLock = NSLock()

/// C callback function for AudioUnit render
/// This must be a C function, not a Swift closure
private func renderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    callbackCountLock.lock()
    globalCallbackCount += 1
    let currentCount = globalCallbackCount
    callbackCountLock.unlock()
    
    // Log first few invocations
    if currentCount <= 3 {
        print("🔔 [AudioUnit] Render callback invoked #\(currentCount) - bus: \(inBusNumber), frames: \(inNumberFrames)")
        print("   ioData: \(ioData != nil ? "not nil" : "nil")")
    }
    
    // Get the monitor instance
    let monitor = Unmanaged<AudioUnitMonitor>.fromOpaque(inRefCon).takeUnretainedValue()
    
    // Get the audio unit
    guard let audioUnit = monitor.audioUnit else {
        if currentCount <= 3 {
            print("❌ [AudioUnit] audioUnit is nil in callback")
        }
        return noErr
    }
    
    // Allocate buffer for audio data
    // For HALOutput, ioData might be nil, so we always allocate our own buffer
    // We need to match the format we requested - stereo (2 channels, non-interleaved) requires 2 buffers
    // Allocate AudioBufferList with space for 2 buffers (variable-length array)
    let bufferListSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
    let bufferListMemory = calloc(1, bufferListSize)
    guard let bufferListMemory = bufferListMemory else {
        if currentCount <= 3 {
            print("❌ [AudioUnit] Failed to allocate buffer list memory")
        }
        return -1
    }
    
    let bufferListPtr = bufferListMemory.assumingMemoryBound(to: AudioBufferList.self)
    bufferListPtr.pointee.mNumberBuffers = 2  // Stereo requires 2 buffers for non-interleaved format
    
    // Allocate first buffer (left channel)
    let leftData = calloc(Int(inNumberFrames), MemoryLayout<Float>.size)
    guard let leftData = leftData else {
        if currentCount <= 3 {
            print("❌ [AudioUnit] Failed to allocate left channel buffer")
        }
        free(bufferListMemory)
        return -1
    }
    
    // Use UnsafeMutableAudioBufferListPointer helper to access buffers properly
    let bufferListHelper = UnsafeMutableAudioBufferListPointer(bufferListPtr)
    
    // Set up first buffer (left channel)
    bufferListHelper[0].mNumberChannels = 1
    bufferListHelper[0].mDataByteSize = inNumberFrames * UInt32(MemoryLayout<Float>.size)
    bufferListHelper[0].mData = leftData
    
    // Allocate second buffer (right channel)
    let rightData = calloc(Int(inNumberFrames), MemoryLayout<Float>.size)
    guard let rightData = rightData else {
        if currentCount <= 3 {
            print("❌ [AudioUnit] Failed to allocate right channel buffer")
        }
        free(leftData)
        free(bufferListMemory)
        return -1
    }
    
    // Set up second buffer (right channel)
    bufferListHelper[1].mNumberChannels = 1
    bufferListHelper[1].mDataByteSize = inNumberFrames * UInt32(MemoryLayout<Float>.size)
    bufferListHelper[1].mData = rightData
    
    defer {
        free(leftData)
        free(rightData)
        free(bufferListMemory)
    }
    
    // Render audio into the buffer from input bus 1
    // For HALOutput, we render from the input bus
    var status = AudioUnitRender(
        audioUnit,
        ioActionFlags,
        inTimeStamp,
        1, // input bus (bus 1 is input for RemoteIO/HALOutput)
        inNumberFrames,
        bufferListPtr
    )
    
    if currentCount <= 3 {
        print("🎤 [AudioUnit] AudioUnitRender status: \(status) (noErr=\(noErr))")
    }
    
    guard status == noErr else {
        if currentCount <= 10 {
            print("❌ [AudioUnit] AudioUnitRender failed with status: \(status)")
        }
        return status
    }
    
    // Process the audio buffer (ioData is nil for input callbacks, we use our allocated buffer)
    monitor.processAudioBuffer(bufferListPtr, inNumberFrames)
    
    return noErr
}

