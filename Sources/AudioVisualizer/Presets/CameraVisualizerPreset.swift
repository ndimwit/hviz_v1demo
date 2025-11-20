import SwiftUI
import AVFoundation
import Charts
#if os(macOS)
import CoreMediaIO
#endif

/// Camera-based visualizer preset
/// Displays camera feed with LineChartPreset overlaid on top
public struct CameraVisualizerPreset: VisualizerPreset {
    public let id = "camera_visualizer"
    public let displayName = "Camera + Line Chart"
    
    private let lineChartPreset = LineChartPreset()
    
    @ViewBuilder
    public func makeView(
        magnitudes: [Float],
        rawAudioSamples: [Float],
        maxMagnitude: Float,
        renderingMode: RenderingMode,
        scrollingData: [[Float]]?,
        continuousWaveformData: [Float]?,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat,
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> any View {
        ZStack {
            // Camera view as background
            CameraPreviewView()
                .ignoresSafeArea()
            
            // Line chart overlay on top
            AnyView(
                lineChartPreset.makeView(
                    magnitudes: magnitudes,
                    rawAudioSamples: rawAudioSamples,
                    maxMagnitude: maxMagnitude,
                    renderingMode: renderingMode,
                    scrollingData: scrollingData,
                    continuousWaveformData: continuousWaveformData,
                    isRegularWidth: isRegularWidth,
                    chartHeight: chartHeight,
                    availableWidth: availableWidth,
                    horizontalPadding: horizontalPadding,
                    leftChannelSamples: leftChannelSamples,
                    rightChannelSamples: rightChannelSamples
                )
            )
            .background(Color.black.opacity(0.3))
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: chartHeight)
    }
}

/// Camera preview view using AVFoundation
private struct CameraPreviewView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // No updates needed
    }
}

/// Camera view controller managing AVCaptureSession
private class CameraViewController: UIViewController {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isSessionRunning = false
    private var isSetupComplete = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isSetupComplete {
            setupCamera()
        } else {
            sessionQueue.async { [weak self] in
                guard let self = self, let session = self.captureSession, !self.isSessionRunning else { return }
                session.startRunning()
                self.isSessionRunning = true
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure preview layer frame is correct after view appears
        previewLayer?.frame = view.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession, self.isSessionRunning else { return }
            session.stopRunning()
            self.isSessionRunning = false
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update preview layer frame on main thread
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer?.frame = self?.view.bounds ?? .zero
        }
    }
    
    #if os(macOS)
    /// Enable CoreMediaIO DAL plugins - required for OBS Virtual Camera and other virtual cameras
    /// This enables access to virtual cameras like OBS Virtual Camera
    private func enableCoreMediaIODALPlugins() {
        print("🔧 Attempting to enable CoreMediaIO DAL plugins...")
        
        // The property selector for allowing screen capture devices (virtual cameras)
        // This is a private constant, so we use its numeric value
        // kCMIOHardwarePropertyAllowScreenCaptureDevices = 0x73637265 ('scre')
        let kCMIOHardwarePropertyAllowScreenCaptureDevices: UInt32 = 0x73637265
        
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
        )
        
        // First, try to get the current value
        var currentValue: UInt32 = 0
        var dataSize = MemoryLayout<UInt32>.size
        var dataUsed: UInt32 = 0
        
