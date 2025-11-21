#include <metal_stdlib>
using namespace metal;

/// MSL Camera Edge Detection and Displacement Shaders
/// Performs real-time edge detection on camera frames and applies audio-driven displacement

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

/// Vertex shader for camera edge effects
vertex VertexOut cameraEdgeVertex(
    device const float4* vertices [[buffer(0)]],
    device const float2* uvs [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    out.position = vertices[vid];
    out.uv = uvs[vid];
    return out;
}

/// Compute shader for edge detection using Sobel operator
kernel void edgeDetectionCompute(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> edgeTexture [[texture(1)]],
    constant float& threshold [[buffer(0)]],
    constant float& sensitivity [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= edgeTexture.get_width() || gid.y >= edgeTexture.get_height()) {
        return;
    }
    
    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();
    
    // Convert to normalized coordinates
    float2 uv = float2(float(gid.x) / float(width), float(gid.y) / float(height));
    
    // Sample neighbors for Sobel operator
    // Clamp to avoid sampling outside texture bounds
    float2 texelSize = float2(1.0 / float(width), 1.0 / float(height));
    
    // Top row
    float3 topLeft = inputTexture.read(uint2(max(0, int(gid.x) - 1), max(0, int(gid.y) - 1))).rgb;
    float3 topMid = inputTexture.read(uint2(gid.x, max(0, int(gid.y) - 1))).rgb;
    float3 topRight = inputTexture.read(uint2(min(width - 1, gid.x + 1), max(0, int(gid.y) - 1))).rgb;
    
    // Middle row
    float3 midLeft = inputTexture.read(uint2(max(0, int(gid.x) - 1), gid.y)).rgb;
    float3 midRight = inputTexture.read(uint2(min(width - 1, gid.x + 1), gid.y)).rgb;
    
    // Bottom row
    float3 bottomLeft = inputTexture.read(uint2(max(0, int(gid.x) - 1), min(height - 1, gid.y + 1))).rgb;
    float3 bottomMid = inputTexture.read(uint2(gid.x, min(height - 1, gid.y + 1))).rgb;
    float3 bottomRight = inputTexture.read(uint2(min(width - 1, gid.x + 1), min(height - 1, gid.y + 1))).rgb;
    
    // Convert to grayscale (luminance)
    // Luminance formula: 0.299*R + 0.587*G + 0.114*B
    float grayTL = dot(topLeft, float3(0.299, 0.587, 0.114));
    float grayTM = dot(topMid, float3(0.299, 0.587, 0.114));
    float grayTR = dot(topRight, float3(0.299, 0.587, 0.114));
    float grayML = dot(midLeft, float3(0.299, 0.587, 0.114));
    float grayMR = dot(midRight, float3(0.299, 0.587, 0.114));
    float grayBL = dot(bottomLeft, float3(0.299, 0.587, 0.114));
    float grayBM = dot(bottomMid, float3(0.299, 0.587, 0.114));
    float grayBR = dot(bottomRight, float3(0.299, 0.587, 0.114));
    
    // Apply Sobel X kernel: [-1  0  1]
    //                      [-2  0  2]
    //                      [-1  0  1]
    float sobelX = -grayTL + grayTR - 2.0 * grayML + 2.0 * grayMR - grayBL + grayBR;
    
    // Apply Sobel Y kernel: [-1 -2 -1]
    //                      [ 0  0  0]
    //                      [ 1  2  1]
    float sobelY = -grayTL - 2.0 * grayTM - grayTR + grayBL + 2.0 * grayBM + grayBR;
    
    // Calculate edge magnitude
    float magnitude = sqrt(sobelX * sobelX + sobelY * sobelY);
    
    // Apply sensitivity multiplier
    magnitude *= sensitivity;
    
    // Normalize to [0, 1] range (assuming max magnitude is around 4.0 * sensitivity)
    magnitude = clamp(magnitude / (4.0 * max(sensitivity, 0.1)), 0.0, 1.0);
    
    // Apply threshold to create binary edge mask
    float edgeValue = step(threshold, magnitude);
    
    // Write to edge texture (single channel)
    edgeTexture.write(float4(edgeValue, edgeValue, edgeValue, 1.0), gid);
}

/// Fragment shader for waveform-based edge displacement (Version 1)
fragment float4 cameraEdgeWaveformFragment(
    VertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> edgeTexture [[texture(1)]],
    device const float* rawAudioSamples [[buffer(0)]],
    constant uint& sampleCount [[buffer(1)]],
    constant float& maxAmplitude [[buffer(2)]],
    constant float& displacementScale [[buffer(3)]],
    constant float& edgeThreshold [[buffer(4)]],
    constant float& opacity [[buffer(5)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Flip UV coordinates vertically to fix upside-down camera (without horizontal flip)
    // Vertical flip: newU = oldU, newV = 1.0 - oldV
    float2 rotatedUV = float2(in.uv.x, 1.0 - in.uv.y);
    
    // Sample edge mask
    float edgeMask = edgeTexture.sample(textureSampler, rotatedUV).r;
    
    // Check if this is an edge pixel
    if (edgeMask > edgeThreshold) {
        // Calculate direction from center (outward)
        float2 center = float2(0.5, 0.5);
        float2 direction = in.uv - center;
        float distance = length(direction);
        
        // Normalize direction
        if (distance > 0.001) {
            direction = normalize(direction);
        } else {
            direction = float2(0.0, 1.0); // Default direction if at center
        }
        
        // Map UV.x to sample index
        float sampleIndexFloat = in.uv.x * float(sampleCount - 1);
        uint sampleIndex = uint(clamp(sampleIndexFloat, 0.0, float(sampleCount - 1)));
        
        // Get waveform value
        float sampleValue = 0.0;
        if (sampleIndex < sampleCount) {
            sampleValue = rawAudioSamples[sampleIndex];
        }
        
        // Normalize amplitude
        float normalizedAmplitude = abs(sampleValue) / max(maxAmplitude, 0.001);
        normalizedAmplitude = clamp(normalizedAmplitude, 0.0, 1.0);
        
        // Calculate displacement (outward from center)
        float displacementMagnitude = normalizedAmplitude * displacementScale;
        float2 displacement = direction * displacementMagnitude;
        
        // Calculate displaced UV coordinates
        float2 displacedUV = in.uv + displacement;
        
        // Clamp to valid range
        displacedUV = clamp(displacedUV, 0.0, 1.0);
        
        // Flip displaced UV vertically to fix upside-down camera (without horizontal flip)
        float2 rotatedDisplacedUV = float2(displacedUV.x, 1.0 - displacedUV.y);
        
        // Sample camera texture at rotated displaced position
        float4 color = cameraTexture.sample(textureSampler, rotatedDisplacedUV);
        
        return float4(color.rgb, color.a * opacity);
    } else {
        // Not an edge pixel, sample camera texture normally with rotation
        float4 color = cameraTexture.sample(textureSampler, rotatedUV);
        return float4(color.rgb, color.a * opacity);
    }
}

/// Fragment shader for spectrogram-based color edge displacement (Version 2)
fragment float4 cameraEdgeColorFragment(
    VertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> edgeTexture [[texture(1)]],
    device const float* magnitudes [[buffer(0)]],
    constant uint& magnitudeCount [[buffer(1)]],
    constant float& maxMagnitude [[buffer(2)]],
    constant float& displacementScale [[buffer(3)]],
    constant float& edgeThreshold [[buffer(4)]],
    constant float& colorIntensity [[buffer(5)]],
    constant float& opacity [[buffer(6)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Flip UV coordinates vertically to fix upside-down camera (without horizontal flip)
    // Vertical flip: newU = oldU, newV = 1.0 - oldV
    float2 rotatedUV = float2(in.uv.x, 1.0 - in.uv.y);
    
    // Sample edge mask
    float edgeMask = edgeTexture.sample(textureSampler, rotatedUV).r;
    
    // Check if this is an edge pixel
    if (edgeMask > edgeThreshold) {
        // Calculate direction from center (outward)
        float2 center = float2(0.5, 0.5);
        float2 direction = in.uv - center;
        float distance = length(direction);
        
        // Normalize direction
        if (distance > 0.001) {
            direction = normalize(direction);
        } else {
            direction = float2(0.0, 1.0); // Default direction if at center
        }
        
        // Map UV.x to frequency bin index
        float binIndexFloat = in.uv.x * float(magnitudeCount - 1);
        uint binIndex = uint(clamp(binIndexFloat, 0.0, float(magnitudeCount - 1)));
        
        // Get magnitude value
        float magnitude = 0.0;
        if (binIndex < magnitudeCount) {
            magnitude = magnitudes[binIndex];
        }
        
        // Normalize magnitude
        float normalizedMag = magnitude / max(maxMagnitude, 0.001);
        normalizedMag = clamp(normalizedMag, 0.0, 1.0);
        
        // Calculate displacement (outward from center)
        float displacementMagnitude = normalizedMag * displacementScale;
        float2 displacement = direction * displacementMagnitude;
        
        // Calculate displaced UV coordinates
        float2 displacedUV = in.uv + displacement;
        
        // Clamp to valid range
        displacedUV = clamp(displacedUV, 0.0, 1.0);
        
        // Flip displaced UV vertically to fix upside-down camera (without horizontal flip)
        float2 rotatedDisplacedUV = float2(displacedUV.x, 1.0 - displacedUV.y);
        
        // Sample camera texture at rotated displaced position
        float4 cameraColor = cameraTexture.sample(textureSampler, rotatedDisplacedUV);
        
        // Map frequency bin to color based on band ranges
        float bandPosition = float(binIndex) / float(max(float(magnitudeCount - 1), 1.0)); // [0, 1]
        float3 frequencyColor;
        
        if (bandPosition < 0.33) {
            // Low bands: Red to Yellow
            float t = bandPosition / 0.33;
            frequencyColor = mix(float3(1.0, 0.0, 0.0), float3(1.0, 1.0, 0.0), t);
        } else if (bandPosition < 0.66) {
            // Mid bands: Yellow to Cyan
            float t = (bandPosition - 0.33) / 0.33;
            frequencyColor = mix(float3(1.0, 1.0, 0.0), float3(0.0, 1.0, 1.0), t);
        } else {
            // High bands: Cyan to Purple
            float t = (bandPosition - 0.66) / 0.34;
            frequencyColor = mix(float3(0.0, 1.0, 1.0), float3(1.0, 0.0, 1.0), t);
        }
        
        // Apply color intensity and mix with camera color
        float3 finalColor = mix(cameraColor.rgb, frequencyColor * colorIntensity, normalizedMag * 0.5);
        
        return float4(finalColor, cameraColor.a * opacity);
    } else {
        // Not an edge pixel, sample camera texture normally with rotation
        float4 color = cameraTexture.sample(textureSampler, rotatedUV);
        return float4(color.rgb, color.a * opacity);
    }
}

