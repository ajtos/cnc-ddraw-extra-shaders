#version 450

/*
   Hyllian's DDT-xBR-lv1 Shader
   
   Copyright (C) 2011-2022 Hyllian/Jararaca - sergiogdb@gmail.com

   Sharpness control - Copyright (c) 2022 Filippo Scognamiglio

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.


*/

// Parameter lines go here:
// set to 1.0 to use dynamic sharpening
#pragma parameter USE_DYNAMIC_SHARPNESS "Dynamic Sharpness [ 0FF | ON ]" 1.0 0.0 1.0 1.0

// Set to 1.0 to bias the interpolation towards sharpening
#pragma parameter USE_SHARPENING_BIAS "Sharpness Bias [ 0FF | ON ]" 1.0 0.0 1.0 1.0

// Minimum amount of sharpening in range [0.0, 1.0]
#pragma parameter DYNAMIC_SHARPNESS_MIN "Dynamic Sharpness Min" 0.0 0.0 0.5 0.1

// Maximum amount of sharpening in range [0.0, 1.0]
#pragma parameter DYNAMIC_SHARPNESS_MAX "Dynamic Sharpness Max" 0.15 0.0 0.5 0.1

// If USE_DYNAMIC_SHARPNESS is 0 apply this static sharpness
#pragma parameter STATIC_SHARPNESS "Static Sharpness" 0.25 0.0 0.5 0.1

#pragma parameter DDT_THRESHOLD "DDT Diagonal Threshold" 2.6 1.0 6.0 0.2

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
COMPAT_VARYING vec4 t1;
COMPAT_VARYING vec2 loc;

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
   TEX0.xy = TexCoord.xy * 1.0001;

    vec2 ps = vec2(SourceSize.z, SourceSize.w);
    float dx = ps.x;
    float dy = ps.y;

    t1.xy = vec2( dx,  0); // F
    t1.zw = vec2(  0, dy); // H
    loc = vTexCoord*SourceSize.xy;
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
COMPAT_VARYING vec4 t1;
COMPAT_VARYING vec2 loc;

// compatibility #defines
#define Source Texture
#define vTexCoord TEX0.xy

#define SourceSize vec4(TextureSize, 1.0 / TextureSize) //either TextureSize or InputSize
#define OutSize vec4(OutputSize, 1.0 / OutputSize)

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float USE_DYNAMIC_SHARPNESS, USE_SHARPENING_BIAS, DYNAMIC_SHARPNESS_MIN, DYNAMIC_SHARPNESS_MAX, STATIC_SHARPNESS, DDT_THRESHOLD;
#else
#define USE_DYNAMIC_SHARPNESS 1.0
#define USE_SHARPENING_BIAS 1.0
#define DYNAMIC_SHARPNESS_MIN 0.0
#define DYNAMIC_SHARPNESS_MAX 0.15
#define STATIC_SHARPNESS 0.25
#define DDT_THRESHOLD 2.6
#endif

#define WP1  4.0
#define WP2  1.0
#define WP3 -1.0

const vec3 Y = vec3( 0.299,  0.587,  0.114);

float luma(vec3 color)
{
  return dot(color, Y);
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
    vec2 pos = fract(loc)-vec2(0.5, 0.5); // pos = pixel position
    vec2 dir = sign(pos); // dir = pixel direction
    float lmax, lmin, contrast;
    float sharpness = STATIC_SHARPNESS;

    vec2 g1 = dir*t1.xy;
    vec2 g2 = dir*t1.zw;

    vec3 A = COMPAT_TEXTURE(Source, vTexCoord       ).xyz;
    vec3 B = COMPAT_TEXTURE(Source, vTexCoord +g1   ).xyz;
    vec3 C = COMPAT_TEXTURE(Source, vTexCoord    +g2).xyz;
    vec3 D = COMPAT_TEXTURE(Source, vTexCoord +g1+g2).xyz;

    vec3 A1 = COMPAT_TEXTURE(Source, vTexCoord    -g2).xyz;
    vec3 B1 = COMPAT_TEXTURE(Source, vTexCoord +g1-g2).xyz;
    vec3 A0 = COMPAT_TEXTURE(Source, vTexCoord -g1   ).xyz;
    vec3 C0 = COMPAT_TEXTURE(Source, vTexCoord -g1+g2).xyz;

    vec3 B2 = COMPAT_TEXTURE(Source, vTexCoord +2.*g1     ).xyz;
    vec3 D2 = COMPAT_TEXTURE(Source, vTexCoord +2.*g1+  g2).xyz;
    vec3 C3 = COMPAT_TEXTURE(Source, vTexCoord      +2.*g2).xyz;
    vec3 D3 = COMPAT_TEXTURE(Source, vTexCoord   +g1+2.*g2).xyz;

    float a = luma(A);
    float b = luma(B);
    float c = luma(C);
    float d = luma(D);

    if (USE_DYNAMIC_SHARPNESS == 1.0)
    {
        lmax = max(max(a, b), max(c, d));
        lmin = min(min(a, b), min(c, d));
        contrast = (lmax - lmin) / (lmax + lmin + 0.05);

        if (USE_SHARPENING_BIAS == 1.0)
            contrast = sqrt(contrast);

        sharpness = mix(DYNAMIC_SHARPNESS_MIN, DYNAMIC_SHARPNESS_MAX, contrast);
    }	
    
    float a1 = luma(A1);
    float b1 = luma(B1);
    float a0 = luma(A0);
    float c0 = luma(C0);

    float b2 = luma(B2);
    float d2 = luma(D2);
    float c3 = luma(C3);
    float d3 = luma(D3);

    float p = abs(pos.x);
    float q = abs(pos.y);

//    A1 B1
// A0 A  B  B2
// C0 C  D  D2
//    C3 D3

    float wd1 = (WP1*abs(a-d) + WP2*(abs(b-a1) + abs(b-d2) + abs(c-a0) + abs(c-d3)) + WP3*(abs(a1-d2) + abs(a0-d3)));
    float wd2 = (WP1*abs(b-c) + WP2*(abs(a-b1) + abs(a-c0) + abs(d-b2) + abs(d-c3)) + WP3*(abs(b1-c0) + abs(b2-c3)));

    float irlv1 = (abs(a-b)+abs(a-c)+abs(d-c)+abs(d-b));

    vec3 color;

    if ( ((wd1+0.1*DDT_THRESHOLD)*DDT_THRESHOLD < wd2) && (irlv1 > 0.0) )
    {
           color = triangleInterpolate(B, D, C, A, vec2(q, 1.-p), sharpness);
    }
    else if ( (wd1 > (wd2+0.1*DDT_THRESHOLD)*DDT_THRESHOLD) && (irlv1 > 0.0))
    {
           color = triangleInterpolate(A, B, D, C, vec2(p, q), sharpness);
    }
    else
        color = quadBilinear(A, B, C, D, vec2(p, q), sharpness);

   FragColor = vec4(color, 1.0);
}
#endif
