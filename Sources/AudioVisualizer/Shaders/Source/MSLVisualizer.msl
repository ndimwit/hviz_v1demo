#include <metal_stdlib>
using namespace metal;

/// Metal Shader Language (MSL) visualizer shader
/// Direct MSL implementation for histogram bands with enhanced effects

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

/// Vertex shader for histogram bars
vertex VertexOut mslHistogramVertex(
    device const VertexIn* vertices [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    VertexIn in = vertices[vid];
    
    // Convert to normalized device coordinates
    float2 pos = (in.position / viewportSize) * 2.0 - 1.0;
    pos.y = -pos.y; // Flip Y for Metal coordinate system
    
    out.position = float4(pos, 0.0, 1.0);
    out.magnitude = in.magnitude;
    out.frequencyIndex = in.frequencyIndex;
    out.uv = in.position / viewportSize;
    
    return out;
}

/// Fragment shader with enhanced visual effects
fragment float4 mslHistogramFragment(
    VertexOut in [[stage_in]],
    constant float& time [[buffer(0)]],
    constant float& maxMagnitude [[buffer(1)]]
) {
    // Normalize magnitude
    float normalizedMag = in.magnitude / max(maxMagnitude, 0.001);
    
    // Frequency-based color gradient
    float colorIndex = in.frequencyIndex;
    float3 baseColor = float3(
        min(1.0, colorIndex * 2.0),      // Red component
        sin(colorIndex * 3.14159) * 0.5, // Green component (sine wave)
        max(0.0, 1.0 - colorIndex * 2.0) // Blue component
    );
    
    // Add pulsing animation based on magnitude and time
    float pulse = sin(time * 3.0 + in.frequencyIndex * 10.0) * 0.15 + 0.85;
    float magnitudePulse = normalizedMag * 0.3 + 0.7;
    
    // Create gradient effect from bottom to top
    float gradient = in.uv.y;
    float3 color = baseColor * pulse * magnitudePulse;
    color += float3(0.1, 0.1, 0.2) * (1.0 - gradient); // Darker at bottom
    
    // Add glow effect for high magnitudes
    float glow = smoothstep(0.7, 1.0, normalizedMag);
    color += float3(0.3, 0.3, 0.5) * glow;
    
    return float4(color, 1.0);
}

/// Compute shader for processing audio magnitudes
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
    
    // Calculate bar position
    float xPos = float(id) * (barWidth + barSpacing) + barWidth * 0.5;
    float barHeight = normalizedMag * chartHeight;
    
    // Create vertices for the bar (two triangles forming a rectangle)
    float frequencyIndex = float(id) / float(max(count - 1u, 1u));
    
    // Bottom-left
    vertices[id * 4 + 0] = VertexIn{
        float2(xPos - barWidth * 0.5, 0.0),
        normalizedMag,
        frequencyIndex
    };
    
    // Bottom-right
    vertices[id * 4 + 1] = VertexIn{
        float2(xPos + barWidth * 0.5, 0.0),
        normalizedMag,
        frequencyIndex
    };
    
    // Top-right
    vertices[id * 4 + 2] = VertexIn{
        float2(xPos + barWidth * 0.5, barHeight),
        normalizedMag,
        frequencyIndex
    };
    
    // Top-left
    vertices[id * 4 + 3] = VertexIn{
        float2(xPos - barWidth * 0.5, barHeight),
        normalizedMag,
        frequencyIndex
    };
}

