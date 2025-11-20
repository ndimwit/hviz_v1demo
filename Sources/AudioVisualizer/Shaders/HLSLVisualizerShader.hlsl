// HLSL Shader for Histogram Bands Visualizer
// This is the original HLSL code that would be cross-compiled to Metal/MSL
// For reference and potential future cross-compilation tools

// HLSL equivalent of the Metal shader above
// Note: This would need to be cross-compiled using tools like SPIRV-Cross or similar

struct AudioData {
    float magnitude;
    float frequencyIndex;
    float maxMagnitude;
    float time;
};

// Compute shader for processing audio data
[numthreads(64, 1, 1)]
void ProcessAudioData(
    StructuredBuffer<float> magnitudes : register(t0),
    RWStructuredBuffer<float> barHeights : register(u0),
    uint3 id : SV_DispatchThreadID
) {
    uint index = id.x;
    if (index >= magnitudes.Length) return;
    
    float magnitude = magnitudes[index];
    float normalized = magnitude / max(maxMagnitude, 0.001f);
    barHeights[index] = normalized;
}

// Vertex shader for histogram bars
struct VertexInput {
    float2 position : POSITION;
    float magnitude : MAGNITUDE;
};

struct VertexOutput {
    float4 position : SV_POSITION;
    float magnitude : MAGNITUDE;
    float frequencyIndex : FREQUENCY;
};

VertexOutput HistogramVertex(
    VertexInput input,
    float frequencyIndex : FREQUENCY_INDEX
) {
    VertexOutput output;
    output.position = float4(input.position, 0.0, 1.0);
    output.magnitude = input.magnitude;
    output.frequencyIndex = frequencyIndex;
    return output;
}

// Pixel shader for histogram bars with frequency-based coloring
float4 RenderHistogramBar(
    VertexOutput input
) : SV_TARGET {
    // Color based on frequency (red for high, blue for low)
    float colorIndex = input.frequencyIndex;
    float3 color = float3(
        min(1.0, colorIndex * 2.0),  // Red
        0.0,                          // Green
        max(0.0, 1.0 - colorIndex * 2.0)  // Blue
    );
    
    // Add subtle animation
    float pulse = sin(time * 2.0) * 0.1 + 0.9;
    color *= pulse;
    
    return float4(color, 1.0);
}

