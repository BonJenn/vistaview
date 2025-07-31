#include <metal_stdlib>
using namespace metal;

// Vertex shader for output mapping
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct OutputMappingUniforms {
    float4x4 transformMatrix;
    float2 outputSize;
    float2 inputSize;
    float opacity;
    float rotation;
    float2 scale;
    float2 translation;
};

// Output mapping vertex shader
vertex VertexOut outputMappingVertex(VertexIn in [[stage_in]],
                                    constant OutputMappingUniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Apply transformation matrix
    float4 position = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transformMatrix * position;
    out.texCoord = in.texCoord;
    
    return out;
}

// Output mapping fragment shader
fragment float4 outputMappingFragment(VertexOut in [[stage_in]],
                                     texture2d<float> inputTexture [[texture(0)]],
                                     constant OutputMappingUniforms& uniforms [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Sample the input texture
    float4 color = inputTexture.sample(textureSampler, in.texCoord);
    
    // Apply opacity
    color.a *= uniforms.opacity;
    
    return color;
}

// Compute shader for output mapping transformation
kernel void outputMappingCompute(texture2d<float, access::read> inputTexture [[texture(0)]],
                                texture2d<float, access::write> outputTexture [[texture(1)]],
                                constant OutputMappingUniforms& uniforms [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    
    // Check bounds
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Normalize coordinates
    float2 outputCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Apply inverse transformation to find input coordinate
    float2 centerOffset = outputCoord - 0.5;
    
    // Apply rotation (inverse)
    float cosR = cos(-uniforms.rotation);
    float sinR = sin(-uniforms.rotation);
    float2 rotated = float2(
        centerOffset.x * cosR - centerOffset.y * sinR,
        centerOffset.x * sinR + centerOffset.y * cosR
    );
    
    // Apply scale (inverse)
    float2 scaled = rotated / uniforms.scale;
    
    // Apply translation (inverse) and convert back to texture coordinates
    float2 inputCoord = scaled + 0.5 - uniforms.translation;
    
    // Sample input texture if coordinates are valid
    float4 color = float4(0.0);
    if (inputCoord.x >= 0.0 && inputCoord.x <= 1.0 && 
        inputCoord.y >= 0.0 && inputCoord.y <= 1.0) {
        
        // Convert to pixel coordinates for sampling
        uint2 inputPixel = uint2(inputCoord * float2(inputTexture.get_width(), inputTexture.get_height()));
        
        // Clamp to texture bounds
        inputPixel = clamp(inputPixel, uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
        
        color = inputTexture.read(inputPixel);
        color.a *= uniforms.opacity;
    }
    
    // Write to output texture
    outputTexture.write(color, gid);
}

// Bilinear interpolation compute shader for better quality
kernel void outputMappingComputeBilinear(texture2d<float, access::read> inputTexture [[texture(0)]],
                                        texture2d<float, access::write> outputTexture [[texture(1)]],
                                        constant OutputMappingUniforms& uniforms [[buffer(0)]],
                                        uint2 gid [[thread_position_in_grid]]) {
    
    // Check bounds
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Normalize coordinates
    float2 outputCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Apply inverse transformation to find input coordinate
    float2 centerOffset = outputCoord - 0.5;
    
    // Apply rotation (inverse)
    float cosR = cos(-uniforms.rotation);
    float sinR = sin(-uniforms.rotation);
    float2 rotated = float2(
        centerOffset.x * cosR - centerOffset.y * sinR,
        centerOffset.x * sinR + centerOffset.y * cosR
    );
    
    // Apply scale (inverse)
    float2 scaled = rotated / uniforms.scale;
    
    // Apply translation (inverse) and convert back to texture coordinates
    float2 inputCoord = scaled + 0.5 - uniforms.translation;
    
    // Sample input texture with bilinear interpolation if coordinates are valid
    float4 color = float4(0.0);
    if (inputCoord.x >= 0.0 && inputCoord.x <= 1.0 && 
        inputCoord.y >= 0.0 && inputCoord.y <= 1.0) {
        
        // Convert to pixel coordinates
        float2 pixelCoord = inputCoord * float2(inputTexture.get_width(), inputTexture.get_height()) - 0.5;
        
        // Get integer and fractional parts
        int2 pixelInt = int2(floor(pixelCoord));
        float2 pixelFrac = pixelCoord - float2(pixelInt);
        
        // Sample four neighboring pixels
        uint inputWidth = inputTexture.get_width();
        uint inputHeight = inputTexture.get_height();
        
        int2 p00 = clamp(pixelInt, int2(0), int2(inputWidth - 1, inputHeight - 1));
        int2 p10 = clamp(pixelInt + int2(1, 0), int2(0), int2(inputWidth - 1, inputHeight - 1));
        int2 p01 = clamp(pixelInt + int2(0, 1), int2(0), int2(inputWidth - 1, inputHeight - 1));
        int2 p11 = clamp(pixelInt + int2(1, 1), int2(0), int2(inputWidth - 1, inputHeight - 1));
        
        float4 c00 = inputTexture.read(uint2(p00));
        float4 c10 = inputTexture.read(uint2(p10));
        float4 c01 = inputTexture.read(uint2(p01));
        float4 c11 = inputTexture.read(uint2(p11));
        
        // Bilinear interpolation
        float4 c0 = mix(c00, c10, pixelFrac.x);
        float4 c1 = mix(c01, c11, pixelFrac.x);
        color = mix(c0, c1, pixelFrac.y);
        
        color.a *= uniforms.opacity;
    }
    
    // Write to output texture
    outputTexture.write(color, gid);
}

// Edge detection for snapping guidelines
kernel void edgeDetectionCompute(texture2d<float, access::read> inputTexture [[texture(0)]],
                                texture2d<float, access::write> outputTexture [[texture(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Sobel edge detection
    float3x3 sobelX = float3x3(-1, 0, 1,
                               -2, 0, 2,
                               -1, 0, 1);
    
    float3x3 sobelY = float3x3(-1, -2, -1,
                                0,  0,  0,
                                1,  2,  1);
    
    float gradX = 0.0;
    float gradY = 0.0;
    
    // Apply Sobel operators
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            int2 samplePos = clamp(int2(gid) + int2(x, y), 
                                  int2(0), 
                                  int2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
            
            float4 sample = inputTexture.read(uint2(samplePos));
            float luminance = dot(sample.rgb, float3(0.299, 0.587, 0.114));
            
            gradX += luminance * sobelX[y + 1][x + 1];
            gradY += luminance * sobelY[y + 1][x + 1];
        }
    }
    
    float magnitude = sqrt(gradX * gradX + gradY * gradY);
    float4 edgeColor = float4(magnitude, magnitude, magnitude, 1.0);
    
    outputTexture.write(edgeColor, gid);
}