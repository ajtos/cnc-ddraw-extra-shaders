# cnc-ddraw-extra-shaders
Additional glsl shaders for cnc-ddraw ported from libretro slang repository

## Porting
**RetroArch** moved from glsl to slang as their format of choice for shaders. Many new shaders were introduced into [slang repository](https://github.com/libretro/slang-shaders) and some were updated compared to [glsl repository](https://github.com/libretro/glsl-shaders). In order to use those shaders with cnc-ddraw, they must be converted to glsl format by hand.

## Tuning
Additionally some shaders can be tuned, cnc-ddraw currently can't change those parameters directly, files must be edited by hand. For example if you look at *cubic/bicubic.glsl* shader, you will notice at top of the file:

```
#pragma parameter B "Bicubic Coeff B" 0.33 0.0 1.0 0.01
#pragma parameter C "Bicubic Coeff C" 0.33 0.0 1.0 0.01
```

Those four numeric values beside parameters correspond to: default value, min value, max value, increments/precision. To actually change those values, look further down the file.

```
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float B, C;
#else
#define B 0.3333
#define C 0.3333
#endif
```

Adjusting those values will impact how shaders behaves. Provided *cubic/bicubic-tuned.glsl* has B/C values changed to 0.0/1.0 resulting in much sharper image at cost of potential ringing artifacts.

## Demo
You can compare shaders [here](https://ajtos.github.io/shaders/) (adpoted from [bayaraa](https://github.com/bayaraa/bayaraa.github.io)).
