import SwiftUI
import MetalKit
import Metal

/// MSL Waveform visualizer preset
/// Based on FFmpeg waveform filter - displays audio waveform as a 2D luminance visualization
/// X-axis: time, Y-axis: amplitude, Intensity: frequency of occurrence
public struct MSLWaveformPreset: VisualizerPreset {
    public let id = "msl_waveform"
    public let displayName = "MSL Waveform"
    
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
        MSLWaveformMetalView(
            rawAudioSamples: rawAudioSamples,
            continuousWaveformData: continuousWaveformData,
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

/// Metal view for waveform shader visualization
private struct MSLWaveformMetalView: UIViewRepresentable {
    let rawAudioSamples: [Float]
    let continuousWaveformData: [Float]?
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let isRegularWidth: Bool
    
    @Environment(\.mslShaderOpacity) var envOpacity
    
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
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0) // Transparent background
        mtkView.isOpaque = false // Allow transparency
        
        context.coordinator.setupMetal(device: device, view: mtkView)
        context.coordinator.updateData(
            rawAudioSamples: rawAudioSamples,
            continuousWaveformData: continuousWaveformData,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth,
            opacity: effectiveOpacity
        )
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateData(
            rawAudioSamples: rawAudioSamples,
            continuousWaveformData: continuousWaveformData,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth,
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
        var computePipelineState: MTLComputePipelineState!
        var library: MTLLibrary!
        var waveformTexture: MTLTexture!
        var waveformTextureDescriptor: MTLTextureDescriptor!
        var waveformBuffer: [Float] = []
        var waveformWidth: Int = 512
        var waveformHeight: Int = 256
        var samplerState: MTLSamplerState!
        
        var rawAudioSamples: [Float] = []
        var continuousWaveformData: [Float]? = nil
        var chartHeight: CGFloat = 200
        var availableWidth: CGFloat = 400
        var horizontalPadding: CGFloat = 16
        var isRegularWidth: Bool = true
        var time: Float = 0.0
        var viewportSize: SIMD2<Float> = SIMD2<Float>(400, 200)
        var scrollPosition: Int = 0
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
                
                vertex VertexOut waveformVertex(
                    device const float4* vertices [[buffer(0)]],
                    device const float2* uvs [[buffer(1)]],
                    uint vid [[vertex_id]]
                ) {
                    VertexOut out;
                    out.position = vertices[vid];
                    out.uv = uvs[vid];
                    return out;
                }
                
                fragment float4 waveformFragment(
                    VertexOut in [[stage_in]],
                    texture2d<float> waveformTexture [[texture(0)]],
                    constant float& time [[buffer(0)]],
                    constant float2& viewportSize [[buffer(1)]],
                    constant float& opacity [[buffer(2)]],
                    sampler textureSampler [[sampler(0)]]
                ) {
                    float waveformValue = waveformTexture.sample(textureSampler, in.uv).r;
                    float normalized = pow(waveformValue, 0.5);
                    float3 color;
                    if (normalized > 0.8) {
                        color = float3(1.0, 1.0, 0.8);
                    } else if (normalized > 0.5) {
                        float t = (normalized - 0.5) / 0.3;
                        color = mix(float3(0.0, 1.0, 1.0), float3(1.0, 1.0, 0.8), t);
                    } else if (normalized > 0.2) {
                        float t = (normalized - 0.2) / 0.3;
                        color = mix(float3(0.0, 0.5, 1.0), float3(0.0, 1.0, 1.0), t);
                    } else {
                        float t = normalized / 0.2;
                        color = mix(float3(0.0, 0.0, 0.1), float3(0.0, 0.5, 1.0), t);
                    }
                    color *= normalized;
                    float pulse = sin(time * 0.5) * 0.05 + 0.95;
                    color *= pulse;
                    float luminance = dot(color, float3(0.299, 0.587, 0.114));
                    float alpha = step(0.01, luminance);
                    alpha *= opacity;
                    return float4(color, alpha);
                }
                
                kernel void mslGenerateWaveform(
                    device const float* samples [[buffer(0)]],
                    constant uint& sampleCount [[buffer(1)]],
                    constant float& time [[buffer(2)]],
                    constant uint& scrollPosition [[buffer(3)]],
                    constant float2& viewportSize [[buffer(4)]],
                    constant uint& textureWidth [[buffer(5)]],
                    constant uint& textureHeight [[buffer(6)]],
                    constant float& maxAmplitude [[buffer(7)]],
                    texture2d<float, access::read_write> waveformTexture [[texture(0)]],
                    uint2 gid [[thread_position_in_grid]]
                ) {
                    if (gid.x >= textureWidth || gid.y >= textureHeight) {
                        return;
                    }
                    float currentValue = waveformTexture.read(gid).r;
                    float decay = 0.98;
                    currentValue *= decay;
                    int textureX = int(gid.x);
                    int scrollOffset = int(scrollPosition);
                    float sampleIndexFloat = (float(textureX) / float(textureWidth)) * float(sampleCount);
                    int sampleIndex = int(sampleIndexFloat);
                    if (sampleIndex >= 0 && sampleIndex < int(sampleCount)) {
                        float sampleValue = samples[sampleIndex];
                        float normalizedAmplitude = sampleValue / max(maxAmplitude, 0.001);
                        normalizedAmplitude = clamp(normalizedAmplitude, -1.0, 1.0);
                        float amplitudeRange = 2.0;
                        float textureYNormalized = 1.0 - (float(gid.y) / float(textureHeight));
                        float amplitudeAtY = (textureYNormalized * amplitudeRange) - 1.0;
                        float amplitudeThreshold = 1.0 / float(textureHeight);
                        if (abs(normalizedAmplitude - amplitudeAtY) < amplitudeThreshold) {
                            currentValue += 0.1;
                        }
                    }
                    currentValue = clamp(currentValue, 0.0, 1.0);
                    waveformTexture.write(float4(currentValue, currentValue, currentValue, 1.0), gid);
                }
                """
                
            // Try loading from file first, then fall back to embedded source
            library = ShaderManager.shared.loadShaderWithFallback(
                name: "MSLWaveform",
                device: device,
                defaultLibrary: device.makeDefaultLibrary(),
                embeddedSource: embeddedSource
            )
            
            guard let finalLibrary = library else {
                print("ERROR: Failed to create Metal library for waveform shader")
                return
            }
            self.library = finalLibrary
            print("✓ MSL Waveform Metal library loaded successfully")
            
            // Create compute pipeline for generating waveform texture
            if let computeFunction = finalLibrary.makeFunction(name: "mslGenerateWaveform") {
                do {
                    computePipelineState = try device.makeComputePipelineState(function: computeFunction)
                } catch {
                    print("Failed to create compute pipeline: \(error)")
                }
            }
            
            // Create render pipeline
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            guard let vertexFunc = finalLibrary.makeFunction(name: "waveformVertex"),
                  let fragmentFunc = finalLibrary.makeFunction(name: "waveformFragment") else {
                print("ERROR: Failed to find shader functions in library")
                print("  Available functions: \(finalLibrary.functionNames)")
                return
            }
            
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            // Enable alpha blending for transparency
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✓ MSL Waveform render pipeline created successfully")
            } catch {
                print("ERROR: Failed to create MSL Waveform render pipeline: \(error)")
                return
            }
            
            // Create waveform texture (2D accumulation buffer)
            waveformWidth = 512
            waveformHeight = 256
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float,
                width: waveformWidth,
                height: waveformHeight,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            waveformTexture = device.makeTexture(descriptor: textureDescriptor)
            waveformTextureDescriptor = textureDescriptor
            
            // Create sampler state for texture sampling
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
            
            if samplerState == nil {
                print("WARNING: Failed to create sampler state, using default")
                samplerState = device.makeSamplerState(descriptor: MTLSamplerDescriptor())
            }
            
            guard samplerState != nil else {
                print("ERROR: Could not create sampler state")
                return
            }
            
            // Initialize waveform buffer
            waveformBuffer = Array(repeating: 0.0, count: waveformWidth * waveformHeight)
        }
        
        func updateData(
            rawAudioSamples: [Float],
            continuousWaveformData: [Float]?,
            chartHeight: CGFloat,
            availableWidth: CGFloat,
            horizontalPadding: CGFloat,
            isRegularWidth: Bool,
            opacity: Float
        ) {
            self.rawAudioSamples = rawAudioSamples
            self.continuousWaveformData = continuousWaveformData
            self.chartHeight = chartHeight
            self.availableWidth = availableWidth
            self.horizontalPadding = horizontalPadding
            self.isRegularWidth = isRegularWidth
            self.viewportSize = SIMD2<Float>(Float(availableWidth), Float(chartHeight))
            self.opacity = opacity
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }
            
            time += 0.016
            
            guard let renderPipeline = renderPipelineState,
                  let waveformTexture = waveformTexture,
                  let samplerState = samplerState else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Use continuous waveform data if available, otherwise use raw samples
            let samples = continuousWaveformData ?? rawAudioSamples
            
            if samples.isEmpty {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Update waveform texture with new audio samples
            if let computePipeline = computePipelineState {
                guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                    return
                }
                
                computeEncoder.setComputePipelineState(computePipeline)
                
                // Create buffer for samples
                guard let sampleBuffer = device.makeBuffer(
                    bytes: samples,
                    length: samples.count * MemoryLayout<Float>.stride,
                    options: []
                ) else {
                    computeEncoder.endEncoding()
                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                    return
                }
                
                var sampleCount = UInt32(samples.count)
                var timeValue = time
                var scrollPos = UInt32(scrollPosition)
                var viewport = viewportSize
                var textureWidth = UInt32(waveformWidth)
                var textureHeight = UInt32(waveformHeight)
                
                // Find max amplitude for normalization
                let maxAmplitude = samples.map { abs($0) }.max() ?? 1.0
                var maxAmp = Float(maxAmplitude)
                
                computeEncoder.setBuffer(sampleBuffer, offset: 0, index: 0)
                computeEncoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.stride, index: 1)
                computeEncoder.setBytes(&timeValue, length: MemoryLayout<Float>.stride, index: 2)
                computeEncoder.setBytes(&scrollPos, length: MemoryLayout<UInt32>.stride, index: 3)
                computeEncoder.setBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 4)
                computeEncoder.setBytes(&textureWidth, length: MemoryLayout<UInt32>.stride, index: 5)
                computeEncoder.setBytes(&textureHeight, length: MemoryLayout<UInt32>.stride, index: 6)
                computeEncoder.setBytes(&maxAmp, length: MemoryLayout<Float>.stride, index: 7)
                computeEncoder.setTexture(waveformTexture, index: 0)
                
                let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
                let threadGroups = MTLSize(
                    width: (waveformWidth + threadGroupSize.width - 1) / threadGroupSize.width,
                    height: (waveformHeight + threadGroupSize.height - 1) / threadGroupSize.height,
                    depth: 1
                )
                computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                computeEncoder.endEncoding()
                
                // Increment scroll position for scrolling effect
                scrollPosition = (scrollPosition + 1) % waveformWidth
            }
            
            // Render waveform texture
            // Configure render pass for transparency
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
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
            
            // Full screen quad vertices
            let vertices: [SIMD4<Float>] = [
                toNDC(x: 0, y: 0),                    // Bottom-left
                toNDC(x: viewWidth, y: 0),            // Bottom-right
                toNDC(x: 0, y: viewHeight),           // Top-left
                toNDC(x: viewWidth, y: viewHeight)    // Top-right
            ]
            
            // UV coordinates
            let uvs: [SIMD2<Float>] = [
                SIMD2<Float>(0.0, 1.0),  // Bottom-left
                SIMD2<Float>(1.0, 1.0),  // Bottom-right
                SIMD2<Float>(0.0, 0.0),  // Top-left
                SIMD2<Float>(1.0, 0.0)   // Top-right
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
            
            var timeValue = time
            var viewportSize = viewportSize
            var opacityValue = opacity
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTexture(waveformTexture, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.stride, index: 0)
            renderEncoder.setFragmentBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            renderEncoder.setFragmentBytes(&opacityValue, length: MemoryLayout<Float>.stride, index: 2)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

