import SwiftUI
import MetalKit
import Metal

/// Camera Edge Color visualizer preset
/// Performs edge detection on camera frames and applies spectrogram-based color displacement
public struct CameraEdgeColorPreset: VisualizerPreset {
    public let id = "camera_edge_color"
    public let displayName = "Camera Edge (Color)"
    
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
        CameraEdgeColorMetalView(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth
        )
        #if targetEnvironment(macCatalyst)
        .frame(height: chartHeight)
        #else
        .frame(maxHeight: .infinity)
        #endif
    }
}

/// Metal view for camera edge color visualization
private struct CameraEdgeColorMetalView: UIViewRepresentable {
    let magnitudes: [Float]
    let maxMagnitude: Float
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let isRegularWidth: Bool
    
    @Environment(\.cameraEdgeDisplacementScale) var envDisplacementScale
    @Environment(\.cameraEdgeThreshold) var envEdgeThreshold
    @Environment(\.cameraEdgeSensitivity) var envEdgeSensitivity
    @Environment(\.cameraEdgeColorIntensity) var envColorIntensity
    @Environment(\.mslShaderOpacity) var envOpacity
    
    private var effectiveDisplacementScale: Float {
        envDisplacementScale != CameraEdgeDisplacementScaleKey.defaultValue ? envDisplacementScale : 0.2
    }
    
    private var effectiveEdgeThreshold: Float {
        envEdgeThreshold != CameraEdgeThresholdKey.defaultValue ? envEdgeThreshold : 0.1
    }
    
    private var effectiveEdgeSensitivity: Float {
        envEdgeSensitivity != CameraEdgeSensitivityKey.defaultValue ? envEdgeSensitivity : 1.0
    }
    
    private var effectiveColorIntensity: Float {
        envColorIntensity != CameraEdgeColorIntensityKey.defaultValue ? envColorIntensity : 1.0
    }
    
    private var effectiveOpacity: Float {
        envOpacity
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Failed to create Metal device")
            return mtkView
        }
        
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.isOpaque = true
        
