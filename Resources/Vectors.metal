#include <metal_stdlib>
using namespace metal;

struct VectorUniforms {
    float4 rect, primary, secondary, style, shape, motion, extra, globe, location, transition;
};
struct VectorVertex {
    float4 position [[position]];
    float2 source;
    float4 rect [[flat]];
    float4 color [[flat]];
    float edge;
    float width [[flat]];
    float2 screenSource;
    float4 transition [[flat]];
};
struct Segment {
    float2 a, b;
    float4 color;
    float width;
};

static float2 circlePoint(float2 center, float2 radius, float t) {
    return center + radius * float2(cos(t), sin(t));
}
static float3 globePoint(float longitude, float latitude, float rotation) {
    return float3(cos(latitude) * sin(longitude + rotation), -sin(latitude), cos(latitude) * cos(longitude + rotation));
}
static float2 terrainLong(int index, float depth, float2 size, constant VectorUniforms &u) {
    float perspective = pow(depth, 1.58);
    float energy = pow(saturate(u.motion.w), 0.72) * (0.72 + u.shape.w * 0.52);
    float phase, amplitude;
    int pattern = int(u.shape.y);
    if (pattern == 0) { phase = depth * 6.2 + float(index) * 0.43 + u.motion.z * 0.16; amplitude = 8 + energy * 24; }
    else if (pattern == 1) { phase = depth * 7.4 + float(index) * 0.43 - u.motion.z * 1.10; amplitude = 10 + energy * (18 + (sin(u.motion.z * 1.6) + 1) * 18); }
    else { phase = depth * 10 + float(index) * 0.43 - u.motion.z * 1.35; amplitude = 9 + energy * 34; }
    return float2(size.x * 0.5 + float(index) * size.x / 7.5 * perspective,
                  size.y * (0.32 + 0.68 * perspective) + sin(phase) * amplitude * (0.16 + perspective * 0.84));
}
static float2 terrainRow(float depth, float x, float2 size, constant VectorUniforms &u) {
    float perspective = pow(depth, 1.82);
    float energy = pow(saturate(u.motion.w), 0.72) * (0.72 + u.shape.w * 0.52);
    float phase, amplitude;
    int pattern = int(u.shape.y);
    if (pattern == 0) { phase = x * M_PI_F * 2.2 + depth * 6.2 + u.motion.z * 0.16; amplitude = 8 + energy * 24; }
    else if (pattern == 1) { phase = x * M_PI_F * 2.6 + depth * 7.4 - u.motion.z * 1.10; amplitude = 10 + energy * (18 + (sin(u.motion.z * 1.6) + 1) * 18); }
    else { phase = x * M_PI_F * 3 + depth * 10 - u.motion.z * 1.35; amplitude = 9 + energy * 34; }
    return float2(size.x * 0.5 + x * size.x * (0.16 + perspective * 1.18),
                  size.y * (0.32 + 0.68 * perspective) + sin(phase) * amplitude * (0.18 + perspective * 0.82));
}
static float2 lissajousPoint(float t, float echo, float2 size, float time) {
    float amplitude = 108 + sin(time * 0.19) * 7;
    float lag = echo * 0.025;
    return size * 0.5 + float2(sin(t * 3.04 + time * 0.82 - lag) * amplitude * 2.05,
                               sin(t * 4.07 + time * 0.61 + sin(time * 0.16) * 0.72 - lag) * amplitude);
}

