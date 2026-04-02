// JND-Adaptive Sharpening - SDR (BT.709 gamma)
// Edge-aware sharpening informed by the Yang et al. (2005) NAMM JND model.
//
// Flat regions (sky, gradients) get ZERO sharpening - would amplify banding.
// Hard edges get REDUCED sharpening - would amplify ringing and Mach bands.
// Moderate-texture regions (fabric, hair, skin detail) get full sharpening.
//
// Must run AFTER antiring.glsl (both hook SCALED).
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
//!DESC JND-Adaptive Sharpening (SDR)

#define SHARPEN_STRENGTH   0.5     // Overall sharpening intensity [0.0 - 2.0]
#define SHARPEN_CLAMP      0.035   // Max overshoot per channel - prevents new ringing [0.0 - 0.1]
#define JND_EDGE_MULT      30.0   // Ratio of edge threshold to flat threshold (0.15/0.005)

float get_luma(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

float luminance_adaptation(float luma) {
    float l = luma * 255.0;
    if (l < 127.0) return (17.0 * (1.0 - sqrt(l / 127.0)) + 3.0) / 255.0;
    return (3.0 / 128.0 * (l - 127.0) + 3.0) / 255.0;
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

    float l_tl = get_luma(tl), l_tc = get_luma(tc), l_tr = get_luma(tr);
    float l_ml = get_luma(ml), l_mc = get_luma(mc), l_mr = get_luma(mr);
    float l_bl = get_luma(bl), l_bc = get_luma(bc), l_br = get_luma(br);

    float gx = -l_tl + l_tr - 2.0*l_ml + 2.0*l_mr - l_bl + l_br;
    float gy = -l_tl - 2.0*l_tc - l_tr + l_bl + 2.0*l_bc + l_br;
    float gradient_mag = sqrt(gx*gx + gy*gy);

    float la = luminance_adaptation(l_mc);
    float cm = gradient_mag * 0.5;
    float jnd = max(la, cm) * (1.0 + 0.3 * min(la, cm) / max(la, cm + 0.0001));

    float mask = smoothstep(jnd, jnd * 4.0, gradient_mag)
               * (1.0 - smoothstep(jnd * JND_EDGE_MULT * 0.5, jnd * JND_EDGE_MULT, gradient_mag));

    vec3 sharp;
    if (quality_level < 1.5) {
        // 3x3 unsharp mask - fast and effective
        vec3 blur = (tl + tr + bl + br + 2.0*(tc + ml + mr + bc)) / 12.0;
        sharp = mc + (mc - blur) * SHARPEN_STRENGTH * mask;
    } else {
        // 5x5 two-scale Laplacian - finer spatial control
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

    // Anti-overshoot clamp: no new ringing from sharpening
    sharp = clamp(sharp, mc - SHARPEN_CLAMP, mc + SHARPEN_CLAMP);
    return vec4(clamp(sharp, 0.0, 1.0), HOOKED_texOff(vec2(0.0)).a);
}
