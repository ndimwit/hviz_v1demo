import SwiftUI
import MetalKit
import Metal

/// MSL Template visualizer preset with live code editing
/// Allows users to edit and hotswap shader code at runtime
public struct MSLTemplatePreset: VisualizerPreset {
    public let id = "msl_template"
    public let displayName = "MSL Template"
    
    /// Default shader code (Camera Edge Waveform preset)
    public static let defaultShaderCode = """
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

fragment float4 cameraEdgeWaveformFragment(
    VertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> edgeTexture [[texture(1)]],
    device const float* rawAudioSamples [[buffer(0)]],
    constant uint& sampleCount [[buffer(1)]],
    constant float& maxAmplitude [[buffer(2)]],
    constant float& displacementScale [[buffer(3)]],
    constant float& edgeThreshold [[buffer(4)]],
    constant float& opacity [[buffer(5)]],
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
        float sampleIndexFloat = in.uv.x * float(sampleCount - 1);
        uint sampleIndex = uint(clamp(sampleIndexFloat, 0.0, float(sampleCount - 1)));
        float sampleValue = 0.0;
        if (sampleIndex < sampleCount) {
            sampleValue = rawAudioSamples[sampleIndex];
        }
        float normalizedAmplitude = abs(sampleValue) / max(maxAmplitude, 0.001);
        normalizedAmplitude = clamp(normalizedAmplitude, 0.0, 1.0);
        float displacementMagnitude = normalizedAmplitude * displacementScale;
        float2 displacement = direction * displacementMagnitude;
        float2 displacedUV = in.uv + displacement;
        displacedUV = clamp(displacedUV, 0.0, 1.0);
        float2 rotatedDisplacedUV = float2(displacedUV.x, 1.0 - displacedUV.y);
        float4 color = cameraTexture.sample(textureSampler, rotatedDisplacedUV);
        return float4(color.rgb, color.a * opacity);
    } else {
        float4 color = cameraTexture.sample(textureSampler, rotatedUV);
        return float4(color.rgb, color.a * opacity);
    }
}
"""
    
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
        MSLTemplateMetalView(
            magnitudes: magnitudes,
            rawAudioSamples: rawAudioSamples,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth
        )
        .frame(height: chartHeight)
    }
}

/// Metal view for MSL template visualization with dynamic shader loading
private struct MSLTemplateMetalView: UIViewRepresentable {
    let magnitudes: [Float]
    let rawAudioSamples: [Float]
    let maxMagnitude: Float
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let isRegularWidth: Bool
    
    @Environment(\.mslTemplateShaderCode) var shaderCode
    @Environment(\.mslTemplateReloadTrigger) var reloadTrigger
    
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
        
        context.coordinator.setupMetal(device: device, view: mtkView, initialShaderCode: shaderCode)
        context.coordinator.updateData(
            magnitudes: magnitudes,
            rawAudioSamples: rawAudioSamples,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth
        )
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // Check if shader code changed and reload if needed
        if context.coordinator.lastShaderCode != shaderCode || reloadTrigger > context.coordinator.lastReloadTrigger {
            context.coordinator.reloadShader(code: shaderCode)
            context.coordinator.lastShaderCode = shaderCode
            context.coordinator.lastReloadTrigger = reloadTrigger
        }
        
