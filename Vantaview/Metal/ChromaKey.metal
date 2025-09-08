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
    float width, height, padding;
    float bgScale, bgOffsetX, bgOffsetY, bgRotationRad, bgEnabled;
    float interactive;
    float lightWrap;
    float bgW, bgH;
    float fillMode; // 0=Contain, 1=Cover
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

inline float computeKeyness(float3 rgb, float3 keyRgb, constant ChromaKeyUniforms& u) {
    float3 yuv  = rgb2yuv(rgb);
    float3 kyuv = rgb2yuv(keyRgb);
    float2 uv   = yuv.yz;
    float2 kuv  = kyuv.yz;

    float2 uva = normalize(uv);
    float2 kuva = normalize(kuv);
    float ang = acos(clamp(dot(uva, kuva), -1.0, 1.0));
    float angN = ang / (0.5 * 3.14159265);

    float distUV = length(uv - kuv);
    float distRGB = distance(rgb, keyRgb);

    float chromaMix = mix(distRGB, distUV + angN * 0.25, saturate(u.balance));
    float satW = mix(0.6, 1.4, saturate(saturation(rgb)));
    float d = chromaMix * satW;

    float thr = mix(0.03, 0.35, saturate(u.strength));
    float halfW = max(0.001, u.softness * max(0.02, thr));
    float k = 1.0 - smoothstep(thr - halfW, thr + halfW, d);
    return clamp(k, 0.0, 1.0);
}

inline float3 despill(float3 src, float3 keyRgb, float k, constant ChromaKeyUniforms& u) {
    float spill = clamp(u.spillStrength, 0.0, 1.0);
    float desat = clamp(u.spillDesat, 0.0, 1.0);
    float bias  = clamp(u.despillBias, 0.0, 1.0);

    float edge = k * (1.0 - k) * 4.0;
    float wSpill = spill * max(edge, 0.15 * k);

    float3 kDir = normalize(keyRgb + 1e-6);
    float proj = dot(src, kDir);
    float3 removed = src - kDir * proj * wSpill;

    float lum = luminance(removed);
    removed = mix(removed, float3(lum), desat * wSpill);

    float3 compTint = normalize(float3(1.0, 1.0, 1.0) - kDir);
    removed = mix(removed, normalize(removed + compTint * 0.25), bias * wSpill);

    return clamp(removed, 0.0, 1.0);
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

    float k = computeKeyness(src.rgb, keyRgb, u);
    if (u.edgeSoftness > 0.001) {
        float r = clamp(u.edgeSoftness * (u.interactive > 0.5 ? 2.0 : 4.0), 1.0, u.interactive > 0.5 ? 4.0 : 8.0);
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

    float matte = 1.0 - k;
    float black = clamp(u.blackClip, 0.0, 1.0);
    float white = clamp(u.whiteClip, 0.0, 1.0);
    if (white < black + 1e-3) white = black + 1e-3;
    matte = clamp((matte - black) / (white - black), 0.0, 1.0);

    float3 fore = despill(src.rgb, keyRgb, k, u);

    if (u.viewMatte > 0.5) {
        float m = matte;
        outTex.write(float4(m, m, m, 1.0), gid);
        return;
    }

    // Aspect-true mapping with Contain/Cover; never stretch
    float3 bgRGB = float3(0.0);
    if (u.bgEnabled > 0.5 && u.bgW > 0.5 && u.bgH > 0.5) {
        float2 scrSize = float2(u.width, u.height);
        float2 bgSize  = float2(u.bgW,   u.bgH);

        float2 pScr = (uv - 0.5) * scrSize;

        float c = cos(-u.bgRotationRad);
        float si = sin(-u.bgRotationRad);
        float2 pRot = float2(pScr.x * c - pScr.y * si, pScr.x * si + pScr.y * c);

        float scaleX = scrSize.x / bgSize.x;
        float scaleY = scrSize.y / bgSize.y;
        float aspectScale = (u.fillMode > 0.5) ? max(scaleX, scaleY) : min(scaleX, scaleY);

        float denom = max(1e-5, aspectScale * u.bgScale);
        float2 pBgPx = pRot / denom;

        float2 buv = (pBgPx / bgSize) + 0.5 + float2(u.bgOffsetX, u.bgOffsetY) * 0.5;

        if (all(buv >= 0.0) && all(buv <= 1.0)) {
            bgRGB = bgTex.sample(s, buv).rgb;
        } else {
            bgRGB = float3(0.0);
        }
    }

    float wrap = u.lightWrap * smoothstep(0.0, 0.6, 1.0 - matte);
    float3 wrapped = clamp(fore + bgRGB * wrap, 0.0, 1.0);

    float useBG = u.bgEnabled > 0.5 ? 1.0 : 0.0;
    float3 outRGB = mix(wrapped, wrapped * matte + bgRGB * (1.0 - matte), useBG);
    float outA   = 1.0;

    outTex.write(float4(outRGB, outA), gid);
}