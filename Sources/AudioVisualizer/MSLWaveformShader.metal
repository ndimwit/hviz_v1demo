#include <metal_stdlib>
using namespace metal;

/// MSL Waveform Shader
/// Based on FFmpeg waveform filter - luminance mode
/// Displays audio waveform as a 2D visualization:
/// - X-axis: time
/// - Y-axis: amplitude
/// - Intensity: frequency of occurrence (luminance)

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

/// Vertex shader for waveform display
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

/// Fragment shader for waveform rendering
/// Renders the accumulated waveform texture with luminance-based coloring
fragment float4 waveformFragment(
    VertexOut in [[stage_in]],
    texture2d<float> waveformTexture [[texture(0)]],
    constant float& time [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    constant float& opacity [[buffer(2)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample the waveform texture
    // The texture contains accumulated amplitude values
    float waveformValue = waveformTexture.sample(textureSampler, in.uv).r;
    
    // Normalize and apply gamma correction for better visualization
    float normalized = pow(waveformValue, 0.5); // Gamma correction
    
    // Create luminance-based color (similar to FFmpeg waveform filter)
    // Higher values = brighter (white/yellow), lower values = darker (black/blue)
    float3 color;
    
    if (normalized > 0.8) {
        // High intensity: white/yellow
        color = float3(1.0, 1.0, 0.8);
    } else if (normalized > 0.5) {
        // Medium-high: yellow/cyan
        float t = (normalized - 0.5) / 0.3;
        color = mix(float3(0.0, 1.0, 1.0), float3(1.0, 1.0, 0.8), t);
    } else if (normalized > 0.2) {
        // Medium: cyan/blue
        float t = (normalized - 0.2) / 0.3;
        color = mix(float3(0.0, 0.5, 1.0), float3(0.0, 1.0, 1.0), t);
    } else {
        // Low: dark blue/black
        float t = normalized / 0.2;
        color = mix(float3(0.0, 0.0, 0.1), float3(0.0, 0.5, 1.0), t);
    }
    
    // Apply intensity scaling
    color *= normalized;
    
    // Add subtle time-based animation for visual interest
    float pulse = sin(time * 0.5) * 0.05 + 0.95;
    color *= pulse;
    
    // Calculate alpha: make black pixels transparent, apply opacity
    // Black is defined as very dark colors (RGB all close to 0)
    float luminance = dot(color, float3(0.299, 0.587, 0.114)); // Standard luminance calculation
    float alpha = step(0.01, luminance); // 1.0 if not black, 0.0 if black
    
    // Apply opacity level to the entire image
    alpha *= opacity;
    
    return float4(color, alpha);
}

/// Compute shader to generate waveform texture
/// Accumulates audio samples into a 2D texture where:
/// - X-axis represents time (sample index)
/// - Y-axis represents amplitude (normalized sample value)
/// - Accumulated values represent frequency of occurrence
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
    
    // Get current pixel value (for accumulation)
    float currentValue = waveformTexture.read(gid).r;
    
    // Decay old values (simulates scrolling effect)
    float decay = 0.98; // Adjust this to control persistence
    currentValue *= decay;
    
    // Map texture X coordinate to sample index
    // The texture scrolls, so we need to account for scroll position
    int textureX = int(gid.x);
    int scrollOffset = int(scrollPosition);
    
    // Calculate which sample this pixel represents
    // We map the texture width to the number of samples
    float sampleIndexFloat = (float(textureX) / float(textureWidth)) * float(sampleCount);
    int sampleIndex = int(sampleIndexFloat);
    
    if (sampleIndex >= 0 && sampleIndex < int(sampleCount)) {
        // Get sample value
        float sampleValue = samples[sampleIndex];
        
        // Normalize amplitude to [-1, 1] range
        float normalizedAmplitude = sampleValue / max(maxAmplitude, 0.001);
        normalizedAmplitude = clamp(normalizedAmplitude, -1.0, 1.0);
        
        // Map texture Y coordinate to amplitude range
        // Y=0 (top) = +1.0, Y=height (bottom) = -1.0
        float amplitudeRange = 2.0; // From -1.0 to +1.0
        float textureYNormalized = 1.0 - (float(gid.y) / float(textureHeight)); // Flip Y
        float amplitudeAtY = (textureYNormalized * amplitudeRange) - 1.0; // Range: [-1, 1]
        
        // Check if this pixel corresponds to the current sample's amplitude
        // We accumulate values when the amplitude matches (within a threshold)
        float amplitudeThreshold = 1.0 / float(textureHeight); // One pixel worth of amplitude
        
        if (abs(normalizedAmplitude - amplitudeAtY) < amplitudeThreshold) {
            // This pixel represents the current sample's amplitude
            // Accumulate the value (increment intensity)
            currentValue += 0.1; // Increment intensity
        }
    }
    
    // Clamp accumulated value
    currentValue = clamp(currentValue, 0.0, 1.0);
    
    // Write back to texture
    waveformTexture.write(float4(currentValue, currentValue, currentValue, 1.0), gid);
}

