# mpv-perceptual-shaders

Eight GLSL shaders for mpv targeting common streaming artifacts: banding, chroma blur, upscaling
ringing, and flat-detail loss. SDR (BT.709) and HDR (ST.2084/PQ) variants for each stage.

## Shaders

| File | Hook | What it does |
|------|------|--------------|
| `deband-sdr.glsl` | LUMA, CHROMA | Weber-Fechner adaptive debanding with IGN dithering, BT.709 |
| `deband-hdr.glsl` | LUMA, CHROMA | Same algorithm; threshold computed via full PQ EOTF in linear light |
| `chroma-reconstruct.glsl` | CHROMA | Bilateral chroma upsampling guided by full-resolution luma; KrigBilateral available |
| `antiring.glsl` | SCALED | Local min/max envelope clamp to remove Gibbs overshoot from sharp upscaling kernels |
| `adaptive-sharpen-sdr.glsl` | SCALED | JND-gated unsharp mask (Yang et al. NAMM); flat regions and hard edges get reduced or zero sharpening |
| `adaptive-sharpen-hdr.glsl` | SCALED | Same; luminance adaptation in absolute nits via PQ EOTF |
| `grain-sdr.glsl` | OUTPUT | Intensity-dependent film grain via IGN, heavier in darks |
| `grain-hdr.glsl` | OUTPUT | Film grain for PQ; amplitude scaled by local PQ value |

## Requirements

- mpv v0.39+
- libplacebo v7.x (needed for `//!PARAM` live switching)
- `vo=gpu-next` in `mpv.conf`
- Vulkan recommended. D3D11 runs 2-3x slower for this workload (~1.6ms total at HDR 4K, Balanced).

## Install

Copy `.glsl` files to your mpv shaders directory:

- Windows: `%APPDATA%\mpv\shaders\`
- Linux / macOS: `~/.config/mpv/shaders/`

Add to `mpv.conf`:

```ini
[sdr-streaming]
glsl-shaders="~~/shaders/deband-sdr.glsl:~~/shaders/chroma-reconstruct.glsl:~~/shaders/antiring.glsl:~~/shaders/adaptive-sharpen-sdr.glsl:~~/shaders/grain-sdr.glsl"
glsl-shader-opts=quality_level=1

[hdr-streaming]
glsl-shaders="~~/shaders/deband-hdr.glsl:~~/shaders/chroma-reconstruct.glsl:~~/shaders/antiring.glsl:~~/shaders/adaptive-sharpen-hdr.glsl:~~/shaders/grain-hdr.glsl"
glsl-shader-opts=quality_level=1
```

## Pipeline order

```
deband -> chroma-reconstruct -> antiring -> adaptive-sharpen -> grain
```

Deband runs at native source resolution (4:2:0 chroma at half res). Chroma-reconstruct uses
the debanded luma as a guide for edge-aware upsampling. Antiring must run before adaptive-sharpen
or the sharpener amplifies surviving ringing. Grain runs at OUTPUT after all scaling.

## Quality levels

All shaders share one `quality_level` param. Set it once via `glsl-shader-opts=quality_level=N`.

| Level | Deband | Chroma | Antiring | Sharpen | Grain |
|-------|--------|--------|----------|---------|-------|
| 0 Fast | 2 samples, r=6px, luma only | HW bilinear passthrough | Passthrough | Passthrough | Pure IGN |
| 1 Balanced | 8 samples, r=16px, full chroma | 4x4 Gaussian bilateral | 3x3 (8 taps) | 3x3 unsharp | Pure IGN |
| 2 Quality | 16 samples, r=22px, golden-angle spiral | 4x4 tighter sigmas | 5x5 (24 taps) | 5x5 two-scale Laplacian | Spatially correlated IGN |

Each shader has `#define` constants at the top for per-parameter tuning. Defaults target typical
streaming content.
