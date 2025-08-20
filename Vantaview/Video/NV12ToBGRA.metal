#include <metal_stdlib>
using namespace metal;

struct ConvertParams {
    float3x3 yuv2rgb;
    float    yOffset;
    float    uvOffset;
    float    yScale;
    float    uvScale;
    float    toneMapEnabled;
    float    swapUV;
};

kernel void nv12ToBGRA(
    texture2d<float, access::read> lumaTexture      [[texture(0)]],
    texture2d<float, access::read> chromaTexture    [[texture(1)]],
    texture2d<float, access::write> outTexture      [[texture(2)]],
    constant ConvertParams& params                  [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float y = lumaTexture.read(gid).r;
    uint2 uvCoord = uint2(gid.x >> 1, gid.y >> 1);
    float2 uv = chromaTexture.read(uvCoord).rg;

    float u = uv.x;
    float v = uv.y;
    if (params.swapUV > 0.5) {
        float t = u; u = v; v = t;
    }

    y = clamp((y - params.yOffset) * params.yScale, 0.0, 1.0);
    u = (u - params.uvOffset) * params.uvScale;
    v = (v - params.uvOffset) * params.uvScale;

    float3 rgb = params.yuv2rgb * float3(y, u, v);

    if (params.toneMapEnabled > 0.5) {
        rgb = rgb / (1.0 + rgb);
    }

    rgb = saturate(rgb);
    outTexture.write(float4(rgb, 1.0), gid);
}