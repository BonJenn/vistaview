#include <metal_stdlib>
using namespace metal;

kernel void nv12ToBGRA(
    texture2d<float, access::read> lumaTexture      [[texture(0)]],
    texture2d<float, access::read> chromaTexture    [[texture(1)]],
    texture2d<float, access::write> outTexture      [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float y = lumaTexture.read(gid).r; // 0..1
    uint2 uvCoord = uint2(gid.x >> 1, gid.y >> 1);
    float2 uv = chromaTexture.read(uvCoord).rg;
    
    float u = uv.x - 0.5f;
    float v = uv.y - 0.5f;
    
    // BT.709-ish conversion
    float r = saturate(y + 1.5748f * v);
    float g = saturate(y - 0.1873f * u - 0.4681f * v);
    float b = saturate(y + 1.8556f * u);
    
    outTexture.write(float4(r, g, b, 1.0), gid);
}