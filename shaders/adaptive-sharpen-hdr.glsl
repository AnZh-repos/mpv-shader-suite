// JND-Adaptive Sharpening - HDR (ST.2084 / PQ)
// Same approach as SDR, but the Yang NAMM luminance adaptation term uses the
// PQ EOTF to determine actual luminance in cd/m^2. PQ code values don't map
// linearly to perceived brightness, so the adaptation function must work in
// absolute nits rather than relative code values.
//
// Quality levels (F4/F5/F6 or glsl-shader-opts=quality_level=N):
//   0 = Fast     - passthrough (skip entirely, saves ~3ms at 4K)
//   1 = Balanced - 3x3 unsharp mask (DEFAULT)
//   2 = Quality  - 5x5 two-scale Laplacian

//!PARAM quality_level
//!DESC Quality level: 0=Fast 1=Balanced 2=Quality
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK SCALED
//!BIND HOOKED
//!DESC JND-Adaptive Sharpening (HDR/PQ)

#define SHARPEN_STRENGTH   0.4     // Slightly lower than SDR - HDR has more perceived headroom
#define SHARPEN_CLAMP      0.035
#define JND_EDGE_MULT      33.0   // Ratio of edge threshold to flat threshold (0.10/0.003)

float get_luma_2020(vec3 rgb) {
    return dot(rgb, vec3(0.2627, 0.6780, 0.0593));
}

float pq_to_nits(float x) {
    float p = pow(max(x, 0.0), 1.0 / 78.84375);
    float num = max(p - 0.8359375, 0.0);
    float den = 18.8515625 - 18.6875 * p;
    return pow(num / den, 1.0 / 0.1593017578) * 10000.0;
}

float luminance_adaptation_hdr(float luma_pq) {
    float nits = pq_to_nits(luma_pq);
    float weber_jnd = max(nits * 0.015, 0.005);
    float pq_jnd;
    if (nits < 1.0)        pq_jnd = 0.01;
    else if (nits < 100.0) pq_jnd = weber_jnd / (nits * 3.0);
    else                   pq_jnd = weber_jnd / (nits * 5.0);
    return clamp(pq_jnd, 0.001, 0.05);
}

vec4 hook() {
    if (quality_level < 0.5) return HOOKED_texOff(vec2(0.0));

    vec3 tl = HOOKED_texOff(vec2(-1.0, -1.0)).rgb;
    vec3 tc = HOOKED_texOff(vec2( 0.0, -1.0)).rgb;
    vec3 tr = HOOKED_texOff(vec2( 1.0, -1.0)).rgb;
    vec3 ml = HOOKED_texOff(vec2(-1.0,  0.0)).rgb;
    vec3 mc = HOOKED_texOff(vec2( 0.0,  0.0)).rgb;
    vec3 mr = HOOKED_texOff(vec2( 1.0,  0.0)).rgb;
    vec3 bl = HOOKED_texOff(vec2(-1.0,  1.0)).rgb;
    vec3 bc = HOOKED_texOff(vec2( 0.0,  1.0)).rgb;
    vec3 br = HOOKED_texOff(vec2( 1.0,  1.0)).rgb;

    float l_tl = get_luma_2020(tl), l_tc = get_luma_2020(tc), l_tr = get_luma_2020(tr);
    float l_ml = get_luma_2020(ml), l_mc = get_luma_2020(mc), l_mr = get_luma_2020(mr);
    float l_bl = get_luma_2020(bl), l_bc = get_luma_2020(bc), l_br = get_luma_2020(br);

    float gx = -l_tl + l_tr - 2.0*l_ml + 2.0*l_mr - l_bl + l_br;
    float gy = -l_tl - 2.0*l_tc - l_tr + l_bl + 2.0*l_bc + l_br;
    float gradient_mag = sqrt(gx*gx + gy*gy);

    float la = luminance_adaptation_hdr(l_mc);
    float cm = gradient_mag * 0.5;
    float jnd = max(la, cm) * (1.0 + 0.3 * min(la, cm) / max(la, cm + 0.0001));

    float mask = smoothstep(jnd, jnd * 4.0, gradient_mag)
               * (1.0 - smoothstep(jnd * JND_EDGE_MULT * 0.5, jnd * JND_EDGE_MULT, gradient_mag));

    vec3 sharp;
    if (quality_level < 1.5) {
        vec3 blur = (tl + tr + bl + br + 2.0*(tc + ml + mr + bc)) / 12.0;
        sharp = mc + (mc - blur) * SHARPEN_STRENGTH * mask;
    } else {
        vec3 s_n2  = HOOKED_texOff(vec2( 0.0, -2.0)).rgb;
        vec3 s_s2  = HOOKED_texOff(vec2( 0.0,  2.0)).rgb;
        vec3 s_w2  = HOOKED_texOff(vec2(-2.0,  0.0)).rgb;
        vec3 s_e2  = HOOKED_texOff(vec2( 2.0,  0.0)).rgb;
        vec3 s_nw2 = HOOKED_texOff(vec2(-1.0, -2.0)).rgb;
        vec3 s_ne2 = HOOKED_texOff(vec2( 1.0, -2.0)).rgb;
        vec3 s_sw2 = HOOKED_texOff(vec2(-1.0,  2.0)).rgb;
        vec3 s_se2 = HOOKED_texOff(vec2( 1.0,  2.0)).rgb;
        vec3 s_wn2 = HOOKED_texOff(vec2(-2.0, -1.0)).rgb;
        vec3 s_ws2 = HOOKED_texOff(vec2(-2.0,  1.0)).rgb;
        vec3 s_en2 = HOOKED_texOff(vec2( 2.0, -1.0)).rgb;
        vec3 s_es2 = HOOKED_texOff(vec2( 2.0,  1.0)).rgb;

        vec3 inner_avg = (tl + tc + tr + ml + mr + bl + bc + br) / 8.0;
        vec3 outer_avg = (s_n2 + s_s2 + s_w2 + s_e2 +
                          s_nw2 + s_ne2 + s_sw2 + s_se2 +
                          s_wn2 + s_ws2 + s_en2 + s_es2) / 12.0;
        vec3 detail = mix(mc - outer_avg, mc - inner_avg, 0.7);
        sharp = mc + detail * SHARPEN_STRENGTH * mask;
    }

    sharp = clamp(sharp, mc - SHARPEN_CLAMP, mc + SHARPEN_CLAMP);
    return vec4(clamp(sharp, 0.0, 1.0), HOOKED_texOff(vec2(0.0)).a);
}
