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
/// Passes through vertices unchanged - displacement happens in fragment shader
vertex VertexOut displaceVertex(
    device const float4* vertices [[buffer(0)]],
    device const float2* uvs [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    out.position = vertices[vid];
    out.uv = uvs[vid];
    return out;
}

/// Fragment shader with displacement effect
/// Based on FFmpeg displace filter example 3 - samples from specific Y position
/// Applies color inversion to displaced pixels
fragment float4 displaceFragment(
    VertexOut in [[stage_in]],
    texture2d<float> displacementTexture [[texture(0)]],
    constant float& time [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    constant float& displacementScale [[buffer(2)]],
    constant float& opacity [[buffer(3)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample displacement map at a specific Y position (like example 3's p(X,363))
    // This creates a horizontal displacement pattern that varies with frequency
    // Using Y = 0.5 (middle of screen) as the reference line
    float2 sampleUV = float2(in.uv.x, 0.5);
    float displacementValue = displacementTexture.sample(textureSampler, sampleUV).r;
    
    // Displacement is based on difference from 0.5 (128/255 in normalized range)
    // Formula: (value - 128) / 128, which in normalized [0,1] is (value - 0.5) * 2.0
    float displacement = (displacementValue - 0.5) * 2.0; // Range: [-1, 1]
    
    // Calculate vertical rippling that increases toward top
    // Vertical position factor: 0.0 at bottom (uv.y = 0), 1.0 at top (uv.y = 1)
    float verticalFactor = in.uv.y;
    
    // Time-based smooth random rippling using multiple sine waves
    // Use X position and time for the pattern, not Y (so pattern is consistent horizontally)
    // The Y position will only affect the strength/intensity of the ripple
    float ripple1 = sin(in.uv.x * 8.0 + time * 1.5) * 0.5 + 0.5;
    float ripple2 = sin(in.uv.x * 12.0 + time * 2.1) * 0.5 + 0.5;
    float ripple3 = sin(in.uv.x * 6.0 + time * 0.8) * 0.5 + 0.5;
    
    // Combine ripples for smooth random pattern
    float ripplePattern = (ripple1 + ripple2 * 0.7 + ripple3 * 0.5) / 2.2;
    
    // Calculate vertical ripple displacement
    // Scale ripple by verticalFactor: 0.0 at bottom (uv.y = 0), full strength at top (uv.y = 1)
    // This ensures ripple is 0 at bottom and increases linearly to full at top
    float rippleAmount = (ripplePattern - 0.5) * 0.015 * verticalFactor;
    
    // Apply displacement scale and calculate offset in UV space
    // Shift upward by applying displacement to Y coordinate
    // Add ripple effect to the displacement
    float2 displacementOffset = float2(0.0, displacement + rippleAmount) * displacementScale;
    
    // Calculate displaced UV coordinates
    // This is where we sample from the background (like FFmpeg displace does)
    float2 displacedUV = in.uv + displacementOffset;
    
    // Clamp or wrap displaced UV to valid range [0, 1]
    // Using clamp for "edge=blank" behavior (FFmpeg default)
    displacedUV = clamp(displacedUV, 0.0, 1.0);
    
    // Generate animated gradient background (like MSL Test)
    // Sample the gradient at the displaced position
    float3 color1 = float3(1.0, 0.2, 0.3); // Red
    float3 color2 = float3(0.2, 0.3, 1.0); // Blue
    float t = sin(time) * 0.5 + 0.5;
    
    // Sample gradient at displaced position - this creates the displacement effect
    float3 color = mix(color1, color2, displacedUV.x + t * 0.3);
    
    // Apply color inversion to displaced pixels
    // Check if displacement occurred (displacement is not zero)
    if (abs(displacement) > 0.01) {
        // Invert the color: 1.0 - color
        color = float3(1.0, 1.0, 1.0) - color;
    }
    
    // Calculate alpha: make black pixels transparent, apply opacity
    // Black is defined as very dark colors (RGB all close to 0)
    float luminance = dot(color, float3(0.299, 0.587, 0.114)); // Standard luminance calculation
    float alpha = step(0.01, luminance); // 1.0 if not black, 0.0 if black
    
    // Apply opacity level to the entire image
    alpha *= opacity;
    
    return float4(color, alpha);
}

/// Compute shader to generate displacement map from audio magnitudes
/// Based on FFmpeg showcqt visualization used in displace examples
/// Creates a visualization that responds to audio frequencies
/// Similar to example 3 which samples from a specific Y position
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
    
    // Map X coordinate to frequency bin (like showcqt)
    // This creates a horizontal pattern that varies with frequency
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
    
    // Create displacement map based on audio visualization
    // The displacement value should be centered around 0.5 (128/255)
    // This means no displacement when value is 0.5
    // Values > 0.5 displace in positive direction, < 0.5 in negative direction
    
    // Base value centered at 0.5 (no displacement)
    float displacementValue = 0.5;
    
    // Create visualization pattern based on frequency magnitude
    // Similar to example 3, we create a pattern that varies horizontally with frequency
    // The Y position in the texture doesn't matter for the displacement value
    // since we sample from a specific Y in the fragment shader
    
    // Frequency-based pattern (horizontal variation)
    // Stronger at higher frequencies and higher magnitudes
    float frequencyPattern = sin(uv.x * 3.14159 * 4.0 + time * 2.0) * normalizedMag;
    displacementValue += frequencyPattern * 0.3;
    
    // Direct magnitude influence - creates stronger displacement for louder frequencies
    float magnitudeInfluence = normalizedMag * 0.2;
    displacementValue += magnitudeInfluence;
    
    // Add time-based animation for dynamic effect
    float timePattern = sin(time * 1.5 + uv.x * 3.14159 * 2.0) * normalizedMag * 0.15;
    displacementValue += timePattern;
    
    // Clamp to valid range [0, 1]
    // Ensure it stays centered around 0.5 for proper displacement behavior
    displacementValue = clamp(displacementValue, 0.0, 1.0);
    
    // Write to texture (same value for all channels since we use grayscale)
    displacementTexture.write(float4(displacementValue, displacementValue, displacementValue, 1.0), gid);
}

