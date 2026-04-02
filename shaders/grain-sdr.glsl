// Perceptual Film Grain - SDR (BT.709 gamma)
// Intensity-dependent noise injection matching real film grain character.
// Stronger in darks where banding is most visible and film grain is most apparent.
// Applied at OUTPUT (last in chain) so no subsequent filter smooths it away.
//
// Quality levels (F4/F5/F6 or glsl-shader-opts=quality_level=N):
//   0 = Fast     - pure IGN (ALU only, no texture fetches)
//   1 = Balanced - pure IGN (same as Fast - grain is already cheap) (DEFAULT)
//   2 = Quality  - spatially correlated IGN (AR approximation, finite grain size)

//!PARAM quality_level
//!DESC Quality level: 0=Fast 1=Balanced 2=Quality
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC Perceptual Film Grain (SDR)

#define GRAIN_LUMA        0.02    // Luma grain intensity [0.0 - 0.1]
#define GRAIN_CHROMA      0.01    // Chroma grain intensity [0.0 - 0.05]
#define GRAIN_DARK_BOOST  2.0     // Extra grain in darks [1.0 - 5.0]
#define GRAIN_DARK_KNEE   0.15    // Luminance below which dark boost ramps up [0.05 - 0.5]

float ign(vec2 pos) {
    return fract(52.9829189 * fract(dot(pos, vec2(0.06711056, 0.00583715))));
}

float ign_offset(vec2 pos, vec2 seed) {
    return fract(52.9829189 * fract(dot(pos + seed, vec2(0.06711056, 0.00583715))));
}

float get_luma(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

vec4 hook() {
    vec4 color = HOOKED_texOff(vec2(0.0));
    float luma = get_luma(color.rgb);

    float dark_factor = 1.0 + GRAIN_DARK_BOOST * smoothstep(GRAIN_DARK_KNEE, 0.0, luma);

    float n_luma = (ign(gl_FragCoord.xy) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor;
    float n_cb   = (ign_offset(gl_FragCoord.xy, vec2(37.0, 17.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor;
    float n_cr   = (ign_offset(gl_FragCoord.xy, vec2(59.0, 83.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor;

    if (quality_level >= 1.5) {
        // Spatially correlated grain: blend with half-pixel-offset IGN values.
        // Models finite grain particle size. Pure white noise looks too "digital."
        float n_l2 = (ign(gl_FragCoord.xy + vec2(0.5, 0.0)) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor;
        float n_l3 = (ign(gl_FragCoord.xy + vec2(0.0, 0.5)) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor;
        float n_l4 = (ign(gl_FragCoord.xy + vec2(0.5, 0.5)) - 0.5) * 2.0 * GRAIN_LUMA * dark_factor;
        n_luma = mix(n_luma, (n_luma + n_l2 + n_l3 + n_l4) * 0.25, 0.35);

        float n_cb2 = (ign_offset(gl_FragCoord.xy + vec2(0.5, 0.0), vec2(37.0, 17.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor;
        float n_cr2 = (ign_offset(gl_FragCoord.xy + vec2(0.5, 0.0), vec2(59.0, 83.0)) - 0.5) * 2.0 * GRAIN_CHROMA * dark_factor;
        n_cb = mix(n_cb, (n_cb + n_cb2) * 0.5, 0.35);
        n_cr = mix(n_cr, (n_cr + n_cr2) * 0.5, 0.35);
    }

    // Apply as YCbCr-aligned perturbation via BT.709 inverse matrix
    color.rgb += n_luma;
    color.rgb += n_cb * vec3(-0.1146, -0.3854,  0.5);
    color.rgb += n_cr * vec3( 0.5,    -0.4542, -0.0458);

    color.rgb = clamp(color.rgb, 0.0, 1.0);
    return color;
}
