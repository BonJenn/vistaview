#include <metal_stdlib>
using namespace metal;

struct OverlayUniforms {
    float2 outputSize;
    float2 overlaySize;
    float2 normSize;
    float2 centerNorm;
    float  rotation;
    float  opacity;
};

kernel void overlayAlphaComposite(
    texture2d<float, access::read>  baseTex       [[texture(0)]],
    texture2d<float, access::write> outTex        [[texture(1)]],
    texture2d<float, access::sample>  overlayTex    [[texture(2)]],
    constant OverlayUniforms&       uni           [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint W = outTex.get_width();
    uint H = outTex.get_height();
    if (gid.x >= W || gid.y >= H) return;

    float2 uv = float2(gid) / float2(W, H);

    float2 local = uv - uni.centerNorm;
    float c = cos(-uni.rotation);
    float s = sin(-uni.rotation);
    float2 rot;
    rot.x = local.x * c - local.y * s;
    rot.y = local.x * s + local.y * c;

    float2 halfSize = uni.normSize * 0.5;
    float2 rel = rot / halfSize;
    float2 ovUV = rel * 0.5 + 0.5;

    constexpr sampler lin(address::clamp_to_edge, filter::linear);
    float4 base = baseTex.read(gid);
    float4 src = float4(0.0);

    if (all(ovUV >= 0.0) && all(ovUV <= 1.0)) {
        src = overlayTex.sample(lin, ovUV);
        src.a *= clamp(uni.opacity, 0.0, 1.0);
    }

    float a = src.a;
    float3 rgb = src.rgb + (1.0 - a) * base.rgb;
    float outA = a + (1.0 - a) * base.a;

    outTex.write(float4(rgb, outA), gid);
}