static Segment vectorSegment(uint id, constant VectorUniforms &u,
                             constant float *history, constant float4 *targets, constant float4 *coastlines, constant float4 *radarMap) {
    float2 size = u.rect.zw, center = size * 0.5;
    float time = u.motion.x;
    Segment s = {float2(0), float2(0), u.primary, 1};
    int scene = int(u.style.x);
    if (scene == 0) {
        float radius = min(size.x, size.y) * 0.41;
        if (id < 128) {
            s.a = circlePoint(center, float2(radius), float(id) / 128 * 2 * M_PI_F);
            s.b = circlePoint(center, float2(radius), float(id + 1) / 128 * 2 * M_PI_F);
            s.width = 1.4;
        } else if ((id -= 128) < 7 * 96) {
            float latitude = (float(id / 96) * 20 - 60) * M_PI_F / 180;
            float scale = cos(latitude), t = float(id % 96) / 96 * 2 * M_PI_F;
            float2 c = center + float2(0, sin(latitude) * radius);
            s.a = circlePoint(c, float2(radius * scale, radius * 0.10 * scale), t);
            s.b = circlePoint(c, float2(radius * scale, radius * 0.10 * scale), t + 2 * M_PI_F / 96);
            s.color = u.secondary;
        } else if ((id -= 7 * 96) < 16 * 72) {
            float longitude = float(id / 72) * 2 * M_PI_F / 16 + time * 0.48;
            float t = -M_PI_F * 0.5 + float(id % 72) / 72 * M_PI_F;
            s.a = center + radius * float2(cos(t) * sin(longitude), sin(t));
            s.b = center + radius * float2(cos(t + M_PI_F / 72) * sin(longitude), sin(t + M_PI_F / 72));
            s.color = u.secondary;
            s.color.a *= cos(longitude) >= 0 ? 0.92 : 0.46;
            s.width = cos(longitude) >= 0 ? 1.05 : 0.7;
        } else if ((id -= 16 * 72) < 24) {
            float y = center.y - radius - 9 + float(id) / 24 * (2 * radius + 18);
            s.a = float2(center.x, y);
            s.b = float2(center.x, min(y + 4, center.y + radius + 9));
            s.color.a *= 0.5;
        } else if ((id -= 24) < uint(u.globe.w)) {
            float4 a = coastlines[id * 2], b = coastlines[id * 2 + 1];
            float3 pa = globePoint(a.x,a.y,time * 0.48), pb = globePoint(b.x,b.y,time * 0.48);
            s.a = center + pa.xy * radius; s.b = center + pb.xy * radius;
            bool active = (a.z == 1 && u.globe.x > 0.5) || (a.z == 2 && u.globe.y > 0.5) || (a.z == 3 && u.globe.z > 0.5);
            s.color = active ? u.primary : u.secondary;
            s.color.a *= pa.z >= 0 && pb.z >= 0 ? (active ? 1.0 : 0.88) : 0.14;
            s.width = active ? 1.7 : 1.05;
        } else {
            id -= uint(u.globe.w);
            uint marker = id / 32, part = id % 32;
            float2 coordinates[] = {u.location.xy, float2(-74.006,40.713) * M_PI_F / 180, float2(-0.128,51.507) * M_PI_F / 180, float2(139.692,35.690) * M_PI_F / 180};
            float3 p = globePoint(coordinates[marker].x,coordinates[marker].y,time * 0.48);
            float2 c = center + radius * p.xy;
            float pulse = marker == 0 ? 0.80 + (sin(time * 3.0)+1)*0.25 : 1;
            float r = (part < 16 ? 1.2 : 4.6) * pulse;
            float t = float(part % 16) / 16 * 2 * M_PI_F;
            s.a = circlePoint(c,float2(r),t); s.b = circlePoint(c,float2(r),t + 2 * M_PI_F / 16);
            s.width = part < 16 ? 2.2 : 0.9;
            bool active = marker == 0 ? u.location.z > 0.5 : (marker == 1 ? u.globe.x > 0.5 : marker == 2 ? u.globe.y > 0.5 : u.globe.z > 0.5);
            s.color = active ? u.primary : u.secondary;
            s.color.a *= part < 16 ? 1 : 0.45;
            if(p.z < 0 || (marker == 0 && !active)) s.color.a = 0;
        }
        s.a = center + (s.a - center) * u.shape.xy;
        s.b = center + (s.b - center) * u.shape.xy;
    } else if (scene == 1) {
        float radius = min(size.x, size.y) * 0.47;
        if (id < 4 * 96) {
            float r = radius * float(id / 96 + 1) / 4;
            float t = float(id % 96) / 96 * 2 * M_PI_F;
            s.a = circlePoint(center, float2(r), t); s.b = circlePoint(center, float2(r), t + 2 * M_PI_F / 96);
            s.color = u.secondary; s.color.a *= 0.35; s.width = 1.1;
        } else if ((id -= 4 * 96) < 12) {
            s.a = center; s.b = circlePoint(center, float2(radius), float(id) * M_PI_F / 6);
            s.color = u.secondary; s.color.a *= 0.35; s.width = 1.1;
        } else if ((id -= 12) < 16) {
            s.a = center; s.b = circlePoint(center, float2(radius), (u.extra.y - float(id) * 2.3) * M_PI_F / 180);
            s.color.a *= 0.25 * (1 - float(id) / 16); s.width = 2;
        } else if ((id -= 16) < uint(u.extra.z)) {
            float4 edge = radarMap[id];
            float2 mapCenter = center + float2(size.x * 0.10,0);
            s.a = mapCenter + radius * edge.xy; s.b = mapCenter + radius * edge.zw;
            bool city = id >= uint(u.extra.w);
            s.color = city ? u.secondary : u.primary; s.color.a *= city ? 1.0 : 0.92;
            s.width = city ? 1.6 : 1.2;
        } else {
            id -= uint(u.extra.z);
            uint index = id / 32, segment = id % 32;
            float4 target = targets[index];
            float mode = u.shape.z;
            float drift = mode > 2.5 ? sin(time * 0.15 + float(index)) * 15 : 0;
            float angle = (mode > 2.5 ? target.y + drift : target.w) * M_PI_F / 180;
            float2 c = mode > 2.5 ? circlePoint(center, float2(radius * target.x), angle)
                : center + float2(size.x * 0.10,0) + radius * target.xy;
            float pulse = u.shape.w > 0.5 ? 0.76 + (sin(time * 3.1 + float(index) * 0.78) + 1) * 0.25 : 1;
            float r = (2.1 + target.z * 5.6) * pulse;
            s.color.a *= 0.20 + target.z * 0.80;
            if (segment >= 16) {
                float t = float(segment - 16) / 16 * 2 * M_PI_F;
                s.a = circlePoint(c, float2(r * 1.9), t); s.b = circlePoint(c, float2(r * 1.9), t + 2 * M_PI_F / 16);
                s.width = 0.8; s.color.a *= u.shape.w > 0.5 ? 0.32 : 0;
            } else if (mode > 0.5 && mode < 1.5) {
                // Four straight diamond edges, each subdivided to match the segment count.
                float2 corners[] = {float2(0,-r),float2(r,0),float2(0,r),float2(-r,0),float2(0,-r)};
                s.a = c + mix(corners[segment / 4], corners[segment / 4 + 1], float(segment % 4) / 4);
                s.b = c + mix(corners[segment / 4], corners[segment / 4 + 1], float(segment % 4 + 1) / 4);
                s.width = 1.4;
            } else if (mode > 1.5 && mode < 2.5) {
                s.a = circlePoint(c, float2(r * 1.8), angle + M_PI_F); s.b = circlePoint(c, float2(r * 1.8), angle);
                if (segment == 1 || segment == 2) {
                    s.a = s.b;
                    s.b = s.a - r * float2(cos(angle + (segment == 1 ? -0.55 : 0.55)),sin(angle + (segment == 1 ? -0.55 : 0.55)));
                }
                s.width = 1.8; if (segment > 2) s.color.a = 0;
            } else {
                float t = float(segment) / 16 * 2 * M_PI_F;
                s.a = circlePoint(c, float2(r * 0.5), t); s.b = circlePoint(c, float2(r * 0.5), t + 2 * M_PI_F / 16);
                s.width = r; // Filled-looking contact, not a hollow ring.
            }
        }
        s.a = center + (s.a - center) * u.shape.xy;
        s.b = center + (s.b - center) * u.shape.xy;
    } else {
        uint gridCount = u.shape.x > 0.5 ? 2625 : 26;
        if (id < gridCount) {
            if (u.shape.x < 0.5) {
                if (id < 17) { float x = float(id) / 16 * size.x; s.a = float2(x,0); s.b = float2(x,size.y); }
                else { float y = float(id - 17) / 8 * size.y; s.a = float2(0,y); s.b = float2(size.x,y); }
                s.color = u.secondary; s.color.a *= 0.72; s.width = 0.8;
            } else if (id < 1344) {
                int index = int(id / 64) - 10;
                float depth = float(id % 64) / 64;
                s.a = terrainLong(index, depth, size, u); s.b = terrainLong(index, depth + 1.0 / 64, size, u);
                s.color = u.secondary; s.color.a *= 0.78; s.width = 0.9;
            } else if (id < 2624) {
                uint rowID = id - 1344;
                float travel = int(u.shape.y) == 1 ? sin(u.motion.z * 0.7) * 0.025 : u.motion.y * (int(u.shape.y) == 2 ? 0.45 : 1);
                float depth = fract(float(rowID / 80) / 16 - travel), x = float(rowID % 80) / 80 * 2 - 1;
                float perspective = pow(depth, 1.82);
                s.a = terrainRow(depth,x,size,u); s.b = terrainRow(depth,x + 2.0 / 80,size,u);
                s.color.a *= 0.38 + perspective * 0.56; s.width = 0.8 + perspective;
            } else {
                s.a = float2(0,size.y * 0.32); s.b = float2(size.x,size.y * 0.32);
                s.color = u.secondary; s.color.a *= 0.98; s.width = 1.45;
            }
        } else {
            id -= gridCount;
            if (u.shape.z > 0.5) {
                float topInset = min(size.y * 0.30, max(42.0, 13 * u.extra.x + 26));
                float height = max(0.0, min(size.y * 0.26, size.y * 0.32 - topInset));
                if (id >= 191) {
                    id -= 191;
                    float2 point = float2(float(id) / 95 * size.x, size.y * 0.32 - saturate(history[id]) * height);
                    s.a = point - float2(0.1,0); s.b = point + float2(0.1,0); s.width = 4;
                    bool isolated = (id == 0 || history[id-1] < 0) && (id == 95 || history[id+1] < 0);
                    if (history[id] < 0 || !isolated) s.color.a = 0;
                } else if (id == 95) {
                    s.a = float2(0,size.y * 0.32); s.b = float2(size.x,size.y * 0.32); s.color = u.secondary; s.width = 1.3;
                } else {
                    if (id >= 96) { id -= 96; s.width = -1; s.color.a *= 0.13; }
                    else { s.width = 1.8; }
                    s.a = float2(float(id) / 95 * size.x, size.y * 0.32 - saturate(history[id]) * height);
                    s.b = float2(float(id + 1) / 95 * size.x, size.y * 0.32 - saturate(history[id + 1]) * height);
                    if (history[id] < 0 || history[id + 1] < 0) s.color.a = 0;
                }
            } else {
                float echo = 3 - float(id / 360), t = float(id % 360) / 360 * 2 * M_PI_F;
                s.a = lissajousPoint(t,echo,size,time); s.b = lissajousPoint(t + 2 * M_PI_F / 360,echo,size,time);
                s.color.a *= echo == 0 ? 1 : 0.11 + (3 - echo) * 0.075; s.width = echo == 0 ? 1.5 : 0.8;
            }
        }
    }
    return s;
}

