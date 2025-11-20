import SwiftUI
import MetalKit
import Metal

/// Simple test preset to verify HLSL shader compilation and rendering
public struct HLSLTestPreset: VisualizerPreset {
    public let id = "hlsl_test"
    public let displayName = "HLSL Test (Simple)"
    
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
        SimpleMetalTestView(
            magnitudes: magnitudes,
            maxMagnitude: maxMagnitude,
            chartHeight: chartHeight,
            availableWidth: availableWidth
        )
        .frame(height: chartHeight)
    }
}

/// Simple Metal test view that renders colored bars
private struct SimpleMetalTestView: UIViewRepresentable {
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
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        
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
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            
            // Simple shader source that just renders colored rectangles
            let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;
            
            struct VertexOut {
                float4 position [[position]];
                float4 color;
            };
            
            vertex VertexOut simpleVertex(uint vid [[vertex_id]]) {
                VertexOut out;
                // Create a full-screen quad
                float2 positions[4] = {
                    float2(-1.0, -1.0),  // Bottom-left
                    float2( 1.0, -1.0),  // Bottom-right
                    float2(-1.0,  1.0),  // Top-left
                    float2( 1.0,  1.0)   // Top-right
                };
                out.position = float4(positions[vid], 0.0, 1.0);
                out.color = float4(0.2, 0.6, 1.0, 1.0); // Blue color
                return out;
            }
            
            fragment float4 simpleFragment(VertexOut in [[stage_in]]) {
                return in.color;
            }
            """
            
            do {
                library = try device.makeLibrary(source: shaderSource, options: nil)
                print("✓ Test Metal library compiled successfully")
            } catch {
                print("ERROR: Failed to compile test Metal library: \(error)")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "simpleVertex")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "simpleFragment")
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✓ Test render pipeline created successfully")
            } catch {
                print("ERROR: Failed to create test render pipeline: \(error)")
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
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(renderPipeline)
            // Draw a full-screen quad (4 vertices forming 2 triangles)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

