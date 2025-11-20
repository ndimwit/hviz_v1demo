import SwiftUI
import AVFoundation
import Charts

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
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupCamera()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
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
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ??
                                    AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async {
                    self.showNoCameraView()
                }
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: videoDevice)
                
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    DispatchQueue.main.async {
                        self.showNoCameraView()
                    }
                    return
                }
                
                session.commitConfiguration()
                
                DispatchQueue.main.async {
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    previewLayer.frame = self.view.bounds
                    self.view.layer.insertSublayer(previewLayer, at: 0)
                    
                    self.previewLayer = previewLayer
                    self.captureSession = session
                    
                    // Start session on background queue
                    self.sessionQueue.async {
                        session.startRunning()
                    }
                }
            } catch {
                print("Failed to setup camera: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.showNoCameraView()
                }
            }
        }
    }
    
    private func showPermissionDeniedView() {
        let label = UILabel()
        label.text = "Camera permission required"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func showNoCameraView() {
        let label = UILabel()
        label.text = "No camera available"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    deinit {
        sessionQueue.async { [weak captureSession] in
            captureSession?.stopRunning()
        }
    }
}

