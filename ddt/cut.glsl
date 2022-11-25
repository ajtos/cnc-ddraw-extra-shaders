#version 450

/*
   MIT License
 
   Copyright (c) 2022 Filippo Scognamiglio
 
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
 
   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.
 
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
*/

/*
    Code ported by Hyllian from:
    https://github.com/Swordfish90/cheap-upscaling-triangulation
*/

// Parameter lines go here:
// set to 1.0 to use dynamic sharpening
#pragma parameter USE_DYNAMIC_SHARPNESS "Dynamic Sharpness [ 0FF | ON ]" 1.0 0.0 1.0 1.0

// Set to 1.0 to bias the interpolation towards sharpening
#pragma parameter USE_SHARPENING_BIAS "Sharpness Bias [ 0FF | ON ]" 0.0 0.0 1.0 1.0

// Minimum amount of sharpening in range [0.0, 1.0]
#pragma parameter DYNAMIC_SHARPNESS_MIN "Dynamic Sharpness Min" 0.0 0.0 0.5 0.1

// Maximum amount of sharpening in range [0.0, 1.0]
#pragma parameter DYNAMIC_SHARPNESS_MAX "Dynamic Sharpness Max" 0.4 0.0 0.5 0.1

// If USE_DYNAMIC_SHARPNESS is 0 apply this static sharpness
#pragma parameter STATIC_SHARPNESS "Static Sharpness" 0.1 0.0 0.5 0.1

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying 
#define COMPAT_ATTRIBUTE attribute 
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;
// out variables go here as COMPAT_VARYING whatever
COMPAT_VARYING vec2 screenCoords;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;

// compatibility #defines
#define vTexCoord TEX0.xy
#define SourceSize vec4(TextureSize, 1.0 / TextureSize) //either TextureSize or InputSize
#define OutSize vec4(OutputSize, 1.0 / OutputSize)

void main()
{
   gl_Position = MVPMatrix * VertexCoord;
   TEX0.xy = TexCoord.xy * 1.000001;

   screenCoords = vTexCoord*SourceSize.xy - vec2(0.5);
}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out COMPAT_PRECISION vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
// in variables go here as COMPAT_VARYING whatever
COMPAT_VARYING vec2 screenCoords;

// compatibility #defines
#define Source Texture
#define vTexCoord TEX0.xy

#define SourceSize vec4(TextureSize, 1.0 / TextureSize) //either TextureSize or InputSize
#define OutSize vec4(OutputSize, 1.0 / OutputSize)

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float USE_DYNAMIC_SHARPNESS, USE_SHARPENING_BIAS, DYNAMIC_SHARPNESS_MIN, DYNAMIC_SHARPNESS_MAX, STATIC_SHARPNESS;
#else
#define USE_DYNAMIC_SHARPNESS 1.0
#define USE_SHARPENING_BIAS 0.0
#define DYNAMIC_SHARPNESS_MIN 0.0
#define DYNAMIC_SHARPNESS_MAX 0.4
#define STATIC_SHARPNESS 0.1
#endif

float luma(vec3 v)
{
    return v.g;
}

float linearStep(float edge0, float edge1, float t)
{
    return clamp((t - edge0) / (edge1 - edge0), 0.0, 1.0);
}

float sharpSmooth(float t, float sharpness)
{
    return linearStep(sharpness, 1.0 - sharpness, t);
}

vec3 quadBilinear(vec3 a, vec3 b, vec3 c, vec3 d, vec2 p, float sharpness)
{
    float x = sharpSmooth(p.x, sharpness);
    float y = sharpSmooth(p.y, sharpness);
    return mix(mix(a, b, x), mix(c, d, x), y);
}

// Fast computation of barycentric coordinates only in the sub-triangle 1 2 4
vec3 fastBarycentric(vec2 p, float sharpness)
{
    float l0 = sharpSmooth(1.0 - p.x - p.y, sharpness);
    float l1 = sharpSmooth(p.x, sharpness);
    return vec3(l0, l1, 1.0 - l0 - l1);
}

vec3 triangleInterpolate(vec3 t1, vec3 t2, vec3 t3, vec3 t4, vec2 c, float sharpness)
{
    // Alter colors and coordinates to compute the other triangle.
    bool altTriangle = 1.0 - c.x < c.y;
    vec3 cornerColor = altTriangle ? t3 : t1;
    vec2 triangleCoords = altTriangle ? vec2(1.0 - c.y, 1.0 - c.x) : c;
    vec3 weights = fastBarycentric(triangleCoords, sharpness);
    return weights.x * cornerColor + weights.y * t2 + weights.z * t4;
}

void main()
{
    float lmax, lmin, contrast;
    float sharpness = STATIC_SHARPNESS;

    vec2 relativeCoords = floor(screenCoords);
    vec2 c1 = ((relativeCoords + vec2(0.0, 0.0)) + vec2(0.5)) / SourceSize.xy;
    vec2 c2 = ((relativeCoords + vec2(1.0, 0.0)) + vec2(0.5)) / SourceSize.xy;
    vec2 c3 = ((relativeCoords + vec2(1.0, 1.0)) + vec2(0.5)) / SourceSize.xy;
    vec2 c4 = ((relativeCoords + vec2(0.0, 1.0)) + vec2(0.5)) / SourceSize.xy;

    vec3 t1 = COMPAT_TEXTURE(Source, c1).rgb;
    vec3 t2 = COMPAT_TEXTURE(Source, c2).rgb;
    vec3 t3 = COMPAT_TEXTURE(Source, c3).rgb;
    vec3 t4 = COMPAT_TEXTURE(Source, c4).rgb;

    float l1 = luma(t1);
    float l2 = luma(t2);
    float l3 = luma(t3);
    float l4 = luma(t4);

    if (USE_DYNAMIC_SHARPNESS == 1.0)
    {
        lmax = max(max(l1, l2), max(l3, l4));
        lmin = min(min(l1, l2), min(l3, l4));
        contrast = (lmax - lmin) / (lmax + lmin + 0.05);

        if (USE_SHARPENING_BIAS == 1.0)
            contrast = sqrt(contrast);

        sharpness = mix(DYNAMIC_SHARPNESS_MIN, DYNAMIC_SHARPNESS_MAX, contrast);
    }

    vec2 pxCoords = fract(screenCoords);

    float diagonal1Strength = abs(l1 - l3);
    float diagonal2Strength = abs(l2 - l4);

    // Alter colors and coordinates to compute the other triangulation.
    bool altTriangulation = diagonal1Strength < diagonal2Strength;

    vec3 cd = triangleInterpolate(
                                  altTriangulation ? t2 : t1,
                                  altTriangulation ? t3 : t2,
                                  altTriangulation ? t4 : t3,
                                  altTriangulation ? t1 : t4,
                                  altTriangulation ? vec2(pxCoords.y, 1.0 - pxCoords.x) : pxCoords,
                                  sharpness
                                 );

    float minDiagonal = min(diagonal1Strength, diagonal2Strength);
    float maxDiagonal = max(diagonal1Strength, diagonal2Strength);
    bool diagonal     = minDiagonal * 4.0 + 0.05 < maxDiagonal;

    vec3 final = diagonal ? cd : quadBilinear(t1, t2, t4, t3, pxCoords, sharpness);

    FragColor = vec4(final, 1.0);
}
#endif
