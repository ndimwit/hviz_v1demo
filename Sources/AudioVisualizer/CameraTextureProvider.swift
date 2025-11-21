import Foundation
import AVFoundation
import Metal
import MetalKit
import CoreVideo

/// Provides camera frames as Metal textures for processing
class CameraTextureProvider: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Properties
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoInput: AVCaptureDeviceInput?
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?
    private let textureQueue = DispatchQueue(label: "camera.texture.queue")
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var device: MTLDevice?
    private var isSessionRunning = false
    private var isSetupComplete = false
    
    /// Callback when a new frame texture is available
    var onNewFrame: ((MTLTexture) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start capturing camera frames and converting to Metal textures
    func startCapture(device: MTLDevice) -> Bool {
        self.device = device
        
        // Create texture cache
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        
        guard result == kCVReturnSuccess, let textureCache = cache else {
            print("ERROR: Failed to create CVMetalTextureCache")
            return false
        }
        
        self.textureCache = textureCache
        
        // Setup camera on background queue
        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
        
        return true
    }
    
    /// Stop capturing camera frames
    func stopCapture() {
        // Clear callback first to prevent it from being called during cleanup
        onNewFrame = nil
        
        // Use sync for immediate cleanup (safe to call from deinit)
        // Don't use [weak self] here since we're in deinit and need to complete cleanup
        sessionQueue.sync {
            // Remove delegate to prevent callbacks during cleanup
            if let output = videoOutput {
                output.setSampleBufferDelegate(nil, queue: nil)
            }
            
            // Stop session if running
            if let session = captureSession, isSessionRunning {
                if session.isRunning {
                    session.stopRunning()
                }
                isSessionRunning = false
            }
            
            // Remove inputs and outputs
            if let session = captureSession {
                if let input = videoInput {
                    session.removeInput(input)
                }
                if let output = videoOutput {
                    session.removeOutput(output)
                }
            }
            
            videoInput = nil
            videoOutput = nil
            captureSession = nil
        }
    }
    
    /// Get the current camera texture (thread-safe)
    func getCurrentTexture() -> MTLTexture? {
        return textureQueue.sync {
            return currentTexture
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        guard let textureCache = textureCache,
              let device = device,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Create Metal texture from pixel buffer
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard result == kCVReturnSuccess,
              let cvMetalTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvMetalTexture) else {
            return
        }
        
        // Update current texture on texture queue
        textureQueue.async { [weak self] in
            self?.currentTexture = texture
            if let callback = self?.onNewFrame {
                callback(texture)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            initializeCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async {
                        self?.initializeCamera()
                    }
                }
            }
        case .denied, .restricted:
            print("Camera permission denied")
        @unknown default:
            print("Unknown camera permission status")
        }
    }
    
    private func initializeCamera() {
        guard let device = device else { return }
        
        // Clean up existing session
        if let existingSession = captureSession {
            if existingSession.isRunning {
                existingSession.stopRunning()
            }
            isSessionRunning = false
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Use medium preset for better performance
        if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        } else if session.canSetSessionPreset(.low) {
            session.sessionPreset = .low
        }
        
        // Find camera device
        var videoDevice: AVCaptureDevice?
        
        #if os(macOS)
        // Enable CoreMediaIO DAL plugins for virtual cameras
        enableCoreMediaIODALPlugins()
        Thread.sleep(forTimeInterval: 0.3)
        #endif
        
        // Try to find a camera device
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera
        ]
        
        #if os(macOS)
        deviceTypes.append(.externalUnknown)
        deviceTypes.append(.deskViewCamera)
        #endif
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        videoDevice = discoverySession.devices.first ?? AVCaptureDevice.default(for: .video)
        
        guard let camera = videoDevice else {
            print("ERROR: No camera device available")
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            } else {
                print("ERROR: Cannot add camera input")
                session.commitConfiguration()
                return
            }
            
            // Setup video output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: textureQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                videoOutput = output
            } else {
                print("ERROR: Cannot add video output")
                session.commitConfiguration()
                return
            }
            
            session.commitConfiguration()
            captureSession = session
            isSetupComplete = true
            
            // Start session
            session.startRunning()
            isSessionRunning = session.isRunning
            
            if isSessionRunning {
                print("✅ Camera texture provider started successfully")
            } else {
                print("⚠️ Camera session failed to start")
            }
            
        } catch {
            print("ERROR: Failed to setup camera: \(error.localizedDescription)")
            session.commitConfiguration()
        }
    }
    
    #if os(macOS)
    private func enableCoreMediaIODALPlugins() {
        let kCMIOHardwarePropertyAllowScreenCaptureDevices: UInt32 = 0x73637265
        
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
        )
        
        var allowScreenCaptureDevices: UInt32 = 1
        let dataSize = MemoryLayout<UInt32>.size
        var dataUsed: UInt32 = 0
        
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(dataSize),
            &dataUsed,
            &allowScreenCaptureDevices
        )
    }
    #endif
    
    deinit {
        stopCapture()
        textureCache = nil
    }
}

