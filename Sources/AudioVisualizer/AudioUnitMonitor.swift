import AVFoundation
import Accelerate
import Foundation
import AudioUnit
#if targetEnvironment(macCatalyst) || os(macOS)
import CoreAudio
#endif

/// AudioUnit-based monitor for reliable microphone access on Mac Catalyst
/// Uses RemoteIO AudioUnit for direct hardware access, bypassing AVAudioEngine issues
/// Note: C callbacks run on background threads, so we handle thread safety internally
final class AudioUnitMonitor {
    
    // MARK: - Properties
    
    /// Audio unit instance (needs to be accessible from C callback)
    var audioUnit: AudioUnit?
    
    /// FFT configuration buffer size
    private let bufferSize = 8192
    
    /// FFT configuration setup
    private var fftSetup: OpaquePointer?
    
    /// Store the FFT magnitude results (thread-safe access via MainActor)
    @MainActor private(set) var fftMagnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
    
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
    
    // MARK: - Public Methods
    
    /// Start monitoring audio input from the microphone
    func startMonitoring() async throws {
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
        
        // Create FFT setup
        fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            UInt(bufferSize),
            .FORWARD
        )
        
        guard fftSetup != nil else {
            throw AudioVisualizerError.fftSetupFailed
        }
        
        // Set up AudioUnit
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
            throw AudioVisualizerError.invalidAudioFormat
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
        
        // Reset magnitudes on MainActor
        await MainActor.run {
            fftMagnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
        }
        isMonitoring = false
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
        
        // Set audio format (44.1kHz, mono, 32-bit float)
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
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
        guard status2 == noErr else {
            throw AudioVisualizerError.invalidAudioFormat
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
        
        guard let audioBufferList = UnsafeMutableAudioBufferListPointer(ioData).first else {
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
        
        // Copy samples to our buffer
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(inNumberFrames)))
        
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
        if sampleBuffer.count >= bufferSize {
            let audioData = Array(sampleBuffer.prefix(bufferSize))
            sampleBuffer.removeFirst(bufferSize)
            bufferLock.unlock()
            
            if processCallbackCount <= 10 {
                print("✅ [AudioUnit] Processing FFT with \(audioData.count) samples (buffer was \(currentBufferSize))")
            }
            
            // Perform FFT asynchronously and update on main actor
            Task { @MainActor in
                let magnitudes = await self.performFFT(data: audioData)
                self.fftMagnitudes = magnitudes
                
                if processCallbackCount <= 10 {
                    let maxMagnitude = magnitudes.max() ?? 0
                    print("📈 [AudioUnit] FFT complete - max magnitude: \(maxMagnitude)")
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
    var bufferList = AudioBufferList()
    bufferList.mNumberBuffers = 1
    bufferList.mBuffers.mNumberChannels = 1
    bufferList.mBuffers.mDataByteSize = inNumberFrames * UInt32(MemoryLayout<Float>.size)
    bufferList.mBuffers.mData = calloc(Int(inNumberFrames), MemoryLayout<Float>.size)
    
    guard bufferList.mBuffers.mData != nil else {
        if currentCount <= 3 {
            print("❌ [AudioUnit] Failed to allocate buffer")
        }
        return -1
    }
    
    defer {
        free(bufferList.mBuffers.mData)
    }
    
    // Render audio into the buffer from input bus 1
    // For HALOutput, we render from the input bus
    var status = AudioUnitRender(
        audioUnit,
        ioActionFlags,
        inTimeStamp,
        1, // input bus (bus 1 is input for RemoteIO/HALOutput)
        inNumberFrames,
        &bufferList
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
    monitor.processAudioBuffer(&bufferList, inNumberFrames)
    
    return noErr
}

