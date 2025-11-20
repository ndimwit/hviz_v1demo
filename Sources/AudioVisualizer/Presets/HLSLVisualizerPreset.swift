import SwiftUI
import MetalKit
import Metal

/// HLSL-based visualizer preset with blur & echo effect
/// This preset demonstrates HLSL shader concepts implemented in Metal with downward blur/echo and color transformation
public struct HLSLVisualizerPreset: VisualizerPreset {
    public let id = "hlsl_visualizer"
    public let displayName = "HLSL Blur Echo"
    
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
        MetalHistogramView(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            isRegularWidth: isRegularWidth
        )
        .frame(height: chartHeight)
    }
}

/// Metal view wrapper for HLSL-style histogram visualization with blur/echo
private struct MetalHistogramView: UIViewRepresentable {
    let magnitudes: [Float]
    let maxMagnitude: Float
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let isRegularWidth: Bool
    
    @Environment(\.blurIntensity) var blurIntensity
    @Environment(\.echoIntensity) var echoIntensity
    @Environment(\.colorTransformIntensity) var colorTransformIntensity
    
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
            blurIntensity: blurIntensity,
            echoIntensity: echoIntensity,
            colorTransformIntensity: colorTransformIntensity
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
            blurIntensity: blurIntensity,
            echoIntensity: echoIntensity,
            colorTransformIntensity: colorTransformIntensity
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var histogramRenderPipelineState: MTLRenderPipelineState!
        var blurEchoRenderPipelineState: MTLRenderPipelineState!
        var library: MTLLibrary!
        
        // Feedback textures for echo effect (double buffering)
        var feedbackTexture1: MTLTexture!
        var feedbackTexture2: MTLTexture!
        var currentFeedbackTexture: MTLTexture?
        var nextFeedbackTexture: MTLTexture?
        var intermediateTexture: MTLTexture!
        var samplerState: MTLSamplerState!
        
        var magnitudes: [Float] = []
        var maxMagnitude: Float = 1.0
        var chartHeight: CGFloat = 200
        var availableWidth: CGFloat = 400
        var horizontalPadding: CGFloat = 16
        var isRegularWidth: Bool = true
        var time: Float = 0.0
        var blurIntensity: Float = 0.5
        var echoIntensity: Float = 0.5
        var colorTransformIntensity: Float = 0.3
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            
            guard let commandQueue = device.makeCommandQueue() else {
                print("ERROR: Failed to create Metal command queue")
                return
            }
            self.commandQueue = commandQueue
            
            // Create shader library with blur/echo shaders
            let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;
            
            struct VertexOut {
                float4 position [[position]];
                float2 uv;
            };
            
            // Vertex shader for full-screen quad
            vertex VertexOut fullScreenVertex(uint vid [[vertex_id]]) {
                VertexOut out;
                float2 positions[4] = {
                    float2(-1.0, -1.0),
                    float2( 1.0, -1.0),
                    float2(-1.0,  1.0),
                    float2( 1.0,  1.0)
                };
                float2 uvs[4] = {
                    float2(0.0, 1.0),
                    float2(1.0, 1.0),
                    float2(0.0, 0.0),
                    float2(1.0, 0.0)
                };
                out.position = float4(positions[vid], 0.0, 1.0);
                out.uv = uvs[vid];
                return out;
            }
            
            // Simple vertex shader for bars
            struct BarVertexOut {
                float4 position [[position]];
                float4 color;
            };
            
            vertex BarVertexOut barVertex(constant float4* vertices [[buffer(0)]],
                                         constant float4* colors [[buffer(1)]],
                                         uint vid [[vertex_id]]) {
                BarVertexOut out;
                out.position = vertices[vid];
                out.color = colors[vid];
                return out;
            }
            
            fragment float4 barFragment(BarVertexOut in [[stage_in]]) {
                return in.color;
            }
            