        context.coordinator.updateData(
            magnitudes: magnitudes,
            rawAudioSamples: rawAudioSamples,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var renderPipelineState: MTLRenderPipelineState?
        var computePipelineState: MTLComputePipelineState?
        var library: MTLLibrary?
        var cameraTextureProvider: CameraTextureProvider?
        var cameraTexture: MTLTexture?
        var edgeTexture: MTLTexture!
        var samplerState: MTLSamplerState!
        
        var lastShaderCode: String = ""
        var lastReloadTrigger: Int = 0
        var lastValidShaderCode: String = ""
        var lastValidLibrary: MTLLibrary?
        
        var magnitudes: [Float] = []
        var rawAudioSamples: [Float] = []
        var maxMagnitude: Float = 1.0
        var chartHeight: CGFloat = 200
        var availableWidth: CGFloat = 400
        var horizontalPadding: CGFloat = 16
        var isRegularWidth: Bool = true
        var viewportSize: SIMD2<Float> = SIMD2<Float>(400, 200)
        var displacementScale: Float = 0.2
        var edgeThreshold: Float = 0.1
        var edgeSensitivity: Float = 1.0
        var opacity: Float = 1.0
        
        func setupMetal(device: MTLDevice, view: MTKView, initialShaderCode: String) {
            self.device = device
            self.currentView = view
            
            guard let commandQueue = device.makeCommandQueue() else {
                print("ERROR: Failed to create Metal command queue")
                return
            }
            self.commandQueue = commandQueue
            
            // Use provided shader code or default
            let codeToUse = initialShaderCode.isEmpty ? MSLTemplatePreset.defaultShaderCode : initialShaderCode
            lastShaderCode = codeToUse
            lastValidShaderCode = codeToUse
            
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
            
            // Load initial shader
            loadShader(code: codeToUse, view: view)
            
            // Setup camera texture provider
            cameraTextureProvider = CameraTextureProvider()
            cameraTextureProvider?.onNewFrame = { [weak self] texture in
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
            
            if !(cameraTextureProvider?.startCapture(device: device) ?? false) {
                print("WARNING: Failed to start camera capture")
            }
        }
        
        func loadShader(code: String, view: MTKView?) -> Bool {
            guard !code.isEmpty else {
                print("ERROR: Empty shader code")
                return false
            }
            
            // Try to compile the shader
            let newLibrary: MTLLibrary?
            do {
                let compileOptions = MTLCompileOptions()
                compileOptions.fastMathEnabled = true
                newLibrary = try device.makeLibrary(source: code, options: compileOptions)
                print("✓ MSL Template shader compiled successfully")
            } catch {
                print("ERROR: Failed to compile MSL Template shader: \(error)")
                // Return false to indicate failure, but don't change current library
                return false
            }
            
            guard let compiledLibrary = newLibrary else {
                return false
            }
            
            // Try to find required functions
            // We'll try to find common function names
            let vertexFunc = compiledLibrary.makeFunction(name: "cameraEdgeVertex") ??
                            compiledLibrary.makeFunction(name: "vertex") ??
                            compiledLibrary.makeFunction(name: "mainVertex")
            
            let fragmentFunc = compiledLibrary.makeFunction(name: "cameraEdgeWaveformFragment") ??
                              compiledLibrary.makeFunction(name: "fragment") ??
                              compiledLibrary.makeFunction(name: "mainFragment")
            
            let computeFunc = compiledLibrary.makeFunction(name: "edgeDetectionCompute") ??
                             compiledLibrary.makeFunction(name: "compute") ??
                             compiledLibrary.makeFunction(name: "mainCompute")
            
            // Create pipelines if we have the functions
            var newRenderPipeline: MTLRenderPipelineState?
            var newComputePipeline: MTLComputePipelineState?
            
            if let vertexFunc = vertexFunc, let fragmentFunc = fragmentFunc, let view = view {
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                
                do {
                    newRenderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                    print("✓ MSL Template render pipeline created")
                } catch {
                    print("ERROR: Failed to create render pipeline: \(error)")
                }
            }
            
            if let computeFunc = computeFunc {
                do {
                    newComputePipeline = try device.makeComputePipelineState(function: computeFunc)
                    print("✓ MSL Template compute pipeline created")
                } catch {
                    print("ERROR: Failed to create compute pipeline: \(error)")
                }
            }
            
            // If we have at least a render pipeline, update everything
            if newRenderPipeline != nil {
                // Update to new shader
                library = compiledLibrary
                renderPipelineState = newRenderPipeline
                computePipelineState = newComputePipeline
                lastValidShaderCode = code
                lastValidLibrary = compiledLibrary
                
                // Clean up old resources if needed (they'll be deallocated automatically)
                print("✓ MSL Template shader loaded successfully")
                return true
            } else {
                print("ERROR: Shader compiled but no valid render pipeline could be created")
                print("  Available functions: \(compiledLibrary.functionNames)")
                return false
            }
        }
        
        var currentView: MTKView?
        
        func reloadShader(code: String) {
            guard let view = currentView else {
                print("WARNING: Cannot reload shader - view not available")
                return
            }
            
            // Try to load new shader
            let success = loadShader(code: code, view: view)
            
            if !success {
                // Fallback to last valid shader
                if let lastValid = lastValidLibrary, lastValidShaderCode != code {
                    print("⚠️ Shader compilation failed, reverting to last valid shader")
                    library = lastValid
                    // Recreate pipelines with last valid library
                    recreatePipelines(from: lastValid, view: view)
                }
            }
        }
        
        func recreatePipelines(from library: MTLLibrary, view: MTKView?) {
            let vertexFunc = library.makeFunction(name: "cameraEdgeVertex") ??
                            library.makeFunction(name: "vertex") ??
                            library.makeFunction(name: "mainVertex")
            
            let fragmentFunc = library.makeFunction(name: "cameraEdgeWaveformFragment") ??
                              library.makeFunction(name: "fragment") ??
                              library.makeFunction(name: "mainFragment")
            
            let computeFunc = library.makeFunction(name: "edgeDetectionCompute") ??
                             library.makeFunction(name: "compute") ??
                             library.makeFunction(name: "mainCompute")
            
            if let vertexFunc = vertexFunc, let fragmentFunc = fragmentFunc, let view = view {
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                
                do {
                    renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                } catch {
                    print("ERROR: Failed to recreate render pipeline: \(error)")
                }
            }
            
            if let computeFunc = computeFunc {
                do {
                    computePipelineState = try device.makeComputePipelineState(function: computeFunc)
                } catch {
                    print("ERROR: Failed to recreate compute pipeline: \(error)")
                }
            }
        }
        
        func updateData(
            magnitudes: [Float],
            rawAudioSamples: [Float],
            maxMagnitude: Float,
            chartHeight: CGFloat,
            availableWidth: CGFloat,
            horizontalPadding: CGFloat,
            isRegularWidth: Bool
        ) {
            self.magnitudes = magnitudes
            self.rawAudioSamples = rawAudioSamples
            self.maxMagnitude = maxMagnitude
            self.chartHeight = chartHeight
            self.availableWidth = availableWidth
            self.horizontalPadding = horizontalPadding
            self.isRegularWidth = isRegularWidth
            self.viewportSize = SIMD2<Float>(Float(availableWidth), Float(chartHeight))
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPipeline = renderPipelineState,
                  let edgeTexture = edgeTexture,
                  let samplerState = samplerState else {
                return
            }
            
            // Get camera texture
            guard let cameraTextureProvider = cameraTextureProvider else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            let cameraTexture = cameraTexture ?? cameraTextureProvider.getCurrentTexture()
            guard let cameraTexture = cameraTexture else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Perform edge detection if compute pipeline is available
            if let computePipeline = computePipelineState {
                guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                    return
                }
                
                computeEncoder.setComputePipelineState(computePipeline)
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
            }
            
            // Render
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
            
            var sampleCount = UInt32(rawAudioSamples.count)
            var maxAmp = maxMagnitude
            var dispScale = displacementScale
            var edgeThresh = edgeThreshold
            var opac = opacity
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTexture(cameraTexture, index: 0)
            renderEncoder.setFragmentTexture(edgeTexture, index: 1)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            
            if let sampleBuffer = device.makeBuffer(
                bytes: rawAudioSamples,
                length: rawAudioSamples.count * MemoryLayout<Float>.stride,
                options: []
            ) {
                renderEncoder.setFragmentBuffer(sampleBuffer, offset: 0, index: 0)
            }
            renderEncoder.setFragmentBytes(&sampleCount, length: MemoryLayout<UInt32>.stride, index: 1)
            renderEncoder.setFragmentBytes(&maxAmp, length: MemoryLayout<Float>.stride, index: 2)
            renderEncoder.setFragmentBytes(&dispScale, length: MemoryLayout<Float>.stride, index: 3)
            renderEncoder.setFragmentBytes(&edgeThresh, length: MemoryLayout<Float>.stride, index: 4)
            renderEncoder.setFragmentBytes(&opac, length: MemoryLayout<Float>.stride, index: 5)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

