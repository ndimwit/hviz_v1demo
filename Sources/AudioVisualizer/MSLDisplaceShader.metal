#include <metal_stdlib>
using namespace metal;

/// MSL Displace Shader
/// Based on FFmpeg displace filter example 2
/// Uses audio visualization to create displacement maps that distort the rendered bars

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

/// Vertex shader for displace effect
/// Displaces vertex positions based on the displacement map
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
    
    // Sample displacement map at this vertex's UV coordinate
    float displacementValue = displacementTexture.sample(textureSampler, uv).r;
    
    // Displacement is based on difference from 0.5 (128/255 in normalized range)
    // Values > 0.5 displace in positive direction, < 0.5 in negative direction
    float displacement = (displacementValue - 0.5) * 2.0; // Range: [-1, 1]
    
    // Apply displacement to vertex position using the adjustable scale
    float2 displacementOffset = float2(displacement, displacement) * displacementScale;
    
    // Convert displacement offset from UV space to NDC space
    float2 ndcDisplacement = displacementOffset * 2.0; // Scale to NDC range
    
    // Apply displacement to position
    out.position = originalPos + float4(ndcDisplacement.x, ndcDisplacement.y, 0.0, 0.0);
    out.uv = uv;
    
    return out;
}

/// Fragment shader with displacement effect
/// Creates animated gradient like MSL Test, but with displacement-based effects
fragment float4 displaceFragment(
    VertexOut in [[stage_in]],
    texture2d<float> displacementTexture [[texture(0)]],
    constant float& time [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Animated gradient based on time (like MSL Test)
    float3 color1 = float3(1.0, 0.2, 0.3); // Red
    float3 color2 = float3(0.2, 0.3, 1.0); // Blue
    float t = sin(time) * 0.5 + 0.5;
    float3 color = mix(color1, color2, in.uv.x + t * 0.3);
    
    // Sample displacement map for additional effects
    float displacementValue = displacementTexture.sample(textureSampler, in.uv).r;
    float displacement = (displacementValue - 0.5) * 2.0; // Range: [-1, 1]
    
    // Add subtle variation based on displacement
    float3 displacementTint = float3(0.1, 0.2, 0.3) * abs(displacement);
    color = mix(color, color + displacementTint, 0.3);
    
    // Add pulsing effect based on displacement
    float pulse = sin(time * 2.0 + displacement * 5.0) * 0.1 + 0.9;
    color *= pulse;
    
    return float4(color, 1.0);
}

/// Compute shader to generate displacement map from audio magnitudes
/// Creates a visualization similar to showcqt that can be used for displacement
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
    
    // Convert pixel position to normalized coordinates
    float2 uv = float2(float(gid.x) / float(width), float(gid.y) / float(height));
    
    // Map X coordinate to frequency bin
    float frequencyIndex = uv.x * float(magnitudeCount - 1);
    uint lowerIndex = uint(floor(frequencyIndex));
    uint upperIndex = min(lowerIndex + 1, magnitudeCount - 1);
    float fraction = frequencyIndex - float(lowerIndex);
    
    // Interpolate magnitude
    float magnitude = 0.0;
    if (magnitudeCount > 0) {
        float mag1 = magnitudes[lowerIndex];
        float mag2 = magnitudes[upperIndex];
        magnitude = mix(mag1, mag2, fraction);
    }
    
    // Normalize magnitude
    float normalizedMag = magnitude / max(maxMagnitude, 0.001);
    
    // Map Y coordinate to amplitude range
    // In waveform visualization, Y represents amplitude
    // For displacement, we want to create a pattern based on the magnitude
    float amplitude = (1.0 - uv.y) * 2.0 - 1.0; // Range: [-1, 1]
    
    // Create displacement value based on magnitude and position
    // The displacement value should be centered around 0.5 (128/255)
    // Higher magnitudes create stronger displacement patterns
    
    // Base displacement centered at 0.5
    float displacementValue = 0.5;
    
    // Create a wave pattern based on frequency (X-axis) and magnitude
    // This creates horizontal waves that vary with audio
    float frequencyWave = sin(uv.x * 3.14159 * 8.0 + time * 2.0) * normalizedMag;
    displacementValue += frequencyWave * 0.3;
    
    // Add vertical variation based on Y position and magnitude
    // Creates vertical waves that respond to audio
    float verticalWave = sin(uv.y * 3.14159 * 4.0 + time * 1.5) * normalizedMag;
    displacementValue += verticalWave * 0.2;
    
    // Add diagonal pattern for more complex displacement
    float diagonalWave = sin((uv.x + uv.y) * 3.14159 * 6.0 + time * 2.5) * normalizedMag;
    displacementValue += diagonalWave * 0.15;
    
    // Clamp to valid range [0, 1]
    displacementValue = clamp(displacementValue, 0.0, 1.0);
    
    // Write to texture
    displacementTexture.write(float4(displacementValue, displacementValue, displacementValue, 1.0), gid);
}