        context.coordinator.setupMetal(device: device, view: mtkView)
        context.coordinator.updateData(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth,
            displacementScale: effectiveDisplacementScale,
            edgeThreshold: effectiveEdgeThreshold,
            edgeSensitivity: effectiveEdgeSensitivity,
            colorIntensity: effectiveColorIntensity,
            opacity: effectiveOpacity
        )
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateData(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth,
            displacementScale: effectiveDisplacementScale,
            edgeThreshold: effectiveEdgeThreshold,
            edgeSensitivity: effectiveEdgeSensitivity,
            colorIntensity: effectiveColorIntensity,
            opacity: effectiveOpacity
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var renderPipelineState: MTLRenderPipelineState!
        var edgeComputePipelineState: MTLComputePipelineState!
        var library: MTLLibrary!
        var cameraTextureProvider: CameraTextureProvider!
        var cameraTexture: MTLTexture?
        var edgeTexture: MTLTexture!
        var samplerState: MTLSamplerState!
        
        var magnitudes: [Float] = []
        var maxMagnitude: Float = 1.0
        var chartHeight: CGFloat = 200
        var availableWidth: CGFloat = 400
        var horizontalPadding: CGFloat = 16
        var isRegularWidth: Bool = true
        var viewportSize: SIMD2<Float> = SIMD2<Float>(400, 200)
        var displacementScale: Float = 0.2
        var edgeThreshold: Float = 0.1
        var edgeSensitivity: Float = 1.0
        var colorIntensity: Float = 1.0
        var opacity: Float = 1.0
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            
            guard let commandQueue = device.makeCommandQueue() else {
                print("ERROR: Failed to create Metal command queue")
                return
            }
            self.commandQueue = commandQueue
            
            // Embedded shader source as fallback
            let embeddedSource = """
                #include <metal_stdlib>
                using namespace metal;
                
                struct VertexOut {
                    float4 position [[position]];
                    float2 uv;
                };
                
                vertex VertexOut cameraEdgeVertex(
                    device const float4* vertices [[buffer(0)]],
                    device const float2* uvs [[buffer(1)]],
                    uint vid [[vertex_id]]
                ) {
                    VertexOut out;
                    out.position = vertices[vid];
                    out.uv = uvs[vid];
                    return out;
                }
                
                kernel void edgeDetectionCompute(
                    texture2d<float, access::read> inputTexture [[texture(0)]],
                    texture2d<float, access::write> edgeTexture [[texture(1)]],
                    constant float& threshold [[buffer(0)]],
                    constant float& sensitivity [[buffer(1)]],
                    uint2 gid [[thread_position_in_grid]]
                ) {
                    if (gid.x >= edgeTexture.get_width() || gid.y >= edgeTexture.get_height()) {
                        return;
                    }
                    uint width = inputTexture.get_width();
                    uint height = inputTexture.get_height();
                    float3 topLeft = inputTexture.read(uint2(max(0, int(gid.x) - 1), max(0, int(gid.y) - 1))).rgb;
                    float3 topMid = inputTexture.read(uint2(gid.x, max(0, int(gid.y) - 1))).rgb;
                    float3 topRight = inputTexture.read(uint2(min(width - 1, gid.x + 1), max(0, int(gid.y) - 1))).rgb;
                    float3 midLeft = inputTexture.read(uint2(max(0, int(gid.x) - 1), gid.y)).rgb;
                    float3 midRight = inputTexture.read(uint2(min(width - 1, gid.x + 1), gid.y)).rgb;
                    float3 bottomLeft = inputTexture.read(uint2(max(0, int(gid.x) - 1), min(height - 1, gid.y + 1))).rgb;
                    float3 bottomMid = inputTexture.read(uint2(gid.x, min(height - 1, gid.y + 1))).rgb;
                    float3 bottomRight = inputTexture.read(uint2(min(width - 1, gid.x + 1), min(height - 1, gid.y + 1))).rgb;
                    float grayTL = dot(topLeft, float3(0.299, 0.587, 0.114));
                    float grayTM = dot(topMid, float3(0.299, 0.587, 0.114));
                    float grayTR = dot(topRight, float3(0.299, 0.587, 0.114));
                    float grayML = dot(midLeft, float3(0.299, 0.587, 0.114));
                    float grayMR = dot(midRight, float3(0.299, 0.587, 0.114));
                    float grayBL = dot(bottomLeft, float3(0.299, 0.587, 0.114));
                    float grayBM = dot(bottomMid, float3(0.299, 0.587, 0.114));
                    float grayBR = dot(bottomRight, float3(0.299, 0.587, 0.114));
                    float sobelX = -grayTL + grayTR - 2.0 * grayML + 2.0 * grayMR - grayBL + grayBR;
                    float sobelY = -grayTL - 2.0 * grayTM - grayTR + grayBL + 2.0 * grayBM + grayBR;
                    float magnitude = sqrt(sobelX * sobelX + sobelY * sobelY);
                    magnitude *= sensitivity;
                    magnitude = clamp(magnitude / (4.0 * max(sensitivity, 0.1)), 0.0, 1.0);
                    float edgeValue = step(threshold, magnitude);
                    edgeTexture.write(float4(edgeValue, edgeValue, edgeValue, 1.0), gid);
                }
                
                fragment float4 cameraEdgeColorFragment(
                    VertexOut in [[stage_in]],
                    texture2d<float> cameraTexture [[texture(0)]],
                    texture2d<float> edgeTexture [[texture(1)]],
                    device const float* magnitudes [[buffer(0)]],
                    constant uint& magnitudeCount [[buffer(1)]],
                    constant float& maxMagnitude [[buffer(2)]],
                    constant float& displacementScale [[buffer(3)]],
                    constant float& edgeThreshold [[buffer(4)]],
                    constant float& colorIntensity [[buffer(5)]],
                    constant float& opacity [[buffer(6)]],
                    sampler textureSampler [[sampler(0)]]
                ) {
                    float2 rotatedUV = float2(in.uv.x, 1.0 - in.uv.y);
                    float edgeMask = edgeTexture.sample(textureSampler, rotatedUV).r;
                    if (edgeMask > edgeThreshold) {
                        float2 center = float2(0.5, 0.5);
                        float2 direction = in.uv - center;
                        float distance = length(direction);
                        if (distance > 0.001) {
                            direction = normalize(direction);
                        } else {
                            direction = float2(0.0, 1.0);
                        }
                        float binIndexFloat = in.uv.x * float(magnitudeCount - 1);
                        uint binIndex = uint(clamp(binIndexFloat, 0.0, float(magnitudeCount - 1)));
                        float magnitude = 0.0;
                        if (binIndex < magnitudeCount) {
                            magnitude = magnitudes[binIndex];
                        }
                        float normalizedMag = magnitude / max(maxMagnitude, 0.001);
                        normalizedMag = clamp(normalizedMag, 0.0, 1.0);
                        float displacementMagnitude = normalizedMag * displacementScale;
                        float2 displacement = direction * displacementMagnitude;
                        float2 displacedUV = in.uv + displacement;
                        displacedUV = clamp(displacedUV, 0.0, 1.0);
                        float2 rotatedDisplacedUV = float2(displacedUV.x, 1.0 - displacedUV.y);
                        float4 cameraColor = cameraTexture.sample(textureSampler, rotatedDisplacedUV);
                        float bandPosition = float(binIndex) / float(max(float(magnitudeCount - 1), 1.0));
                        float3 frequencyColor;
                        if (bandPosition < 0.33) {
                            float t = bandPosition / 0.33;
                            frequencyColor = mix(float3(1.0, 0.0, 0.0), float3(1.0, 1.0, 0.0), t);
                        } else if (bandPosition < 0.66) {
                            float t = (bandPosition - 0.33) / 0.33;
                            frequencyColor = mix(float3(1.0, 1.0, 0.0), float3(0.0, 1.0, 1.0), t);
                        } else {
                            float t = (bandPosition - 0.66) / 0.34;
                            frequencyColor = mix(float3(0.0, 1.0, 1.0), float3(1.0, 0.0, 1.0), t);
                        }
                        float3 finalColor = mix(cameraColor.rgb, frequencyColor * colorIntensity, normalizedMag * 0.5);
                        return float4(finalColor, cameraColor.a * opacity);
                    } else {
                        float4 color = cameraTexture.sample(textureSampler, rotatedUV);
                        return float4(color.rgb, color.a * opacity);
                    }
                }
                """
            
            // Load shader library
            library = ShaderManager.shared.loadShaderWithFallback(
                name: "MSLCameraEdge",
                device: device,
                defaultLibrary: device.makeDefaultLibrary(),
                embeddedSource: embeddedSource
            )
            
            guard let finalLibrary = library else {
                print("ERROR: Failed to create Metal library for camera edge shader")
                return
            }
            self.library = finalLibrary
            print("✓ Camera Edge Color Metal library loaded successfully")
            
            // Create edge detection compute pipeline
            if let computeFunction = finalLibrary.makeFunction(name: "edgeDetectionCompute") {
                do {
                    edgeComputePipelineState = try device.makeComputePipelineState(function: computeFunction)
                } catch {
                    print("ERROR: Failed to create edge detection compute pipeline: \(error)")
                }
            }
            
            // Create render pipeline
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            guard let vertexFunc = finalLibrary.makeFunction(name: "cameraEdgeVertex"),
                  let fragmentFunc = finalLibrary.makeFunction(name: "cameraEdgeColorFragment") else {
                print("ERROR: Failed to find shader functions in library")
                print("  Available functions: \(finalLibrary.functionNames)")
                return
            }
            
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✓ Camera Edge Color render pipeline created successfully")
            } catch {
                print("ERROR: Failed to create Camera Edge Color render pipeline: \(error)")
                return
            }
            