            // Fragment shader for blur/echo effect with color transformation
            fragment float4 blurEchoFragment(VertexOut in [[stage_in]],
                                            texture2d<float> currentFrame [[texture(0)]],
                                            texture2d<float> feedbackTexture [[texture(1)]],
                                            constant float& blurIntensity [[buffer(0)]],
                                            constant float& echoIntensity [[buffer(1)]],
                                            constant float& colorTransformIntensity [[buffer(2)]],
                                            constant float2& textureSize [[buffer(3)]],
                                            sampler textureSampler [[sampler(0)]]) {
                float2 uv = in.uv;
                
                // Sample current frame
                float4 current = currentFrame.sample(textureSampler, uv);
                
                // Calculate downward stretch offset (sample from above to stretch down)
                // blurIntensity controls how much we stretch (0.0 = no stretch, 1.0 = maximum stretch)
                float stretchAmount = blurIntensity * 0.1; // Maximum 10% of texture height
                
                // Sample from feedback texture at position above current pixel (stretching downward)
                float2 feedbackUV = uv;
                feedbackUV.y = clamp(uv.y - stretchAmount, 0.0, 1.0);
                
                // Sample multiple points for blur effect (vertical blur)
                float4 smeared = float4(0.0);
                int blurSamples = 5;
                float blurStep = blurIntensity * 0.02;
                float totalWeight = 0.0;
                
                for (int i = 0; i < blurSamples; i++) {
                    float2 sampleUV = feedbackUV;
                    float offset = (float(i) - float(blurSamples) * 0.5) * blurStep;
                    sampleUV.y = clamp(feedbackUV.y + offset, 0.0, 1.0);
                    
                    float4 sample = feedbackTexture.sample(textureSampler, sampleUV);
                    
                    // Apply accumulated color transformation to feedback (increases over layers)
                    float3 sampleColor = sample.rgb;
                    
                    // Darken (accumulated - stronger for older layers)
                    float darkenAmount = colorTransformIntensity * 0.3;
                    sampleColor *= (1.0 - darkenAmount);
                    
                    // Invert (accumulated)
                    float3 inverted = 1.0 - sampleColor;
                    sampleColor = mix(sampleColor, inverted, colorTransformIntensity * 0.4);
                    
                    // Weight by distance from center (gaussian-like)
                    float weight = 1.0 - abs(offset) / (blurStep * float(blurSamples) * 0.5);
                    weight = max(0.0, weight);
                    
                    smeared += float4(sampleColor, sample.a) * weight;
                    totalWeight += weight;
                }
                
                if (totalWeight > 0.0) {
                    smeared /= totalWeight;
                }
                
                // Apply opacity to smeared content for perceptual layering
                float smearedOpacity = echoIntensity * 0.85; // Max 85% opacity for layering
                
                // Blend: current frame on top, smeared feedback behind
                // Standard alpha blending: result = foreground + background * (1 - foreground.a)
                float4 result;
                
                // If current frame has content, blend it on top
                if (current.a > 0.01) {
                    // Current frame is foreground, smeared is background
                    result.rgb = current.rgb * current.a + smeared.rgb * (1.0 - current.a) * smearedOpacity;
                    result.a = current.a + smeared.a * (1.0 - current.a) * smearedOpacity;
                } else {
                    // No current content, use smeared content to fill background
                    result.rgb = smeared.rgb;
                    result.a = smeared.a * smearedOpacity;
                }
                
                return result;
            }
            """
            
            do {
                library = try device.makeLibrary(source: shaderSource, options: nil)
                print("✓ HLSL Blur Echo Metal library compiled successfully")
            } catch {
                print("ERROR: Failed to compile Metal library: \(error)")
                return
            }
            
            // Create histogram render pipeline (renders bars to texture)
            if let vertexFunc = library.makeFunction(name: "barVertex"),
               let fragmentFunc = library.makeFunction(name: "barFragment") {
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                
                do {
                    histogramRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                    print("✓ Histogram render pipeline created")
                } catch {
                    print("ERROR: Failed to create histogram render pipeline: \(error)")
                }
            }
            
            // Create blur/echo render pipeline
            if let vertexFunc = library.makeFunction(name: "fullScreenVertex"),
               let fragmentFunc = library.makeFunction(name: "blurEchoFragment") {
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                
                do {
                    blurEchoRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                    print("✓ Blur/Echo render pipeline created")
                } catch {
                    print("ERROR: Failed to create blur/echo render pipeline: \(error)")
                }
            }
            
            // Create sampler state
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
            
            // Initialize feedback textures (will be resized in draw)
        }
        
        func updateData(
            magnitudes: [Float],
            maxMagnitude: Float,
            chartHeight: CGFloat,
            availableWidth: CGFloat,
            horizontalPadding: CGFloat,
            isRegularWidth: Bool,
            blurIntensity: Float,
            echoIntensity: Float,
            colorTransformIntensity: Float
        ) {
            self.magnitudes = magnitudes
            self.maxMagnitude = maxMagnitude
            self.chartHeight = chartHeight
            self.availableWidth = availableWidth
            self.horizontalPadding = horizontalPadding
            self.isRegularWidth = isRegularWidth
            self.blurIntensity = blurIntensity
            self.echoIntensity = echoIntensity
            self.colorTransformIntensity = colorTransformIntensity
        }
        
        func ensureTextures(size: CGSize) {
            let width = Int(size.width)
            let height = Int(size.height)
            
            if feedbackTexture1 == nil || feedbackTexture1.width != width || feedbackTexture1.height != height {
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                
                feedbackTexture1 = device.makeTexture(descriptor: textureDescriptor)
                feedbackTexture2 = device.makeTexture(descriptor: textureDescriptor)
                intermediateTexture = device.makeTexture(descriptor: textureDescriptor)
                
                currentFeedbackTexture = feedbackTexture1
                nextFeedbackTexture = feedbackTexture2
                
                // Textures will be cleared on first render pass
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Textures will be recreated in draw if size changes
            feedbackTexture1 = nil
            feedbackTexture2 = nil
            intermediateTexture = nil
            currentFeedbackTexture = nil
            nextFeedbackTexture = nil
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let histogramPipeline = histogramRenderPipelineState,
                  let blurEchoPipeline = blurEchoRenderPipelineState,
                  let samplerState = samplerState else {
                return
            }
            
            time += 0.016
            
            let drawableSize = view.drawableSize
            ensureTextures(size: drawableSize)
            
            guard let intermediateTexture = intermediateTexture,
                  let currentFeedbackTexture = currentFeedbackTexture,
                  let nextFeedbackTexture = nextFeedbackTexture else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            guard !magnitudes.isEmpty else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // PASS 1: Render histogram bars to intermediate texture
            let intermediateRenderPass = MTLRenderPassDescriptor()
            intermediateRenderPass.colorAttachments[0].texture = intermediateTexture
            intermediateRenderPass.colorAttachments[0].loadAction = .clear
            intermediateRenderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            intermediateRenderPass.colorAttachments[0].storeAction = .store
            
            guard let histogramEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: intermediateRenderPass) else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Render histogram bars
            let chartWidth = availableWidth - (horizontalPadding * 2)
            let minBarWidth: CGFloat = isRegularWidth ? 2 : 1
            let barSpacing: CGFloat = isRegularWidth ? 2 : 1
            let maxBars = max(1, Int((chartWidth + barSpacing) / (minBarWidth + barSpacing)))
            let targetBarCount = min(maxBars, magnitudes.count)
            
            let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetBarCount)
            let barWidth = (chartWidth - CGFloat(targetBarCount - 1) * barSpacing) / CGFloat(targetBarCount)
            let viewWidth = max(Float(drawableSize.width), 1.0)
            let viewHeight = max(Float(drawableSize.height), 1.0)
            
            func toNDC(x: CGFloat, y: CGFloat) -> SIMD4<Float> {
                let ndcX = (Float(x) / viewWidth) * 2.0 - 1.0
                let ndcY = 1.0 - (Float(y) / viewHeight) * 2.0
                return SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
            }
            
            histogramEncoder.setRenderPipelineState(histogramPipeline)
            
            for (index, magnitude) in downsampledMagnitudes.enumerated() {
                let normalizedHeight = CGFloat(magnitude / maxMagnitude)
                let barHeight = normalizedHeight * chartHeight
                let xPos = CGFloat(index) * (barWidth + barSpacing) + horizontalPadding
                let frequencyIndex = Float(index) / Float(max(targetBarCount - 1, 1))
                
                let colorIndex = Double(frequencyIndex)
                var color = SIMD4<Float>(
                    Float(min(1.0, colorIndex * 2.0)),
                    0.0,
                    Float(max(0.0, 1.0 - colorIndex * 2.0)),
                    1.0
                )
                
                // Create rectangle as two triangles
                let bottomLeft = toNDC(x: xPos, y: 0)
                let bottomRight = toNDC(x: xPos + barWidth, y: 0)
                let topRight = toNDC(x: xPos + barWidth, y: barHeight)
                let topLeft = toNDC(x: xPos, y: barHeight)
                
                let vertices: [SIMD4<Float>] = [
                    bottomLeft, bottomRight, topLeft,
                    bottomRight, topRight, topLeft
                ]
                
                guard let vertexBuffer = device.makeBuffer(
                    bytes: vertices,
                    length: vertices.count * MemoryLayout<SIMD4<Float>>.stride,
                    options: []
                ) else { continue }
                
                guard let colorBuffer = device.makeBuffer(
                    bytes: [color, color, color, color, color, color],
                    length: 6 * MemoryLayout<SIMD4<Float>>.stride,
                    options: []
                ) else { continue }
                
                histogramEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                histogramEncoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
                histogramEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            
            histogramEncoder.endEncoding()
            
            // PASS 2: Apply blur/echo effect and render to screen + update feedback texture
            // First render to screen
            guard let blurEchoEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Full-screen quad vertices
            let quadVertices: [SIMD4<Float>] = [
                SIMD4<Float>(-1.0, -1.0, 0.0, 1.0),
                SIMD4<Float>( 1.0, -1.0, 0.0, 1.0),
                SIMD4<Float>(-1.0,  1.0, 0.0, 1.0),
                SIMD4<Float>( 1.0,  1.0, 0.0, 1.0)
            ]
            
            guard let quadVertexBuffer = device.makeBuffer(
                bytes: quadVertices,
                length: quadVertices.count * MemoryLayout<SIMD4<Float>>.stride,
                options: []
            ) else {
                blurEchoEncoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            var blurInt = blurIntensity
            var echoInt = echoIntensity
            var colorTransformInt = colorTransformIntensity
            var textureSize = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
            
            blurEchoEncoder.setRenderPipelineState(blurEchoPipeline)
            blurEchoEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            blurEchoEncoder.setFragmentTexture(intermediateTexture, index: 0)
            blurEchoEncoder.setFragmentTexture(currentFeedbackTexture, index: 1)
            blurEchoEncoder.setFragmentSamplerState(samplerState, index: 0)
            blurEchoEncoder.setFragmentBytes(&blurInt, length: MemoryLayout<Float>.stride, index: 0)
            blurEchoEncoder.setFragmentBytes(&echoInt, length: MemoryLayout<Float>.stride, index: 1)
            blurEchoEncoder.setFragmentBytes(&colorTransformInt, length: MemoryLayout<Float>.stride, index: 2)
            blurEchoEncoder.setFragmentBytes(&textureSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 3)
            blurEchoEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            blurEchoEncoder.endEncoding()
            
            // Copy result to feedback texture for next frame
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(
                    from: drawable.texture,
                    sourceSlice: 0,
                    sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: Int(drawableSize.width), height: Int(drawableSize.height), depth: 1),
                    to: nextFeedbackTexture,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blitEncoder.endEncoding()
            }
            
            // Swap feedback textures
            let temp = self.currentFeedbackTexture
            self.currentFeedbackTexture = self.nextFeedbackTexture
            self.nextFeedbackTexture = temp
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func downsampleMagnitudes(_ magnitudes: [Float], to targetCount: Int) -> [Float] {
            guard !magnitudes.isEmpty && targetCount > 0 else {
                return magnitudes
            }
            
            if magnitudes.count <= targetCount {
                return magnitudes
            }
            
            var result = [Float]()
            let step = Double(magnitudes.count - 1) / Double(targetCount - 1)
            
            for i in 0..<targetCount {
                let position = Double(i) * step
                let lowerIndex = Int(position)
                let upperIndex = min(lowerIndex + 1, magnitudes.count - 1)
                let fraction = position - Double(lowerIndex)
                
                let interpolated = Float(Double(magnitudes[lowerIndex]) * (1.0 - fraction) + Double(magnitudes[upperIndex]) * fraction)
                result.append(interpolated)
            }
            
            return result
        }
    }
}