vertex VectorVertex consoleVectorVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                       constant VectorUniforms &u [[buffer(0)]],
                                       constant float *history [[buffer(1)]],
                                       constant float4 *targets [[buffer(2)]],
                                       constant float4 *coastlines [[buffer(3)]],
                                       constant float4 *radarMap [[buffer(4)]]) {
    Segment s = vectorSegment(id / 6,u,history,targets,coastlines,radarMap);
    bool area = s.width < 0;
    // Draw the broad glow first, then the bright center; no blur render passes.
    if (u.style.z > 0) {
        if (area && instance != 2) s.color.a = 0;
        else if (instance == 0) { s.width += 7; s.color.a *= 0.025 * u.style.z; }
        else if (instance == 1) { s.width += 3; s.color.a *= 0.06 * u.style.z; }
    }
    float2 direction = s.b - s.a;
    float length = max(0.001, metal::length(direction));
    float2 normal = float2(-direction.y, direction.x) / length;
    uint corner = id % 6;
    bool end = corner == 1 || corner == 2 || corner == 4;
    float side = corner == 0 || corner == 1 || corner == 3 ? -1 : 1;
    float edge = side * (s.width * 0.5 + 0.5);
    float2 source = (end ? s.b : s.a) + normal * edge + u.rect.xy;
    if (area) {
        source = (end ? s.b : s.a) + u.rect.xy;
        if (side > 0) source.y = u.rect.y + u.rect.w * 0.32;
        edge = 0; s.width = 0;
    }
    float2 screenSource = source;
    if(u.transition.x >= 0) {
        float progress = u.transition.x;
        bool incoming = u.transition.z > 0.5;
        if(u.transition.y < 0.5) {
            screenSource.x += u.transition.w * 960 * (incoming ? 1-progress : -progress);
        } else if(u.transition.y > 1.5) {
            float halfProgress = incoming ? saturate((progress - 0.48)/0.52) : saturate(progress/0.52);
            float scale = max(0.018,incoming ? halfProgress : 1-halfProgress);
            screenSource = (screenSource-float2(480,270)) * float2(1+(1-scale)*0.018,scale) + float2(480,270);
            screenSource.x += sin(progress*M_PI_F*15)*(1-scale)*11;
            if(incoming ? progress < 0.48 : progress >= 0.52) s.color.a = 0;
        }
    }
    float2 p = screenSource / float2(480,270) - 1;
    float2 original = p;
    float curvature = saturate(u.style.y) * 0.18;
    for (int i = 0; i < 8; ++i) {
        p.x = original.x / (1 + curvature * p.y * p.y);
        p.y = original.y / (1 + curvature * p.x * p.x);
    }
    VectorVertex v;
    v.position = float4(p * float2(1,-1),0,1);
    v.source = source; v.rect = u.rect; v.color = s.color; v.edge = edge; v.width = s.width;
    v.screenSource = screenSource; v.transition = u.transition;
    return v;
}

fragment float4 consoleVectorFragment(VectorVertex in [[stage_in]]) {
    if (any(in.source < in.rect.xy) || any(in.source > in.rect.xy + in.rect.zw)) discard_fragment();
    if(in.transition.x >= 0 && in.transition.y > 0.5 && in.transition.y < 1.5) {
        float boundary = in.transition.x * (960+94) - 94 + 94 * in.screenSource.y / 540;
        bool revealed = in.transition.w > 0 ? in.screenSource.x <= boundary : in.screenSource.x >= 960-boundary;
        if(revealed != (in.transition.z > 0.5)) discard_fragment();
    }
    float coverage = in.width == 0 ? 1 : saturate(in.width * 0.5 + 0.5 - abs(in.edge));
    float alpha = coverage * in.color.a;
    return float4(in.color.rgb * alpha, alpha);
}
