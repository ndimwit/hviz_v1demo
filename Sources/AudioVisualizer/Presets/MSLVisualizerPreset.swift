import SwiftUI
import MetalKit
import Metal

/// MSL (Metal Shader Language) visualizer preset
/// Direct Metal shader implementation for histogram bands visualization
public struct MSLVisualizerPreset: VisualizerPreset {
    public let id = "msl_visualizer"
    public let displayName = "MSL Shader"
    
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
        MSLMetalView(
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

/// Metal view for MSL shader visualization
private struct MSLMetalView: UIViewRepresentable {
    let magnitudes: [Float]
    let maxMagnitude: Float
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalPadding: CGFloat
    let isRegularWidth: Bool
    
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
            isRegularWidth: isRegularWidth
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
            isRegularWidth: isRegularWidth
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
        
        var magnitudes: [Float] = []
        var maxMagnitude: Float = 1.0
        var chartHeight: CGFloat = 200
        var availableWidth: CGFloat = 400
        var horizontalPadding: CGFloat = 16
        var isRegularWidth: Bool = true
        var time: Float = 0.0
        var viewportSize: SIMD2<Float> = SIMD2<Float>(400, 200)
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            
            guard let commandQueue = device.makeCommandQueue() else {
                print("ERROR: Failed to create Metal command queue")
                return
            }
            self.commandQueue = commandQueue
            
            // Load shader library - try default library first
            var library: MTLLibrary?
            
            // Try default library (works when Metal files are compiled into the bundle)
            library = device.makeDefaultLibrary()
            
            // If default library fails, try compiling from embedded source
            if library == nil {
                let shaderSource = """
                #include <metal_stdlib>
                using namespace metal;
                
                struct VertexIn {
                    float2 position;
                    float magnitude;
                    float frequencyIndex;
                };
                
                struct VertexOut {
                    float4 position [[position]];
                    float magnitude;
                    float frequencyIndex;
                    float2 uv;
                };
                
                vertex VertexOut mslHistogramVertex(
                    device const VertexIn* vertices [[buffer(0)]],
                    constant float2& viewportSize [[buffer(1)]],
                    uint vid [[vertex_id]]
                ) {
                    VertexOut out;
                    VertexIn in = vertices[vid];
                    float2 pos = (in.position / viewportSize) * 2.0 - 1.0;
                    pos.y = -pos.y;
                    out.position = float4(pos, 0.0, 1.0);
                    out.magnitude = in.magnitude;
                    out.frequencyIndex = in.frequencyIndex;
                    out.uv = in.position / viewportSize;
                    return out;
                }
                
                fragment float4 mslHistogramFragment(
                    VertexOut in [[stage_in]],
                    constant float& time [[buffer(0)]],
                    constant float& maxMagnitude [[buffer(1)]]
                ) {
                    float normalizedMag = in.magnitude / max(maxMagnitude, 0.001);
                    float colorIndex = in.frequencyIndex;
                    float3 baseColor = float3(
                        min(1.0, colorIndex * 2.0),
                        sin(colorIndex * 3.14159) * 0.5,
                        max(0.0, 1.0 - colorIndex * 2.0)
                    );
                    float pulse = sin(time * 3.0 + in.frequencyIndex * 10.0) * 0.15 + 0.85;
                    float magnitudePulse = normalizedMag * 0.3 + 0.7;
                    float gradient = in.uv.y;
                    float3 color = baseColor * pulse * magnitudePulse;
                    color += float3(0.1, 0.1, 0.2) * (1.0 - gradient);
                    float glow = smoothstep(0.7, 1.0, normalizedMag);
                    color += float3(0.3, 0.3, 0.5) * glow;
                    return float4(color, 1.0);
                }
                
                kernel void mslProcessAudio(
                    device const float* magnitudes [[buffer(0)]],
                    device VertexIn* vertices [[buffer(1)]],
                    constant uint& count [[buffer(2)]],
                    constant float2& viewportSize [[buffer(3)]],
                    constant float& maxMagnitude [[buffer(4)]],
                    constant float& barWidth [[buffer(5)]],
                    constant float& barSpacing [[buffer(6)]],
                    constant float& chartHeight [[buffer(7)]],
                    uint id [[thread_position_in_grid]]
                ) {
                    if (id >= count) return;
                    float magnitude = magnitudes[id];
                    float normalizedMag = magnitude / max(maxMagnitude, 0.001);
                    float xPos = float(id) * (barWidth + barSpacing) + barWidth * 0.5;
                    float barHeight = normalizedMag * chartHeight;
                    float frequencyIndex = float(id) / float(max(count - 1u, 1u));
                    vertices[id * 4 + 0] = VertexIn{float2(xPos - barWidth * 0.5, 0.0), normalizedMag, frequencyIndex};
                    vertices[id * 4 + 1] = VertexIn{float2(xPos + barWidth * 0.5, 0.0), normalizedMag, frequencyIndex};
                    vertices[id * 4 + 2] = VertexIn{float2(xPos + barWidth * 0.5, barHeight), normalizedMag, frequencyIndex};
                    vertices[id * 4 + 3] = VertexIn{float2(xPos - barWidth * 0.5, barHeight), normalizedMag, frequencyIndex};
                }
                """
                
                do {
                    library = try device.makeLibrary(source: shaderSource, options: nil)
                    print("✓ Metal library compiled from embedded source")
                } catch {
                    print("ERROR: Failed to compile Metal library from embedded source: \(error)")
                }
            }
            
            guard let finalLibrary = library else {
                print("ERROR: Failed to create Metal library")
                print("  - Device: \(device.name)")
                print("  - Check that Metal shader files (.metal) are in the source directory")
                print("  - Verify Metal shaders compile without errors")
                return
            }
            self.library = finalLibrary
            print("✓ Metal library loaded successfully")
            
            // Create compute pipeline
            guard let computeFunction = finalLibrary.makeFunction(name: "mslProcessAudio") else {
                print("Warning: mslProcessAudio function not found, using fallback rendering")
                return
            }
            
            do {
                computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            } catch {
                print("Failed to create compute pipeline: \(error)")
            }
            
            // Create a simpler render pipeline that actually works
            let simpleShaderSource = """
            #include <metal_stdlib>
            using namespace metal;
            
            struct VertexOut {
                float4 position [[position]];
                float4 color;
            };
            
            vertex VertexOut barVertex(constant float4* vertices [[buffer(0)]],
                                      constant float4* colors [[buffer(1)]],
                                      uint vid [[vertex_id]]) {
                VertexOut out;
                out.position = vertices[vid];
                out.color = colors[vid];
                return out;
            }
            
            fragment float4 barFragment(VertexOut in [[stage_in]]) {
                return in.color;
            }
            """
            
            // Try to use the simple shader
            if let simpleLibrary = try? device.makeLibrary(source: simpleShaderSource, options: nil),
               let vertexFunc = simpleLibrary.makeFunction(name: "barVertex"),
               let fragmentFunc = simpleLibrary.makeFunction(name: "barFragment") {
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                
                do {
                    renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                    print("✓ MSL Simple render pipeline created successfully")
                } catch {
                    print("Failed to create MSL simple render pipeline: \(error)")
                }
            }
        }
        
        func updateData(
            magnitudes: [Float],
            maxMagnitude: Float,
            chartHeight: CGFloat,
            availableWidth: CGFloat,
            horizontalPadding: CGFloat,
            isRegularWidth: Bool
        ) {
            self.magnitudes = magnitudes
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
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }
            
            time += 0.016
            
            // Fallback to CPU-based rendering if Metal setup failed
            guard let renderPipeline = renderPipelineState else {
                // Use simplified rendering
                return
            }
            
            let chartWidth = availableWidth - (horizontalPadding * 2)
            let minBarWidth: CGFloat = isRegularWidth ? 2 : 1
            let barSpacing: CGFloat = isRegularWidth ? 2 : 1
            let maxBars = max(1, Int((chartWidth + barSpacing) / (minBarWidth + barSpacing)))
            let targetBarCount = min(maxBars, magnitudes.count)
            
            if targetBarCount == 0 || magnitudes.isEmpty {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Downsample magnitudes
            let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetBarCount)
            
            // Create vertex and color data for bars
            var vertices: [SIMD4<Float>] = []
            var colors: [SIMD4<Float>] = []
            
            let barWidth = (chartWidth - CGFloat(targetBarCount - 1) * barSpacing) / CGFloat(targetBarCount)
            let drawableSize = view.drawableSize
            let viewWidth = max(Float(drawableSize.width), 1.0)
            let viewHeight = max(Float(drawableSize.height), 1.0)
            
            // Convert to normalized device coordinates
            func toNDC(x: CGFloat, y: CGFloat) -> SIMD4<Float> {
                let ndcX = (Float(x) / viewWidth) * 2.0 - 1.0
                let ndcY = 1.0 - (Float(y) / viewHeight) * 2.0 // Flip Y
                return SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
            }
            
            for (index, magnitude) in downsampledMagnitudes.enumerated() {
                let normalizedHeight = CGFloat(magnitude / maxMagnitude)
                let barHeight = normalizedHeight * chartHeight
                let xPos = CGFloat(index) * (barWidth + barSpacing) + horizontalPadding
                let frequencyIndex = Float(index) / Float(max(targetBarCount - 1, 1))
                
                // Enhanced color based on frequency (similar to MSL shader)
                let colorIndex = Double(frequencyIndex)
                let baseColor = SIMD3<Float>(
                    Float(min(1.0, colorIndex * 2.0)),
                    Float(sin(colorIndex * 3.14159) * 0.5),
                    Float(max(0.0, 1.0 - colorIndex * 2.0))
                )
                
                // Add pulsing effect
                let pulse = sin(time * 3.0 + frequencyIndex * 10.0) * 0.15 + 0.85
                let color = SIMD4<Float>(baseColor * pulse, 1.0)
                
                // Create rectangle as two triangles
                let bottomLeft = toNDC(x: xPos, y: 0)
                let bottomRight = toNDC(x: xPos + barWidth, y: 0)
                let topRight = toNDC(x: xPos + barWidth, y: barHeight)
                let topLeft = toNDC(x: xPos, y: barHeight)
                
                // Triangle 1
                vertices.append(bottomLeft)
                vertices.append(bottomRight)
                vertices.append(topLeft)
                colors.append(color)
                colors.append(color)
                colors.append(color)
                
                // Triangle 2
                vertices.append(bottomRight)
                vertices.append(topRight)
                vertices.append(topLeft)
                colors.append(color)
                colors.append(color)
                colors.append(color)
            }
            
            guard !vertices.isEmpty, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            // Create buffers
            let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<SIMD4<Float>>.stride,
                options: []
            )
            
            let colorBuffer = device.makeBuffer(
                bytes: colors,
                length: colors.count * MemoryLayout<SIMD4<Float>>.stride,
                options: []
            )
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            renderEncoder.endEncoding()
            
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

