// Luma-Guided Chroma Reconstruction
// Replaces mpv's built-in chroma upsampling (cscale) with edge-aware
// interpolation that uses the full-resolution luma plane as a guide signal.
//
// Quality levels (F4/F5/F6 or glsl-shader-opts=quality_level=N):
//   0 = Fast     - 2x2 kernel (8 tex), polynomial weights (no exp())
//   1 = Balanced - 4x4 kernel (32 tex), Gaussian weights (DEFAULT)
//   2 = Quality  - 4x4 kernel, tighter sigmas; set CHROMA_MODE=1 for KrigBilateral
//
// CHROMA_MODE: 0=bilateral (all quality levels), 1=KrigBilateral (quality 2 only)

//!PARAM quality_level
//!DESC Quality level: 0=Fast 1=Balanced 2=Quality
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!DESC Chroma Reconstruction (Luma-Guided)

// --- Tunable ---
#define CHROMA_MODE   0     // 0 = bilateral (all levels), 1 = KrigBilateral (quality=2 only)
#define SIGMA_SPATIAL 1.0   // Spatial falloff [0.5 - 4.0]
#define SIGMA_RANGE   0.10  // Luma similarity threshold [0.01 - 0.5]
#define KRIG_RANGE    0.2   // Variogram range (CHROMA_MODE 1 only)
#define KRIG_NUGGET   0.001 // Variogram noise floor (CHROMA_MODE 1 only)

#if CHROMA_MODE == 0

// ============================================================
// Bilateral mode (default)
// ============================================================

vec4 hook() {
    // Fast: let GPU hardware bilinear handle chroma upsampling - 1 tex fetch, zero ALU
    if (quality_level < 0.5) return HOOKED_texOff(vec2(0.0));

    float luma_target = LUMA_texOff(vec2(0.0)).x;

    vec2 sum = vec2(0.0);
    float weight_sum = 0.0;

    float sigma_s2 = 2.0 * SIGMA_SPATIAL * SIGMA_SPATIAL;
    float sigma_r2_eff = (quality_level >= 1.5) ? (SIGMA_RANGE * 0.7) : SIGMA_RANGE;
    sigma_r2_eff = 2.0 * sigma_r2_eff * sigma_r2_eff;

    {
        // 4x4 bilateral with Gaussian weights - 16 chroma + 16 luma = 32 tex fetches
        for (int dy = -1; dy <= 2; dy++) {
            for (int dx = -1; dx <= 2; dx++) {
                vec2 offset = vec2(float(dx) - 0.5, float(dy) - 0.5);

                vec2 chroma_s = HOOKED_tex(HOOKED_pos + offset * HOOKED_pt).xy;
                float luma_n  = LUMA_tex(LUMA_pos + offset * LUMA_pt * 2.0).x;

                float d_s = dot(offset, offset);
                float d_l = luma_n - luma_target;

                float w = exp(-d_s / sigma_s2) * exp(-(d_l * d_l) / sigma_r2_eff);

                sum += chroma_s * w;
                weight_sum += w;
            }
        }
    }

    vec2 result = (weight_sum > 0.001) ? sum / weight_sum
                                       : HOOKED_texOff(vec2(0.0)).xy;
    return vec4(result, 0.0, 0.0);
}

#else // CHROMA_MODE == 1 - KrigBilateral (set quality_level=2 for best results)

// ============================================================
// KrigBilateral mode - geostatistical optimal interpolation
// Only meaningful at quality_level >= 1 (4x4 kernel)
// ============================================================

float variogram(float luma_diff) {
    float h2 = luma_diff * luma_diff;
    float r2 = KRIG_RANGE * KRIG_RANGE;
    return KRIG_NUGGET + (1.0 - KRIG_NUGGET) * (1.0 - exp(-h2 / r2));
}

vec4 hook() {
    float luma_target = LUMA_texOff(vec2(0.0)).x;

    // Fast: fall back to 2x2 bilateral with polynomial weights
    if (quality_level < 0.5) {
        vec2 sum = vec2(0.0);
        float weight_sum = 0.0;
        float sigma_s2 = 2.0 * SIGMA_SPATIAL * SIGMA_SPATIAL;
        float sigma_r2 = 2.0 * SIGMA_RANGE * SIGMA_RANGE;
        for (int dy = 0; dy <= 1; dy++) {
            for (int dx = 0; dx <= 1; dx++) {
                vec2 offset = vec2(float(dx) - 0.5, float(dy) - 0.5);
                vec2 cs = HOOKED_tex(HOOKED_pos + offset * HOOKED_pt).xy;
                float ln = LUMA_tex(LUMA_pos + offset * LUMA_pt * 2.0).x;
                float d_l = ln - luma_target;
                float w = max(0.0, 1.0 - dot(offset,offset)/sigma_s2)
                        * max(0.0, 1.0 - (d_l*d_l)/sigma_r2);
                sum += cs * w; weight_sum += w;
            }
        }
        vec2 r = (weight_sum > 0.001) ? sum/weight_sum : HOOKED_texOff(vec2(0.0)).xy;
        return vec4(r, 0.0, 0.0);
    }

    const int N = 16;
    vec2  chroma_s[N];
    float luma_s[N];
    float gamma_0[N];

    int idx = 0;
    for (int dy = -1; dy <= 2; dy++) {
        for (int dx = -1; dx <= 2; dx++) {
            vec2 offset = vec2(float(dx) - 0.5, float(dy) - 0.5);
            chroma_s[idx] = HOOKED_tex(HOOKED_pos + offset * HOOKED_pt).xy;
            luma_s[idx]   = LUMA_tex(LUMA_pos + offset * LUMA_pt * 2.0).x;
            gamma_0[idx]  = variogram(luma_s[idx] - luma_target);
            idx++;
        }
    }

    float weights[N];
    float weight_sum = 0.0;
    float sigma_s2 = 2.0 * SIGMA_SPATIAL * SIGMA_SPATIAL;

    for (int i = 0; i < N; i++) {
        int dy_i = i / 4 - 1;
        int dx_i = (i - (i/4)*4) - 1;
        vec2 off_i = vec2(float(dx_i) - 0.5, float(dy_i) - 0.5);
        float w_s = exp(-dot(off_i, off_i) / sigma_s2);
        weights[i] = w_s / max(gamma_0[i], 0.0001);
        weight_sum += weights[i];
    }

    vec2 result = vec2(0.0);
    for (int i = 0; i < N; i++)
        result += chroma_s[i] * (weights[i] / weight_sum);

    return vec4(result, 0.0, 0.0);
}

#endif