            // Create edge texture (will be resized when camera texture is available)
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: 640,
                height: 480,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            edgeTexture = device.makeTexture(descriptor: textureDescriptor)
            
            // Create sampler state
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
            
            guard samplerState != nil else {
                print("ERROR: Could not create sampler state")
                return
            }
            
            // Setup camera texture provider
            cameraTextureProvider = CameraTextureProvider()
            cameraTextureProvider.onNewFrame = { [weak self] texture in
                self?.cameraTexture = texture
                // Resize edge texture if needed
                if let edgeTexture = self?.edgeTexture,
                   edgeTexture.width != texture.width || edgeTexture.height != texture.height {
                    let newDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .r8Unorm,
                        width: texture.width,
                        height: texture.height,
                        mipmapped: false
                    )
                    newDescriptor.usage = [.shaderRead, .shaderWrite]
                    self?.edgeTexture = device.makeTexture(descriptor: newDescriptor)
                }
            }
            
            if !cameraTextureProvider.startCapture(device: device) {
                print("ERROR: Failed to start camera capture")
            }
        }
        
        func updateData(
            magnitudes: [Float],
            maxMagnitude: Float,
            chartHeight: CGFloat,
            availableWidth: CGFloat,
            horizontalPadding: CGFloat,
            isRegularWidth: Bool,
            displacementScale: Float,
            edgeThreshold: Float,
            edgeSensitivity: Float,
            colorIntensity: Float,
            opacity: Float
        ) {
            self.magnitudes = magnitudes
            self.maxMagnitude = maxMagnitude
            self.chartHeight = chartHeight
            self.availableWidth = availableWidth
            self.horizontalPadding = horizontalPadding
            self.isRegularWidth = isRegularWidth
            self.viewportSize = SIMD2<Float>(Float(availableWidth), Float(chartHeight))
            self.displacementScale = displacementScale
            self.edgeThreshold = edgeThreshold
            self.edgeSensitivity = edgeSensitivity
            self.colorIntensity = colorIntensity
            self.opacity = opacity
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let edgeComputePipeline = edgeComputePipelineState,
                  let renderPipeline = renderPipelineState,
                  let edgeTexture = edgeTexture,
                  let samplerState = samplerState else {
                return
            }
            
            // Get camera texture - check cached first, then provider
            guard let cameraTextureProvider = cameraTextureProvider else {
                // Camera not initialized yet, skip rendering
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            let cameraTexture = cameraTexture ?? cameraTextureProvider.getCurrentTexture()
            guard let cameraTexture = cameraTexture else {
                // No camera texture available yet, skip rendering
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Perform edge detection on camera texture
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            computeEncoder.setComputePipelineState(edgeComputePipeline)
            computeEncoder.setTexture(cameraTexture, index: 0)
            computeEncoder.setTexture(edgeTexture, index: 1)
            
            var threshold = edgeThreshold
            var sensitivity = edgeSensitivity
            computeEncoder.setBytes(&threshold, length: MemoryLayout<Float>.stride, index: 0)
            computeEncoder.setBytes(&sensitivity, length: MemoryLayout<Float>.stride, index: 1)
            
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(
                width: (edgeTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
                height: (edgeTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
                depth: 1
            )
            computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            computeEncoder.endEncoding()
            
            // Render with displacement
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Create full-screen quad
            let drawableSize = view.drawableSize
            let viewWidth = max(Float(drawableSize.width), 1.0)
            let viewHeight = max(Float(drawableSize.height), 1.0)
            
            func toNDC(x: Float, y: Float) -> SIMD4<Float> {
                let ndcX = (x / viewWidth) * 2.0 - 1.0
                let ndcY = 1.0 - (y / viewHeight) * 2.0
                return SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
            }
            
            let vertices: [SIMD4<Float>] = [
                toNDC(x: 0, y: 0),
                toNDC(x: viewWidth, y: 0),
                toNDC(x: 0, y: viewHeight),
                toNDC(x: viewWidth, y: viewHeight)
            ]
            
            let uvs: [SIMD2<Float>] = [
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(1.0, 1.0),
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(1.0, 0.0)
            ]
            
            guard let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<SIMD4<Float>>.stride,
                options: []
            ),
            let uvBuffer = device.makeBuffer(
                bytes: uvs,
                length: uvs.count * MemoryLayout<SIMD2<Float>>.stride,
                options: []
            ) else {
                renderEncoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Create buffer for magnitudes
            guard let magnitudeBuffer = device.makeBuffer(
                bytes: magnitudes,
                length: magnitudes.count * MemoryLayout<Float>.stride,
                options: []
            ) else {
                renderEncoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            var magnitudeCount = UInt32(magnitudes.count)
            var maxMag = maxMagnitude
            var displacementScaleValue = displacementScale
            var edgeThresholdValue = edgeThreshold
            var colorIntensityValue = colorIntensity
            var opacityValue = opacity
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTexture(cameraTexture, index: 0)
            renderEncoder.setFragmentTexture(edgeTexture, index: 1)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            renderEncoder.setFragmentBuffer(magnitudeBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBytes(&magnitudeCount, length: MemoryLayout<UInt32>.stride, index: 1)
            renderEncoder.setFragmentBytes(&maxMag, length: MemoryLayout<Float>.stride, index: 2)
            renderEncoder.setFragmentBytes(&displacementScaleValue, length: MemoryLayout<Float>.stride, index: 3)
            renderEncoder.setFragmentBytes(&edgeThresholdValue, length: MemoryLayout<Float>.stride, index: 4)
            renderEncoder.setFragmentBytes(&colorIntensityValue, length: MemoryLayout<Float>.stride, index: 5)
            renderEncoder.setFragmentBytes(&opacityValue, length: MemoryLayout<Float>.stride, index: 6)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        deinit {
            cameraTextureProvider?.stopCapture()
        }
    }
}

