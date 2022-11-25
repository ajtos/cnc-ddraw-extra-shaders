#version 450

/*
   Hyllian's DDT Shader
   
   Copyright (C) 2011-2016 Hyllian/Jararaca - sergiogdb@gmail.com

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

const vec3 Y = vec3(.2126, .7152, .0722);

float luma(vec3 color)
{
  return dot(color, Y);
}

vec3 bilinear(float p, float q, vec3 A, vec3 B, vec3 C, vec3 D)
{
	return ((1.-p)*(1.-q)*A + p*(1.-q)*B + (1.-p)*q*C + p*q*D);
}

void main()
{
vec2 pos = fract(loc)-vec2(0.5, 0.5); // pos = pixel position
	vec2 dir = sign(pos); // dir = pixel direction

	vec2 g1 = dir*t1.xy;
	vec2 g2 = dir*t1.zw;

	vec3 A = COMPAT_TEXTURE(Source, vTexCoord       ).xyz;
	vec3 B = COMPAT_TEXTURE(Source, vTexCoord +g1   ).xyz;
	vec3 C = COMPAT_TEXTURE(Source, vTexCoord    +g2).xyz;
	vec3 D = COMPAT_TEXTURE(Source, vTexCoord +g1+g2).xyz;

	float a = luma(A);
	float b = luma(B);
	float c = luma(C);
	float d = luma(D);

	float p = abs(pos.x);
	float q = abs(pos.y);

	float k = distance(pos,g1 * SourceSize.xy);
	float l = distance(pos,g2 * SourceSize.xy);

	float wd1 = abs(a-d);
	float wd2 = abs(b-c);

	if ( wd1 < wd2 )
	{
		if (k < l)
		{
			C = A + D - B;
		}
		else
		{
			B = A + D - C;
		}
	}
	else if (wd1 > wd2)
	{
		D = B + C - A;
	}

	vec3 color = bilinear(p, q, A, B, C, D);
   FragColor = vec4(color, 1.0);
}
#endif
