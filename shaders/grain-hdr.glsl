// Perceptual Film Grain - HDR (PQ / ST.2084)
// Intensity-dependent noise injection for HDR content on PQ displays.
// PQ near-black is extremely nonlinear: codes 0-64 (of 1023) cover 0-1 cd/m^2.
// Grain amplitude is scaled by local PQ value to remain perceptually consistent
// across the high dynamic range.
//
// Quality levels (F4/F5/F6 or glsl-shader-opts=quality_level=N):
//   0 = Fast     - pure IGN (ALU only)
//   1 = Balanced - pure IGN (same - grain is cheap) (DEFAULT)
//   2 = Quality  - spatially correlated IGN (AR approximation)

//!PARAM quality_level
//!DESC Quality level: 0=Fast 1=Balanced 2=Quality
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC Perceptual Film Grain (HDR/PQ)

#define GRAIN_LUMA        0.015
#define GRAIN_CHROMA      0.008
#define GRAIN_DARK_BOOST  3.0
#define GRAIN_DARK_KNEE   0.10

float ign(vec2 pos) {
    return fract(52.9829189 * fract(dot(pos, vec2(0.06711056, 0.00583715))));
}

float ign_offset(vec2 pos, vec2 seed) {
    return fract(52.9829189 * fract(dot(pos + seed, vec2(0.06711056, 0.00583715))));
}

float get_luma_2020(vec3 rgb) {
    return dot(rgb, vec3(0.2627, 0.6780, 0.0593));
}

vec4 hook() {
    vec4 color = HOOKED_texOff(vec2(0.0));
    float luma_pq = get_luma_2020(color.rgb);

    float dark_factor = 1.0 + GRAIN_DARK_BOOST * smoothstep(GRAIN_DARK_KNEE, 0.0, luma_pq);
    // Scale grain amplitude by local PQ value: near-black PQ steps are
    // perceptually large, so absolute noise must be smaller there.
    float pq_scale = max(luma_pq, 0.02);

    float n_luma = (ign(gl_FragCoord.xy) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor * pq_scale;
    float n_cb   = (ign_offset(gl_FragCoord.xy, vec2(37.0, 17.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor * pq_scale;
    float n_cr   = (ign_offset(gl_FragCoord.xy, vec2(59.0, 83.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor * pq_scale;

    if (quality_level >= 1.5) {
        float n_l2 = (ign(gl_FragCoord.xy + vec2(0.5, 0.0)) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor * pq_scale;
        float n_l3 = (ign(gl_FragCoord.xy + vec2(0.0, 0.5)) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor * pq_scale;
        float n_l4 = (ign(gl_FragCoord.xy + vec2(0.5, 0.5)) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor * pq_scale;
        n_luma = mix(n_luma, (n_luma + n_l2 + n_l3 + n_l4) * 0.25, 0.35);

        float n_cb2 = (ign_offset(gl_FragCoord.xy + vec2(0.5, 0.0), vec2(37.0, 17.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor * pq_scale;
        float n_cr2 = (ign_offset(gl_FragCoord.xy + vec2(0.5, 0.0), vec2(59.0, 83.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor * pq_scale;
        n_cb = mix(n_cb, (n_cb + n_cb2) * 0.5, 0.35);
        n_cr = mix(n_cr, (n_cr + n_cr2) * 0.5, 0.35);
    }

    // Apply via BT.2020 inverse matrix
    color.rgb += n_luma;
    color.rgb += n_cb * vec3(-0.0593, -0.4407,  0.5);
    color.rgb += n_cr * vec3( 0.5,    -0.4598, -0.0402);

    color.rgb = clamp(color.rgb, 0.0, 1.0);
    return color;
}
