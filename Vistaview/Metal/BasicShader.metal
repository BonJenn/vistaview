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

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> videoTexture [[texture(0)]],
                              constant BlurParams& blurData [[buffer(0)]]) {
    constexpr sampler videoSampler (mag_filter::linear, min_filter::linear);

    float blurEnabled = blurData.values.x;
    float blurAmount = blurData.values.y;

    if (blurEnabled < 0.5 || blurAmount < 0.01) {
        return videoTexture.sample(videoSampler, in.uv);
    }

    const int radius = 10;
    float sigma = 1.0 + blurAmount * 25.0;
    float strengthMultiplier = blurAmount * 5.0;

    float2 texelSize = float2(1.0 / 800.0, 1.0 / 600.0) * strengthMultiplier;

    float4 horizBlur = float4(0.0);
    float horizTotal = 0.0;

    for (int x = -radius; x <= radius; x++) {
        float offset = float(x);
        float weight = exp(-(offset * offset) / (2.0 * sigma * sigma));
        float2 sampleOffset = float2(offset * texelSize.x, 0.0);
        horizBlur += videoTexture.sample(videoSampler, in.uv + sampleOffset) * weight;
        horizTotal += weight;
    }

    horizBlur /= horizTotal;

    float4 finalColor = float4(0.0);
    float vertTotal = 0.0;

    for (int y = -radius; y <= radius; y++) {
        float offset = float(y);
        float weight = exp(-(offset * offset) / (2.0 * sigma * sigma));
        float2 sampleOffset = float2(0.0, offset * texelSize.y);
        finalColor += videoTexture.sample(videoSampler, in.uv + sampleOffset) * weight;
        vertTotal += weight;
    }

    return finalColor / vertTotal;
}
