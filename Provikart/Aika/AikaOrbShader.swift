//
//  AikaOrbShader.swift
//  Provikart
//
//  Shader koule AIKA – převod webového WebGL shaderu (provikart.cz/assets/aika/orb.js) do Metalu.
//  Kompiluje se až za běhu (MTLDevice.makeLibrary(source:)), takže sestavení nepotřebuje Metal Toolchain.
//

enum AikaOrbShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// extra: x = síla záře (0 = bez záře), y = přiblížení (<1 = větší koule), z = rychlost otáčení
struct AikaUniforms { float4 a; float4 b; float4 c; float4 params; float4 size; float4 extra; };
struct VOut { float4 position [[position]]; };

vertex VOut aika_vertex(uint vid [[vertex_id]]) {
    float2 pts[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    VOut o; o.position = float4(pts[vid], 0, 1); return o;
}

// 3D simplex noise (Ashima / Stefan Gustavson, MIT)
static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 10.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = mod289(i);
    float4 p = permute(permute(permute(i.z + float4(0.0, i1.z, i2.z, 1.0)) + i.y + float4(0.0, i1.y, i2.y, 1.0)) + i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.5 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 105.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

fragment float4 aika_fragment(VOut in [[stage_in]], constant AikaUniforms &u [[buffer(0)]]) {
    float2 size = u.size.xy;
    float t = u.params.x; float level = u.params.y; float swirl = u.params.z; float breath = u.params.w;
    float3 colA = u.a.xyz; float3 colB = u.b.xyz; float3 colC = u.c.xyz;
    float2 position = in.position.xy;
    // Stejné souřadnice jako web: -1…1, y nahoru
    float2 p = float2(position.x / size.x * 2.0 - 1.0, 1.0 - position.y / size.y * 2.0);
    p.x *= size.x / size.y;
    p *= u.extra.y;
    float ang = atan2(p.y, p.x);
    float r = length(p);

    // okraj koule se vlní podle hlasu
    float wobble = snoise(float3(cos(ang) * 1.4, sin(ang) * 1.4, t * 0.6)) * (0.018 + level * 0.09);
    float radius = 0.56 + breath * 0.012 * sin(t * 1.3) + level * 0.06 + wobble;
    float d = r - radius;

    // vnější záře
    float glow = exp(-max(d, 0.0) * 5.0) * (0.55 + level * 0.7) * u.extra.x;
    float3 col = mix(colA, colB, 0.5 + 0.5 * sin(t * 0.4)) * glow * 0.7;

    if (d < 0.0) {
        float2 q = p / radius;
        float z = sqrt(max(0.0, 1.0 - dot(q, q)));
        float3 n = float3(q, z);
        // otáčení koule kolem svislé osy (jen vzor, světlo zůstává)
        float sa = sin(t * u.extra.z); float ca = cos(t * u.extra.z);
        float3 nr = float3(n.x * ca + n.z * sa, n.y, -n.x * sa + n.z * ca);
        float3 sp = nr * 0.85 + float3(0.0, 0.0, t * 0.12);
        float sw = swirl;
        float3 warp = float3(snoise(sp + float3(t * 0.21 * sw, 0.0, 0.0)),
                             snoise(sp + float3(5.2, t * 0.17 * sw, 1.3)),
                             snoise(sp + float3(9.1, 2.8, t * 0.23)));
        float f = snoise(sp * 0.9 + warp * (0.55 + level * 0.9));
        float f2 = snoise(sp * 1.4 - warp * 0.4 + t * 0.08);
        float3 base = mix(colA, colB, smoothstep(-0.8, 0.8, f));
        base = mix(base, colC, smoothstep(0.1, 1.0, f2) * (0.45 + level * 0.45));
        float light = 0.55 + 0.45 * dot(n, normalize(float3(-0.35, 0.5, 0.8)));
        float fres = pow(1.0 - z, 2.2);
        float3 inner = base * light * (0.75 + level * 0.55) + fres * mix(colB, float3(1.0), 0.35) * 0.9;
        float spec = pow(max(0.0, dot(reflect(-normalize(float3(-0.4, 0.55, 0.75)), n), float3(0, 0, 1))), 28.0);
        inner += float3(1.0) * spec * 0.35;
        float edge = smoothstep(0.0, -0.012 * u.extra.y, d);
        // záře je průsvitná, samotná koule neprůhledná (na světlém pozadí jinak tmavne)
        float ga = clamp(max(col.r, max(col.g, col.b)) * 1.4, 0.0, 1.0);
        return float4(mix(col * ga, inner, edge), mix(ga, 1.0, edge));
    }
    float a = clamp(max(col.r, max(col.g, col.b)) * 1.4, 0.0, 1.0);
    // SwiftUI čeká předem vynásobenou alfu
    return float4(col * a, a);
}
"""#
}
