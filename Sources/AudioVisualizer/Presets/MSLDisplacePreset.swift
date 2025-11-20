import SwiftUI
import MetalKit
import Metal

/// MSL Displace visualizer preset
/// Based on FFmpeg displace filter example 2 - uses audio visualization to displace/distort the rendered bars
public struct MSLDisplacePreset: VisualizerPreset {
    public let id = "msl_displace"
    public let displayName = "MSL Displace"
    
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
        MSLDisplaceMetalView(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth,
            displacementScale: 0.15 // Default, will be updated via environment
        )
        .frame(height: chartHeight)
    }
}

/// Metal view for displace shader visualization
private struct MSLDisplaceMetalView: UIViewRepresentable {
    let magnitudes: [Float]
    let maxMagnitude: Float
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let isRegularWidth: Bool
    let displacementScale: Float
    
    @Environment(\.mslDisplaceScale) var envDisplacementScale
    
    private var effectiveDisplacementScale: Float {
        envDisplacementScale != MSLDisplaceScaleKey.defaultValue ? envDisplacementScale : displacementScale
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
        
        context.coordinator.setupMetal(device: device, view: mtkView)
        context.coordinator.updateData(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth,
            displacementScale: effectiveDisplacementScale
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
            displacementScale: effectiveDisplacementScale
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
        var displacementTexture: MTLTexture!
        var displacementTextureDescriptor: MTLTextureDescriptor!
        var samplerState: MTLSamplerState!
        
        var magnitudes: [Float] = []
        var maxMagnitude: Float = 1.0
        var chartHeight: CGFloat = 200
        var availableWidth: CGFloat = 400
        var horizontalPadding: CGFloat = 16
        var isRegularWidth: Bool = true
        var time: Float = 0.0
        var viewportSize: SIMD2<Float> = SIMD2<Float>(400, 200)
        var displacementScale: Float = 0.15
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            
            guard let commandQueue = device.makeCommandQueue() else {
                print("ERROR: Failed to create Metal command queue")
                return
            }
            self.commandQueue = commandQueue
            
            // Load shader library - try default library first
            var library: MTLLibrary?
            library = device.makeDefaultLibrary()
            
            // Check if default library has our functions, if not use embedded source
            if let defaultLib = library {
                if defaultLib.makeFunction(name: "displaceVertex") == nil ||
                   defaultLib.makeFunction(name: "displaceFragment") == nil {
                    // Functions not found in default library, use embedded source
                    library = nil
                }
            }
            
            // If default library fails or doesn't have our functions, try compiling from embedded source
            if library == nil {
                let shaderSource = """
                #include <metal_stdlib>
                using namespace metal;
                
                struct VertexOut {
                    float4 position [[position]];
                    float2 uv;
                };
                
                vertex VertexOut displaceVertex(
                    device const float4* vertices [[buffer(0)]],
                    device const float2* uvs [[buffer(1)]],
                    texture2d<float> displacementTexture [[texture(0)]],
                    constant float2& viewportSize [[buffer(2)]],
                    constant float& displacementScale [[buffer(3)]],
                    sampler textureSampler [[sampler(0)]],
                    uint vid [[vertex_id]]
                ) {
                    VertexOut out;
                    float4 originalPos = vertices[vid];
                    float2 uv = uvs[vid];
                    float displacementValue = displacementTexture.sample(textureSampler, uv).r;
                    float displacement = (displacementValue - 0.5) * 2.0;
                    float2 displacementOffset = float2(displacement, displacement) * displacementScale;
                    float2 ndcDisplacement = displacementOffset * 2.0;
                    out.position = originalPos + float4(ndcDisplacement.x, ndcDisplacement.y, 0.0, 0.0);
                    out.uv = uv;
                    return out;
                }
                
                fragment float4 displaceFragment(
                    VertexOut in [[stage_in]],
                    texture2d<float> displacementTexture [[texture(0)]],
                    constant float& time [[buffer(0)]],
                    constant float2& viewportSize [[buffer(1)]],
                    sampler textureSampler [[sampler(0)]]
                ) {
                    float3 color1 = float3(1.0, 0.2, 0.3);
                    float3 color2 = float3(0.2, 0.3, 1.0);
                    float t = sin(time) * 0.5 + 0.5;
                    float3 color = mix(color1, color2, in.uv.x + t * 0.3);
                    float displacementValue = displacementTexture.sample(textureSampler, in.uv).r;
                    float displacement = (displacementValue - 0.5) * 2.0;
                    float3 displacementTint = float3(0.1, 0.2, 0.3) * abs(displacement);
                    color = mix(color, color + displacementTint, 0.3);
                    float pulse = sin(time * 2.0 + displacement * 5.0) * 0.1 + 0.9;
                    color *= pulse;
                    return float4(color, 1.0);
                }
                
                kernel void mslGenerateDisplacementMap(
                    device const float* magnitudes [[buffer(0)]],
                    constant uint& magnitudeCount [[buffer(1)]],
                    constant float& maxMagnitude [[buffer(2)]],
                    constant float& time [[buffer(3)]],
                    constant float2& viewportSize [[buffer(4)]],
                    texture2d<float, access::write> displacementTexture [[texture(0)]],
                    uint2 gid [[thread_position_in_grid]]
                ) {
                    if (gid.x >= displacementTexture.get_width() || gid.y >= displacementTexture.get_height()) {
                        return;
                    }
                    uint width = displacementTexture.get_width();
                    uint height = displacementTexture.get_height();
                    float2 uv = float2(float(gid.x) / float(width), float(gid.y) / float(height));
                    float frequencyIndex = uv.x * float(magnitudeCount - 1);
                    uint lowerIndex = uint(floor(frequencyIndex));
                    uint upperIndex = min(lowerIndex + 1, magnitudeCount - 1);
                    float fraction = frequencyIndex - float(lowerIndex);
                    float magnitude = 0.0;
                    if (magnitudeCount > 0) {
                        float mag1 = magnitudes[lowerIndex];
                        float mag2 = magnitudes[upperIndex];
                        magnitude = mix(mag1, mag2, fraction);
                    }
                    float normalizedMag = magnitude / max(maxMagnitude, 0.001);
                    float displacementValue = 0.5;
                    float frequencyWave = sin(uv.x * 3.14159 * 8.0 + time * 2.0) * normalizedMag;
                    displacementValue += frequencyWave * 0.3;
                    float verticalWave = sin(uv.y * 3.14159 * 4.0 + time * 1.5) * normalizedMag;
                    displacementValue += verticalWave * 0.2;
                    float diagonalWave = sin((uv.x + uv.y) * 3.14159 * 6.0 + time * 2.5) * normalizedMag;
                    displacementValue += diagonalWave * 0.15;
                    displacementValue = clamp(displacementValue, 0.0, 1.0);
                    displacementTexture.write(float4(displacementValue, displacementValue, displacementValue, 1.0), gid);
                }
                """
                
                do {
                    library = try device.makeLibrary(source: shaderSource, options: nil)
                    print("✓ MSL Displace Metal library compiled from embedded source")
                } catch {
                    print("ERROR: Failed to compile Metal library from embedded source: \(error)")
                }
            }
            
            guard let finalLibrary = library else {
                print("ERROR: Failed to create Metal library for displace shader")
                return
            }
            self.library = finalLibrary
            print("✓ MSL Displace Metal library loaded successfully")
            
            // Create compute pipeline for generating displacement map
            if let computeFunction = finalLibrary.makeFunction(name: "mslGenerateDisplacementMap") {
                do {
                    computePipelineState = try device.makeComputePipelineState(function: computeFunction)
                } catch {
                    print("Failed to create compute pipeline: \(error)")
                }
            }
            
            // Create render pipeline
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            guard let vertexFunc = finalLibrary.makeFunction(name: "displaceVertex"),
                  let fragmentFunc = finalLibrary.makeFunction(name: "displaceFragment") else {
                print("ERROR: Failed to find shader functions in library")
                print("  Available functions: \(finalLibrary.functionNames)")
                return
            }
            
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✓ MSL Displace render pipeline created successfully")
            } catch {
                print("ERROR: Failed to create MSL Displace render pipeline: \(error)")
                return
            }
            
            // Create displacement texture
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: 512,
                height: 512,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            displacementTexture = device.makeTexture(descriptor: textureDescriptor)
            displacementTextureDescriptor = textureDescriptor
            
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
        }
        
