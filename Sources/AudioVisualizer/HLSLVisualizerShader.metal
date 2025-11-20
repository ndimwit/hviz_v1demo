#include <metal_stdlib>
using namespace metal;

/// Metal shader equivalent of HLSL histogram bands visualizer
/// This shader processes audio magnitude data and renders histogram bars
/// Original HLSL concept converted to MSL for Apple platforms

struct AudioData {
    float magnitude;
    float frequencyIndex;
    float maxMagnitude;
    float time;
};

/// Compute shader for processing audio data into bar heights
kernel void processAudioData(
    device const float* magnitudes [[buffer(0)]],
    device float* barHeights [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    constant float& maxMagnitude [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) return;
    
    float magnitude = magnitudes[id];
    float normalized = magnitude / max(maxMagnitude, 0.001);
    barHeights[id] = normalized;
}

/// Fragment shader for rendering histogram bars with frequency-based coloring
fragment float4 renderHistogramBar(
    float4 position [[position]],
    constant float& barHeight [[buffer(0)]],
    constant float& frequencyIndex [[buffer(1)]],
    constant float& time [[buffer(2)]]
) {
    // Color based on frequency (similar to HistogramBandsPreset)
    // Red for high frequencies, blue for low frequencies
    float colorIndex = frequencyIndex;
    float3 color = float3(
        min(1.0, colorIndex * 2.0),  // Red component
        0.0,                          // Green component
        max(0.0, 1.0 - colorIndex * 2.0)  // Blue component
    );
    
    // Add subtle animation based on time
    float pulse = sin(time * 2.0) * 0.1 + 0.9;
    color *= pulse;
    
    return float4(color, 1.0);
}

/// Vertex shader for histogram bar rendering
struct VertexIn {
    float2 position;
    float magnitude;
};

struct VertexOut {
    float4 position [[position]];
    float magnitude;
    float frequencyIndex;
};

vertex VertexOut histogramVertex(
    device const VertexIn* vertices [[buffer(0)]],
    constant float& frequencyIndex [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.magnitude = vertices[vid].magnitude;
    out.frequencyIndex = frequencyIndex;
    return out;
}

