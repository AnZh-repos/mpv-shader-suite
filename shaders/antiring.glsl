// Anti-Ringing - Local Min/Max Clamp
// Suppresses ringing (Gibbs phenomenon overshoot) introduced by sharp upscaling
// kernels like ewa_lanczossharp. Ringing manifests as pixel values that exceed
// the local dynamic range - clamping to the local envelope removes it cleanly.
//
// Must run BEFORE adaptive-sharpen in the chain so the sharpener never amplifies
// surviving ringing, which Mach bands in the HVS would then further amplify.
//
// Quality levels (F4/F5/F6 or glsl-shader-opts=quality_level=N):
//   0 = Fast     - passthrough (skip entirely, saves ~3ms at 4K)
//   1 = Balanced - 3x3 neighborhood (8 taps) (DEFAULT)
//   2 = Quality  - 5x5 neighborhood (24 taps), more stable envelope

//!PARAM quality_level
//!DESC Quality level: 0=Fast 1=Balanced 2=Quality
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK SCALED
//!BIND HOOKED
//!DESC Anti-Ringing (Local Min/Max Clamp)

#define ANTIRING_STRENGTH  0.80   // Balanced blend [0.0=off - 1.0=full clamp]
#define ANTIRING_STRENGTH2 0.85   // Strength override at quality=2

vec4 hook() {
    if (quality_level < 0.5) return HOOKED_texOff(vec2(0.0));

    vec4 center = HOOKED_texOff(vec2(0.0));
    vec4 lo = center;
    vec4 hi = center;
    vec4 s;

    s = HOOKED_texOff(vec2(-1.0, -1.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2( 0.0, -1.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2( 1.0, -1.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2(-1.0,  0.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2( 1.0,  0.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2(-1.0,  1.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2( 0.0,  1.0)); lo = min(lo, s); hi = max(hi, s);
    s = HOOKED_texOff(vec2( 1.0,  1.0)); lo = min(lo, s); hi = max(hi, s);

    if (quality_level >= 1.5) {
        // Extended 5x5 ring: 16 additional samples for a more stable envelope.
        s = HOOKED_texOff(vec2(-2.0, -2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2(-1.0, -2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 0.0, -2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 1.0, -2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 2.0, -2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2(-2.0, -1.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 2.0, -1.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2(-2.0,  0.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 2.0,  0.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2(-2.0,  1.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 2.0,  1.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2(-2.0,  2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2(-1.0,  2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 0.0,  2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 1.0,  2.0)); lo = min(lo, s); hi = max(hi, s);
        s = HOOKED_texOff(vec2( 2.0,  2.0)); lo = min(lo, s); hi = max(hi, s);
    }

    float strength = (quality_level >= 1.5) ? ANTIRING_STRENGTH2 : ANTIRING_STRENGTH;
    return mix(center, clamp(center, lo, hi), strength);
}
