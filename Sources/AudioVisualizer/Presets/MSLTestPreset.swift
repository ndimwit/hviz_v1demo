import SwiftUI
import MetalKit
import Metal

/// Simple test preset to verify MSL shader compilation and rendering
public struct MSLTestPreset: VisualizerPreset {
    public let id = "msl_test"
    public let displayName = "MSL Test (Simple)"
    
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
        SimpleMSLTestView(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth
        )
        .frame(height: chartHeight)
    }
}

/// Simple MSL test view that renders animated gradient
private struct SimpleMSLTestView: UIViewRepresentable {
    let magnitudes: [Float]
    let maxMagnitude: Float
    let chartHeight: CGFloat
    let availableWidth: CGFloat
    
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
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        
        context.coordinator.setupMetal(device: device, view: mtkView)
        context.coordinator.updateData(magnitudes: magnitudes, maxMagnitude: maxMagnitude)
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateData(magnitudes: magnitudes, maxMagnitude: maxMagnitude)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var renderPipelineState: MTLRenderPipelineState!
        var library: MTLLibrary!
        
        var magnitudes: [Float] = []
        var maxMagnitude: Float = 1.0
        var time: Float = 0.0
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            
            // Simple animated gradient shader
            let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;
            
            struct VertexOut {
                float4 position [[position]];
                float2 uv;
            };
            
            vertex VertexOut gradientVertex(uint vid [[vertex_id]]) {
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
            
            fragment float4 gradientFragment(VertexOut in [[stage_in]],
                                            constant float& time [[buffer(0)]]) {
                // Animated gradient based on time
                float3 color1 = float3(1.0, 0.2, 0.3); // Red
                float3 color2 = float3(0.2, 0.3, 1.0); // Blue
                float t = sin(time) * 0.5 + 0.5;
                float3 color = mix(color1, color2, in.uv.x + t * 0.3);
                return float4(color, 1.0);
            }
            """
            
            do {
                library = try device.makeLibrary(source: shaderSource, options: nil)
                print("✓ MSL Test Metal library compiled successfully")
            } catch {
                print("ERROR: Failed to compile MSL test Metal library: \(error)")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "gradientVertex")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "gradientFragment")
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✓ MSL Test render pipeline created successfully")
            } catch {
                print("ERROR: Failed to create MSL test render pipeline: \(error)")
            }
        }
        
        func updateData(magnitudes: [Float], maxMagnitude: Float) {
            self.magnitudes = magnitudes
            self.maxMagnitude = maxMagnitude
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size changes
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPipeline = renderPipelineState else {
                return
            }
            
            time += 0.016
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.stride, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