        func updateData(
            magnitudes: [Float],
            maxMagnitude: Float,
            chartHeight: CGFloat,
            availableWidth: CGFloat,
            horizontalPadding: CGFloat,
            isRegularWidth: Bool,
            displacementScale: Float
        ) {
            self.magnitudes = magnitudes
            self.maxMagnitude = maxMagnitude
            self.chartHeight = chartHeight
            self.availableWidth = availableWidth
            self.horizontalPadding = horizontalPadding
            self.isRegularWidth = isRegularWidth
            self.viewportSize = SIMD2<Float>(Float(availableWidth), Float(chartHeight))
            self.displacementScale = displacementScale
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
                  let displacementTexture = displacementTexture,
                  let samplerState = samplerState else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Generate displacement map from audio magnitudes
            if let computePipeline = computePipelineState {
                guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                    return
                }
                
                computeEncoder.setComputePipelineState(computePipeline)
                
                // Create buffer for magnitudes
                let magnitudeBuffer = device.makeBuffer(
                    bytes: magnitudes,
                    length: magnitudes.count * MemoryLayout<Float>.stride,
                    options: []
                )
                
                var magCount = UInt32(magnitudes.count)
                var maxMag = maxMagnitude
                var timeValue = time
                var viewport = viewportSize
                
                computeEncoder.setBuffer(magnitudeBuffer, offset: 0, index: 0)
                computeEncoder.setBytes(&magCount, length: MemoryLayout<UInt32>.stride, index: 1)
                computeEncoder.setBytes(&maxMag, length: MemoryLayout<Float>.stride, index: 2)
                computeEncoder.setBytes(&timeValue, length: MemoryLayout<Float>.stride, index: 3)
                computeEncoder.setBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 4)
                computeEncoder.setTexture(displacementTexture, index: 0)
                
                let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
                let threadGroups = MTLSize(
                    width: (displacementTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
                    height: (displacementTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
                    depth: 1
                )
                computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                computeEncoder.endEncoding()
            }
            
            // Render with displacement - use full-screen gradient quad
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Create full-screen quad for gradient background
            let drawableSize = view.drawableSize
            let viewWidth = max(Float(drawableSize.width), 1.0)
            let viewHeight = max(Float(drawableSize.height), 1.0)
            
            func toNDC(x: Float, y: Float) -> SIMD4<Float> {
                let ndcX = (x / viewWidth) * 2.0 - 1.0
                let ndcY = 1.0 - (y / viewHeight) * 2.0
                return SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
            }
            
            // Full screen quad vertices (triangle strip)
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
            var displacementScaleValue = displacementScale
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
            renderEncoder.setVertexTexture(displacementTexture, index: 0)
            renderEncoder.setVertexSamplerState(samplerState, index: 0)
            renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            renderEncoder.setVertexBytes(&displacementScaleValue, length: MemoryLayout<Float>.stride, index: 3)
            renderEncoder.setFragmentTexture(displacementTexture, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.stride, index: 0)
            renderEncoder.setFragmentBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

