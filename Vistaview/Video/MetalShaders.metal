#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 texCoord;
};

struct ScaleUniforms {
    float2 scale;
};

vertex VSOut textured_vertex_scaled(uint vid [[vertex_id]],
                                    constant ScaleUniforms& u [[buffer(0)]]) {
    VSOut out;
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 tex[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    float2 p = positions[vid] * u.scale;
    out.position = float4(p, 0.0, 1.0);
    out.texCoord = tex[vid];
    return out;
}

fragment float4 textured_fragment(VSOut in [[stage_in]],
                                  texture2d<float> colorTex [[texture(0)]],
                                  sampler s [[sampler(0)]]) {
    return colorTex.sample(s, in.texCoord);
}