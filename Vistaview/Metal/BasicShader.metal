#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct BlurParams {
    float2 values;
};

vertex VertexOut vertex_main(uint vertexID [[ vertex_id ]]) {
    float2 positions[4] = {
        float2(-1.0,  1.0),
        float2(-1.0, -1.0),
        float2( 1.0,  1.0),
        float2( 1.0, -1.0)
    };

    float2 uvs[4] = {
        float2(0.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

// PERFORMANCE: Optimized fragment shader with reduced sample count and better efficiency
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> videoTexture [[texture(0)]],
                              constant BlurParams& blurData [[buffer(0)]]) {
    constexpr sampler videoSampler (mag_filter::linear, min_filter::linear);

    float blurEnabled = blurData.values.x;
    float blurAmount = blurData.values.y;

    // Early exit for no blur - saves significant GPU cycles
    if (blurEnabled < 0.5 || blurAmount < 0.01) {
        return videoTexture.sample(videoSampler, in.uv);
    }

    // PERFORMANCE: Reduced radius from 10 to 6 for 60% fewer samples while maintaining visual quality
    const int radius = 6;
    float sigma = 1.0 + blurAmount * 15.0; // Reduced from 25.0
    float strengthMultiplier = blurAmount * 3.0; // Reduced from 5.0

    // PERFORMANCE: Use more efficient texel size calculation
    float2 texelSize = float2(1.0 / float(videoTexture.get_width()), 
                             1.0 / float(videoTexture.get_height())) * strengthMultiplier;

    // PERFORMANCE: Pre-calculate common values
    float sigmaSq2 = 2.0 * sigma * sigma;
    float4 blurColor = float4(0.0);
    float totalWeight = 0.0;

    // PERFORMANCE: Single-pass blur approximation instead of separable blur
    // This trades slight quality for significant performance improvement
    for (int x = -radius; x <= radius; x++) {
        for (int y = -radius; y <= radius; y++) {
            float2 offset = float2(float(x), float(y));
            float distance = length(offset);
            
            // PERFORMANCE: Skip samples beyond circular radius to reduce sample count
            if (distance > float(radius)) continue;
            
            float weight = exp(-(distance * distance) / sigmaSq2);
            float2 sampleOffset = offset * texelSize;
            
            blurColor += videoTexture.sample(videoSampler, in.uv + sampleOffset) * weight;
            totalWeight += weight;
        }
    }

    return blurColor / totalWeight;
}

// PERFORMANCE: Add simple pass-through fragment shader for no-effect scenarios
fragment float4 fragment_passthrough(VertexOut in [[stage_in]],
                                    texture2d<float> videoTexture [[texture(0)]]) {
    constexpr sampler videoSampler (mag_filter::linear, min_filter::linear);
    return videoTexture.sample(videoSampler, in.uv);
}

// PERFORMANCE: Add efficient box blur for lower quality/higher performance scenarios
fragment float4 fragment_boxblur(VertexOut in [[stage_in]],
                                 texture2d<float> videoTexture [[texture(0)]],
                                 constant BlurParams& blurData [[buffer(0)]]) {
    constexpr sampler videoSampler (mag_filter::linear, min_filter::linear);

    float blurEnabled = blurData.values.x;
    float blurAmount = blurData.values.y;

    if (blurEnabled < 0.5 || blurAmount < 0.01) {
        return videoTexture.sample(videoSampler, in.uv);
    }

    // PERFORMANCE: Very efficient 3x3 box blur
    float2 texelSize = float2(1.0 / float(videoTexture.get_width()), 
                             1.0 / float(videoTexture.get_height())) * blurAmount;

    float4 color = float4(0.0);
    
    // 3x3 box blur - only 9 samples
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float2 sampleOffset = float2(float(x), float(y)) * texelSize;
            color += videoTexture.sample(videoSampler, in.uv + sampleOffset);
        }
    }
    
    return color / 9.0;
}