        var getStatus = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(dataSize),
            &dataUsed,
            &currentValue
        )
        
        print("   Current DAL plugin state: \(currentValue == 1 ? "enabled" : "disabled") (getStatus: \(getStatus))")
        
        // Set the value to 1 (enabled)
        var allowScreenCaptureDevices: UInt32 = 1
        dataSize = MemoryLayout<UInt32>.size
        dataUsed = 0
        
        let setStatus = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(dataSize),
            &dataUsed,
            &allowScreenCaptureDevices
        )
        
        // Verify it was set
        var verifyValue: UInt32 = 0
        dataUsed = 0
        let verifyStatus = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(dataSize),
            &dataUsed,
            &verifyValue
        )
        
        print("   Set status: \(setStatus)")
        print("   Verify status: \(verifyStatus)")
        print("   New DAL plugin state: \(verifyValue == 1 ? "enabled" : "disabled")")
        
        if setStatus == kCMIOHardwareNoError && verifyValue == 1 {
            print("✅ CoreMediaIO DAL plugins enabled successfully (required for virtual cameras like OBS)")
        } else {
            print("⚠️ Failed to enable CoreMediaIO DAL plugins")
            print("   Set status: \(setStatus) (0 = success)")
            print("   Verify value: \(verifyValue) (expected 1)")
            print("   Note: This may require Screen Recording permission in System Settings")
            print("   OBS Virtual Camera may still work if OBS is running and virtual camera is active")
        }
    }
    #endif
    
    private func setupCamera() {
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            initializeCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.initializeCamera()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDeniedView()
        @unknown default:
            showPermissionDeniedView()
        }
    }
    
    private func initializeCamera() {
        print("📹 initializeCamera() called")
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                print("❌ initializeCamera: self is nil")
                return 
            }
            
            print("📹 initializeCamera: Starting on background queue")
            
            // Double-check permissions are actually granted
            let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            print("📹 Camera authorization status: \(authStatus.rawValue)")
            guard authStatus == .authorized else {
                print("❌ Camera permission not granted (status: \(authStatus.rawValue))")
                DispatchQueue.main.async {
                    self.showPermissionDeniedView()
                }
                return
            }
            
            // Enable CoreMediaIO DAL plugins (required for OBS Virtual Camera and other virtual cameras)
            #if os(macOS)
            print("📹 [macOS] About to enable CoreMediaIO DAL plugins...")
            self.enableCoreMediaIODALPlugins()
            print("📹 [macOS] Finished enabling CoreMediaIO DAL plugins, waiting for devices to register...")
            // Give the system time to register the virtual cameras after enabling DAL plugins
            Thread.sleep(forTimeInterval: 0.3)
            print("📹 [macOS] Proceeding with device discovery...")
            #else
            print("📹 [iOS] Skipping CoreMediaIO DAL plugins (iOS doesn't need this)")
            #endif
            
            // Clean up any existing session
            if let existingSession = self.captureSession {
                if existingSession.isRunning {
                    existingSession.stopRunning()
                }
                self.isSessionRunning = false
            }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            // Use a lower preset for better compatibility
            if session.canSetSessionPreset(.medium) {
                session.sessionPreset = .medium
            } else if session.canSetSessionPreset(.low) {
                session.sessionPreset = .low
            }
            
            // Try to find a camera device - check all available devices including virtual cameras
            var videoDevice: AVCaptureDevice?
            var availableDevices: [AVCaptureDevice] = []
            
            // Method 1: Try DiscoverySession with all device types
            var deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInTrueDepthCamera,
                .continuityCamera  // Continuity Camera devices
            ]
            
            // Add macOS-only device types
            #if os(macOS)
            deviceTypes.append(.externalUnknown)  // This includes virtual cameras
            deviceTypes.append(.deskViewCamera)   // Some virtual cameras might appear here
            #endif
            
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )
            
            availableDevices = discoverySession.devices
            print("📹 DiscoverySession found \(availableDevices.count) video device(s)")
            
            // Method 2: Fallback to older devices(for:) API if DiscoverySession found nothing
            if availableDevices.isEmpty {
                #if os(macOS)
                // On macOS, try the older API which might find more devices
                // First try devices(for:) which filters for video
                availableDevices = AVCaptureDevice.devices(for: .video)
                print("📹 Fallback devices(for:) found \(availableDevices.count) video device(s)")
                
                // If still nothing, try devices() to get ALL devices, then filter manually
                if availableDevices.isEmpty {
                    let allDevices = AVCaptureDevice.devices()
                    print("📹 Total AVCaptureDevices (all types): \(allDevices.count)")
                    availableDevices = allDevices.filter { $0.hasMediaType(.video) }
                    print("📹 Filtered to \(availableDevices.count) video-capable device(s)")
                    
                    // Log all devices for debugging
                    for device in allDevices {
                        print("   Device: \(device.localizedName)")
                        print("     - Has video: \(device.hasMediaType(.video))")
                        print("     - Has audio: \(device.hasMediaType(.audio))")
                        print("     - Type: \(device.deviceType.rawValue)")
                    }
                }
                #else
                // On iOS, try default device directly
                if let defaultDevice = AVCaptureDevice.default(for: .video) {
                    availableDevices = [defaultDevice]
                    print("📹 Default device API found 1 device")
                }
                #endif
            }
            
            // Log all found devices
            if !availableDevices.isEmpty {
                print("📹 Available video devices:")
                for device in availableDevices {
                    print("   - \(device.localizedName)")
                    print("     Type: \(device.deviceType.rawValue)")
                    print("     Position: \(device.position.rawValue)")
                    print("     UniqueID: \(device.uniqueID)")
                    #if os(macOS)
                    print("     ModelID: \(device.modelID)")
                    #endif
                }
            } else {
                print("⚠️ No video devices found with any method")
            }
            
            // Try devices in order of preference:
            // 1. Built-in back camera
            videoDevice = availableDevices.first { device in
                device.position == .back && device.deviceType == .builtInWideAngleCamera
            }
            
            // 2. Built-in front camera
            if videoDevice == nil {
                videoDevice = availableDevices.first { device in
                    device.position == .front && device.deviceType == .builtInWideAngleCamera
                }
            }
            
            // 3. Any built-in camera
            if videoDevice == nil {
                videoDevice = availableDevices.first { device in
                    device.deviceType == .builtInWideAngleCamera || 
                    device.deviceType == .builtInUltraWideCamera ||
                    device.deviceType == .builtInTelephotoCamera
                }
            }
            
            // 4. External/virtual cameras (this should catch virtual cameras)
            #if os(macOS)
            if videoDevice == nil {
                // Try externalUnknown first (most common for virtual cameras)
                videoDevice = availableDevices.first { device in
                    device.deviceType == .externalUnknown
                }
            }
            
            // 5. Try other external device types (macOS only)
            if videoDevice == nil {
                videoDevice = availableDevices.first { device in
                    device.deviceType == .deskViewCamera
                }
            }
            #endif
            
            // 6. Try continuity camera (available on both platforms)
            if videoDevice == nil {
                videoDevice = availableDevices.first { device in
                    device.deviceType == .continuityCamera
                }
            }
            
            // 7. Try ANY available device (last resort)
            if videoDevice == nil {
                videoDevice = availableDevices.first
            }
            
            // 8. Fallback to default device (this might work even if discovery didn't find it)
            if videoDevice == nil {
                videoDevice = AVCaptureDevice.default(for: .video)
                if let defaultDevice = videoDevice {
                    print("✅ Using default device: \(defaultDevice.localizedName)")
                }
            }
            
            guard let device = videoDevice else {
                print("❌ No camera device available")
                print("   DiscoverySession found: \(discoverySession.devices.count) device(s)")
                print("   Fallback API found: \(availableDevices.count) device(s)")
                print("   Default device: \(AVCaptureDevice.default(for: .video)?.localizedName ?? "nil")")
                
                // Try one more time with a broader search
                #if os(macOS)
                print("   Attempting broader device search...")
                let allDevices = AVCaptureDevice.devices()
                print("   Total AVCaptureDevices: \(allDevices.count)")
                for dev in allDevices {
                    print("     - \(dev.localizedName) (hasVideo: \(dev.hasMediaType(.video)))")
                }
                #endif
                
                DispatchQueue.main.async {
                    self.showErrorView(message: "No camera found\n\nDiscovery found \(availableDevices.count) device(s)\nCheck console for details")
                }
                session.commitConfiguration()
                return
            }
            
            print("✅ Selected camera: \(device.localizedName) (type: \(device.deviceType.rawValue))")
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                // Remove existing input if any
                if let existingInput = self.videoInput {
                    session.removeInput(existingInput)
                }
                
                if session.canAddInput(input) {
                    session.addInput(input)
                    self.videoInput = input
                } else {
                    print("❌ Cannot add camera input")
                    DispatchQueue.main.async {
                        self.showNoCameraView()
                    }
                    session.commitConfiguration()
                    return
                }
                
                session.commitConfiguration()
                
                DispatchQueue.main.async {
                    // Remove existing preview layer if any
                    self.previewLayer?.removeFromSuperlayer()
                    
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    previewLayer.frame = self.view.bounds
                    self.view.layer.insertSublayer(previewLayer, at: 0)
                    
                    self.previewLayer = previewLayer
                    self.captureSession = session
                    self.isSetupComplete = true
                    
                    // Start session on background queue with error handling
                    self.sessionQueue.async {
                        guard !self.isSessionRunning else { return }
                        
                        // Add notification observer for session errors
                        NotificationCenter.default.addObserver(
                            self,
                            selector: #selector(self.sessionRuntimeError),
                            name: .AVCaptureSessionRuntimeError,
                            object: session
                        )
                        
                        NotificationCenter.default.addObserver(
                            self,
                            selector: #selector(self.sessionWasInterrupted),
                            name: .AVCaptureSessionWasInterrupted,
                            object: session
                        )
                        
                        NotificationCenter.default.addObserver(
                            self,
                            selector: #selector(self.sessionInterruptionEnded),
                            name: .AVCaptureSessionInterruptionEnded,
                            object: session
                        )
                        
                        session.startRunning()
                        self.isSessionRunning = session.isRunning
                        
                        DispatchQueue.main.async {
                            if self.isSessionRunning {
                                print("✅ Camera session started successfully")
                            } else {
                                print("⚠️ Camera session failed to start")
                                self.showErrorView(message: "Camera failed to start")
                            }
                        }
                    }
                }
            } catch {
                print("❌ Failed to setup camera: \(error.localizedDescription)")
                session.commitConfiguration()
                DispatchQueue.main.async {
                    self.showNoCameraView()
                }
            }
        }
    }
    
    private func showPermissionDeniedView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Remove existing subviews
            self.view.subviews.forEach { $0.removeFromSuperview() }
            
            let label = UILabel()
            label.text = "Camera permission required"
            label.textColor = .white
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 16)
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
            ])
        }
    }
    
    private func showNoCameraView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Remove existing subviews
            self.view.subviews.forEach { $0.removeFromSuperview() }
            
            let label = UILabel()
            label.text = "No camera available"
            label.textColor = .white
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 16)
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
            ])
        }
    }
    
    private func showErrorView(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Remove existing subviews
            self.view.subviews.forEach { $0.removeFromSuperview() }
            
            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 14)
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(lessThanOrEqualTo: self.view.trailingAnchor, constant: -20)
            ])
        }
    }
    
    @objc private func sessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("❌ Camera session runtime error: \(error.localizedDescription)")
        
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            if session.isRunning {
                session.startRunning()
                self.isSessionRunning = session.isRunning
            } else {
                DispatchQueue.main.async {
                    self.showErrorView(message: "Camera error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func sessionWasInterrupted(notification: Notification) {
        print("⚠️ Camera session was interrupted")
        if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? AVCaptureSession.InterruptionReason {
            print("   Reason: \(reason)")
        }
    }
    
    @objc private func sessionInterruptionEnded(notification: Notification) {
        print("✅ Camera session interruption ended")
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession, !self.isSessionRunning else { return }
            session.startRunning()
            self.isSessionRunning = session.isRunning
        }
    }
    
    deinit {
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Clean up on main thread to avoid issues
        if let session = captureSession, isSessionRunning {
            sessionQueue.sync {
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }
        
        // Remove preview layer
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        
        // Remove input
        if let input = videoInput, let session = captureSession {
            sessionQueue.sync {
                if session.inputs.contains(input) {
                    session.removeInput(input)
                }
            }
        }
        
        captureSession = nil
        videoInput = nil
    }
}

