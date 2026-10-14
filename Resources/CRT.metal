#include <metal_stdlib>
#include "Vectors.metal"
using namespace metal;

struct CRTParameters {
    float4 color;
    float4 effects; // scanlines, noise, tracking, curvature
    float4 motion; // seconds, first thickness, second thickness, reserved
};

struct CRTVertex {
    float4 position [[position]];
    float2 uv;
};

vertex CRTVertex crtOverlayVertex(uint index [[vertex_id]]) {
    float2 uv = float2((index << 1) & 2, index & 2);
    return {float4(uv * float2(2, -2) + float2(-1, 1), 0, 1), uv};
}

static float grainHash(uint2 pixel, uint frame) {
    uint n = pixel.x * 73856093u ^ pixel.y * 19349663u ^ frame * 83492791u;
    n ^= n >> 13; n *= 1274126177u; n ^= n >> 16;
    return float(n & 0xffffffu) / 16777216.0;
}

static void over(thread float4 &result, float3 rgb, float alpha) {
    alpha = saturate(alpha);
    result = float4(rgb * alpha, alpha) + result * (1 - alpha);
}

static void trackingBand(thread float4 &result, float2 p, float y, float thickness,
                         float strength, int frame, float3 color) {
    float width = max(0.5, thickness);
    float height = max(18.0, width * 4.2);
    float delta = p.y - y;
    if (abs(delta) > height * 0.5 + 10) return;
    float phase = (delta / height + 0.5) * 3;
    if (phase >= 0 && phase < 1) over(result, float3(0), phase * 0.12 * strength);
    if (phase >= 1 && phase < 2) {
        over(result, float3(0), (2 - phase) * 0.12 * strength);
        over(result, color, (phase - 1) * 0.075 * strength);
    }
    if (phase >= 2 && phase <= 3) over(result, color, (3 - phase) * 0.075 * strength);
    over(result, color, (1 - smoothstep(width * 0.5 - 0.5, width * 0.5 + 0.5, abs(delta))) * 0.34 * strength);
    for (int i = 0; i < 13; ++i) {
        float start = float((i * 137 + frame * 29) % 900);
        float length = float(18 + (i * 23) % 96);
        float offset = float(i % 5 - 2) * max(2.5, width * 0.65);
        float coverage = saturate(max(1.0, width * 0.22) * 0.5 + 0.5 - abs(delta - offset));
        if (p.x >= start && p.x < start + length) over(result, float3(1), coverage * (0.10 + float(i % 3) * 0.035) * strength);
    }
}

fragment float4 crtOverlayFragment(CRTVertex input [[stage_in]], constant CRTParameters &u [[buffer(0)]]) {
    float2 p = input.uv * 2 - 1;
    p *= 1 + saturate(u.effects.w) * 0.18 * float2(p.y * p.y, p.x * p.x);
    if (any(abs(p) > 1)) return float4(0, 0, 0, 1);
    p = (p + 1) * float2(480, 270);
    float4 result = 0;
    if (u.effects.x > 0.001) {
        // Dark line centered on y=1 mod 4, highlight at y=2.35.
        float scan = abs(fmod(p.y - 1 + 2 + 4, 4) - 2);
        over(result, float3(0), saturate(1.075 - scan) * (0.12 + u.effects.x * 0.60));
        float highlight = abs(fmod(p.y - 2.35 + 2 + 4, 4) - 2);
        over(result, u.color.rgb, saturate(0.775 - highlight) * (0.025 + u.effects.x * 0.14));
    }
    if (u.effects.y > 0.001) {
        float grain = grainHash(uint2(p), uint(u.motion.x * 14));
        if (grain > 0.9984) over(result, grain > 0.99968 ? float3(1) : u.color.rgb, 0.035 + u.effects.y * 0.26);
    }
    if (u.effects.z > 0.5) {
        trackingBand(result, p, fmod(u.motion.x * 72, 640.0) - 50, u.motion.y, 0.78, int(u.motion.x * 9), u.color.rgb);
        trackingBand(result, p, fmod(u.motion.x * 43 + 286.2, 690.0) - 75, u.motion.z, 1, int(u.motion.x * 6) + 117, u.color.rgb);
    }
    float vignette = saturate((distance(p, float2(480, 270)) - 385) / 205) * 0.30;
    over(result, float3(0), vignette);
    return result; // Premultiplied alpha for the transparent CAMetalLayer.
}

// Output pixel -> source pixel. Keep the same map in CRTTubeGeometry for click targets.
[[ stitchable ]] float2 crtTube(float2 position, float2 size, float strength) {
    float2 p = position / size * 2.0 - 1.0;
    float amount = clamp(strength, 0.0, 1.0) * 0.18;
    float2 source = p * (1.0 + amount * float2(p.y * p.y, p.x * p.x));
    return (source + 1.0) * size * 0.5;
}
