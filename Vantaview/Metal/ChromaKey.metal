#include <metal_stdlib>
using namespace metal;

inline float3 rgb2yuv(float3 c) {
    float y = dot(c, float3(0.2126, 0.7152, 0.0722));
    float u = dot(c, float3(-0.114572, -0.385428, 0.5));
    float v = dot(c, float3(0.5, -0.454153, -0.045847));
    return float3(y, u, v);
}

struct ChromaKeyUniforms {
    float keyR, keyG, keyB;
    float strength, softness, balance;
    float matteShift, edgeSoftness;
    float blackClip, whiteClip;
    float spillStrength, spillDesat, despillBias;
    float viewMatte;
    uint  width, height, padding;
    float bgScale, bgOffsetX, bgOffsetY, bgRotationRad, bgEnabled;
};

inline float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
inline float saturation(float3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    float l = (maxc + minc) * 0.5;
    if (maxc == minc) return 0.0;
    float d = maxc - minc;
    return d / (1.0 - fabs(2.0 * l - 1.0) + 1e-5);
}

// Returns keyness k in [0..1], where 1.0 means pixel == key color
inline float computeKeyness(float3 rgb, float3 keyRgb, constant ChromaKeyUniforms& u) {
    float3 yuv = rgb2yuv(rgb);
    float3 kyuv = rgb2yuv(keyRgb);
    float2 uv = yuv.yz;
    float2 kuv = kyuv.yz;
    float distUV = distance(uv, kuv);
    float sat = saturation(rgb);
    float satWeight = mix(0.6, 1.4, saturate(sat));
    float distRGB = distance(rgb, keyRgb);
    float distMix = mix(distRGB, distUV, saturate(u.balance));
    float dist = distMix * satWeight;
    float thr = mix(0.05, 0.5, saturate(u.strength));
    float halfWidth = max(0.001, u.softness * max(0.02, thr));
    float k = 1.0 - smoothstep(thr - halfWidth, thr + halfWidth, dist);
    return saturate(k);
}

kernel void chromaKeyKernel(
    texture2d<float, access::read>     inTex  [[texture(0)]],
    texture2d<float, access::write>    outTex [[texture(1)]],
    texture2d<float, access::sample>   bgTex  [[texture(2)]],
    constant ChromaKeyUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint W = outTex.get_width();
    uint H = outTex.get_height();
    if (gid.x >= W || gid.y >= H) return;

    float2 uv = float2(gid) / float2(W, H);
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float4 src = inTex.read(gid);
    float3 keyRgb = float3(u.keyR, u.keyG, u.keyB);

    // Compute keyness then invert to matte (foreground alpha)
    float k = computeKeyness(src.rgb, keyRgb, u); // 1 = key color, 0 = not key
    // Optional edge soften by local blur of keyness
    if (u.edgeSoftness > 0.001) {
        float r = clamp(u.edgeSoftness * 4.0, 1.0, 6.0);
        int radius = int(r);
        float sum = 0.0, wsum = 0.0;
        for (int y = -radius; y <= radius; ++y) {
            for (int x = -radius; x <= radius; ++x) {
                float2 d = float2(x,y);
                float w = exp(-dot(d,d) / (2.0 * r * r));
                uint nx = uint(clamp(int(gid.x) + x, 0, int(W) - 1));
                uint ny = uint(clamp(int(gid.y) + y, 0, int(H) - 1));
                float nk = computeKeyness(inTex.read(uint2(nx,ny)).rgb, keyRgb, u);
                sum += nk * w; wsum += w;
            }
        }
        k = sum / max(1e-6, wsum);
    }
    float matte = 1.0 - k; // 1 = keep (foreground), 0 = remove (keyed background)

    // Clip matte
    float black = clamp(u.blackClip, 0.0, 1.0);
    float white = clamp(u.whiteClip, 0.0, 1.0);
    if (white < black + 1e-3) white = black + 1e-3;
    matte = clamp((matte - black) / (white - black), 0.0, 1.0);

    // Spill suppression focuses where keyness is high (near edges of key)
    float edge = k * (1.0 - k) * 4.0; // bell around 0.5
    float spill = clamp(u.spillStrength, 0.0, 1.0);
    float desat = clamp(u.spillDesat, 0.0, 1.0);
    float bias = clamp(u.despillBias, 0.0, 1.0);
    float wSpill = spill * max(edge, 0.2 * k);

    float3 kDir = normalize(keyRgb + 1e-6);
    float proj = dot(src.rgb, kDir);
    float3 spillRemoved = src.rgb - kDir * proj * wSpill;
    float lum = luminance(spillRemoved);
    spillRemoved = mix(spillRemoved, float3(lum), desat * wSpill);
    float3 compTint = normalize(float3(1.0, 1.0, 1.0) - kDir);
    spillRemoved = mix(spillRemoved, normalize(spillRemoved + compTint * 0.25), bias * wSpill);
    spillRemoved = clamp(spillRemoved, 0.0, 1.0);

    if (u.viewMatte > 0.5) {
        float m = matte;
        outTex.write(float4(m, m, m, 1.0), gid);
        return;
    }

    // Background sample (only used when bgEnabled > 0.5)
    float3 bgRGB = float3(0.0);
    if (u.bgEnabled > 0.5) {
        float2 p = uv - 0.5;
        float c = cos(-u.bgRotationRad);
        float si = sin(-u.bgRotationRad);
        float2 pr = float2(p.x * c - p.y * si, p.x * si + p.y * c);
        pr /= max(u.bgScale, 1e-5);
        pr -= float2(u.bgOffsetX, u.bgOffsetY) * 0.5;
        float2 buv = pr + 0.5;
        bgRGB = bgTex.sample(s, buv).rgb;
    }

    // If no background set, keep fully opaque output
    float useBG = u.bgEnabled > 0.5 ? 1.0 : 0.0;
    float3 outRGB = mix(spillRemoved, spillRemoved * matte + bgRGB * (1.0 - matte), useBG);
    float outA   = mix(1.0, 1.0, useBG); // always opaque output for monitors

    outTex.write(float4(outRGB, outA), gid);
}