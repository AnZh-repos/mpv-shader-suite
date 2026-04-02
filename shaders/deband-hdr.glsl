// Perceptual Debanding - HDR (ST.2084 / PQ)
// Weber-Fechner adaptive debanding for 10-bit PQ content.
//
// PQ allocates 131 code values (64-195 in 10-bit narrow range) to 0-1 cd/m^2.
// Near-black banding is structurally unavoidable at 10-bit PQ for noise-free
// content. The Weber-Fechner adaptive threshold is computed in linear light
// via the full PQ EOTF for the center pixel, then compared in PQ domain to
// avoid costly EOTF calls for every neighbor sample.
//
// Quality levels (F4/F5/F6 or glsl-shader-opts=quality_level=N):
//   0 = Fast     - 2 samples (1 tap ±), radius 6px, chroma pass is passthrough
//   1 = Balanced - 8 samples (4 taps ±), radius 16px, full chroma deband (DEFAULT)
//   2 = Quality  - 16 samples (8 taps ±), radius 22px, golden-angle spiral

//!PARAM quality_level
//!DESC Quality level: 0=Fast 1=Balanced 2=Quality
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK LUMA
//!BIND HOOKED
//!DESC Perceptual Deband (LUMA, HDR/PQ)

#define DEBAND_THRESHOLD   0.005   // Base detection threshold (PQ normalized) [0.001 - 0.02]
#define DEBAND_GRAIN       0.001   // IGN dither amplitude [0.0 - 0.005]
#define WEBER_KNEE         0.0001  // Linear luminance floor (normalized to 10000 cd/m^2)
#define WEBER_MAX_MULT     10.0    // Max threshold multiplier in darks

float ign(vec2 pos) {
    return fract(52.9829189 * fract(dot(pos, vec2(0.06711056, 0.00583715))));
}

float pq_to_linear(float x) {
    float xp = pow(max(x, 0.0), 1.0 / 78.84375);
    float num = max(xp - 0.8359375, 0.0);
    float den = 18.8515625 - 18.6875 * xp;
    return pow(num / den, 1.0 / 0.1593017578);
}

vec4 hook() {
    float center = HOOKED_texOff(vec2(0.0)).x;
    float center_lin = pq_to_linear(center);

    float weber = DEBAND_THRESHOLD / max(center_lin, WEBER_KNEE);
    float pq_thresh = min(weber, DEBAND_THRESHOLD * WEBER_MAX_MULT) * 0.5;

    float h1 = ign(gl_FragCoord.xy) - 0.5;
    float h2 = ign(gl_FragCoord.xy + vec2(31.7, 47.3)) - 0.5;
    vec2 dir = normalize(vec2(h1, h2));

    float radius = (quality_level < 0.5) ? 6.0  : (quality_level < 1.5) ? 16.0 : 22.0;
    int   taps   = (quality_level < 0.5) ? 1    : (quality_level < 1.5) ? 4    : 8;
    float golden_angle = 2.39996323;

    float sum = 0.0;
    float count = 0.0;

    for (int i = 0; i < 8; i++) {
        if (i >= taps) break;

        float r = radius * (float(i + 1) / float(taps));
        vec2 tap_dir = dir;
        if (quality_level >= 1.5) {
            float a = float(i) * golden_angle;
            tap_dir = vec2(dir.x * cos(a) - dir.y * sin(a),
                          dir.x * sin(a) + dir.y * cos(a));
        }
        vec2 offset = tap_dir * r * HOOKED_pt;

        float s1 = HOOKED_tex(HOOKED_pos + offset).x;
        if (abs(s1 - center) < pq_thresh) { sum += s1; count += 1.0; }

        float s2 = HOOKED_tex(HOOKED_pos - offset).x;
        if (abs(s2 - center) < pq_thresh) { sum += s2; count += 1.0; }
    }

    float result = center;
    if (count > 0.0)
        result = mix(center, sum / count, count / (count + 2.0));

    result += (ign(gl_FragCoord.xy + vec2(0.5)) - 0.5) * DEBAND_GRAIN;
    return vec4(clamp(result, 0.0, 1.0), 0.0, 0.0, 0.0);
}

//!HOOK CHROMA
//!BIND HOOKED
//!DESC Perceptual Deband (CHROMA, HDR/PQ)

#define DEBAND_THRESHOLD_C 0.006
#define DEBAND_GRAIN_C     0.001
#define WEBER_KNEE_C       0.02
#define WEBER_MAX_MULT_C   6.0

float ign_c(vec2 pos) {
    return fract(52.9829189 * fract(dot(pos, vec2(0.06711056, 0.00583715))));
}

vec4 hook() {
    if (quality_level < 0.5) return HOOKED_texOff(vec2(0.0));

    vec4 center = HOOKED_texOff(vec2(0.0));
    float chroma_energy = length(center.xy - 0.5);
    float thresh = DEBAND_THRESHOLD_C / max(chroma_energy, WEBER_KNEE_C);
    thresh = min(thresh, DEBAND_THRESHOLD_C * WEBER_MAX_MULT_C);

    float h1 = ign_c(gl_FragCoord.xy + vec2(7.0, 13.0)) - 0.5;
    float h2 = ign_c(gl_FragCoord.xy + vec2(43.0, 29.0)) - 0.5;
    vec2 dir = normalize(vec2(h1, h2));

    float radius = (quality_level < 1.5) ? 16.0 : 22.0;
    int   taps   = (quality_level < 1.5) ? 4    : 6;
    float golden_angle = 2.39996323;

    vec2 sum = vec2(0.0);
    float count = 0.0;

    for (int i = 0; i < 6; i++) {
        if (i >= taps) break;

        float r = radius * (float(i + 1) / float(taps));
        vec2 tap_dir = dir;
        if (quality_level >= 1.5) {
            float a = float(i) * golden_angle;
            tap_dir = vec2(dir.x * cos(a) - dir.y * sin(a),
                          dir.x * sin(a) + dir.y * cos(a));
        }
        vec2 offset = tap_dir * r * HOOKED_pt;

        vec2 s1 = HOOKED_tex(HOOKED_pos + offset).xy;
        if (length(s1 - center.xy) < thresh) { sum += s1; count += 1.0; }

        vec2 s2 = HOOKED_tex(HOOKED_pos - offset).xy;
        if (length(s2 - center.xy) < thresh) { sum += s2; count += 1.0; }
    }

    vec2 result = center.xy;
    if (count > 0.0)
        result = mix(center.xy, sum / count, count / (count + 2.0));

    result.x += (ign_c(gl_FragCoord.xy + vec2(3.0, 11.0)) - 0.5) * DEBAND_GRAIN_C;
    result.y += (ign_c(gl_FragCoord.xy + vec2(23.0, 5.0)) - 0.5) * DEBAND_GRAIN_C;
    return vec4(clamp(result, 0.0, 1.0), 0.0, 0.0);
}
