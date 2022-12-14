#version 450

/*
   Hyllian's ddt-jinc windowed-jinc 2-lobe with anti-ringing Shader
   
   Copyright (C) 2011-2022 Hyllian/Jararaca - sergiogdb@gmail.com

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/

      /*
         This is an approximation of Jinc(x)*Jinc(x*r1/r2) for x < 2.5,
         where r1 and r2 are the first two zeros of jinc function.
         For a jinc 2-lobe best approximation, use A=0.5 and B=0.825.
      */  

// A=0.5, B=0.825 is the best jinc approximation for x<2.5. if B=1.0, it's a lanczos filter.
// Increase A to get more blur. Decrease it to get a sharper picture. 
// B = 0.825 to get rid of dithering. I

// Parameter lines go here:
#pragma parameter JINC2_WINDOW_SINC "Window Sinc Param" 0.50 0.0 1.0 0.01
#pragma parameter JINC2_SINC "Sinc Param" 0.86 0.0 1.0 0.01
#pragma parameter JINC2_AR_STRENGTH "Anti-ringing Strength" 1.0 0.0 1.0 0.1
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
   TEX0.xy = TexCoord.xy * vec2(1.0001);
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

// compatibility #defines
#define Source Texture
#define vTexCoord TEX0.xy

#define SourceSize vec4(TextureSize, 1.0 / TextureSize) //either TextureSize or InputSize
#define OutSize vec4(OutputSize, 1.0 / OutputSize)

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float JINC2_WINDOW_SINC, JINC2_SINC, JINC2_AR_STRENGTH, DDT_THRESHOLD;
#else
#define JINC2_WINDOW_SINC 0.50
#define JINC2_SINC 0.86
#define JINC2_AR_STRENGTH 1.0
#define DDT_THRESHOLD 2.6
#endif

#define halfpi  1.5707963267948966192313216916398
#define pi    3.1415926535897932384626433832795
#define wa    (JINC2_WINDOW_SINC*pi)
#define wb    (JINC2_SINC*pi)

#define WP1  2.0
#define WP2  1.0
#define WP3 -1.0

const vec3 Y = vec3( 0.299,  0.587,  0.114);

float luma(vec3 color)
{
  return dot(color, Y);
}

// Calculates the distance between two points
float d(vec2 pt1, vec2 pt2)
{
  vec2 v = pt2 - pt1;
  return sqrt(dot(v,v));
}

vec3 min4(vec3 a, vec3 b, vec3 c, vec3 d)
{
    return min(a, min(b, min(c, d)));
}

vec3 max4(vec3 a, vec3 b, vec3 c, vec3 d)
{
    return max(a, max(b, max(c, d)));
}

vec4 resampler(vec4 x)
{
	vec4 res;
	res.x = (x.x==0.0) ?  wa*wb  :  sin(x.x*wa)*sin(x.x*wb)/(x.x*x.x);
	res.y = (x.y==0.0) ?  wa*wb  :  sin(x.y*wa)*sin(x.y*wb)/(x.y*x.y);
	res.z = (x.z==0.0) ?  wa*wb  :  sin(x.z*wa)*sin(x.z*wb)/(x.z*x.z);
	res.w = (x.w==0.0) ?  wa*wb  :  sin(x.w*wa)*sin(x.w*wb)/(x.w*x.w);
	return res;
}

void main()
{
      vec3 color;
      mat4x4 weights;

      vec2 dx = vec2(1.0, 0.0);
      vec2 dy = vec2(0.0, 1.0);

      vec2 pc = vTexCoord*SourceSize.xy;

      vec2 tc = (floor(pc-vec2(0.5,0.5))+vec2(0.5,0.5));

      vec2 pos = fract(pc-vec2(0.5,0.5));
     
      weights[0] = resampler(vec4(d(pc, tc    -dx    -dy), d(pc, tc           -dy), d(pc, tc    +dx    -dy), d(pc, tc+2.0*dx    -dy)));
      weights[1] = resampler(vec4(d(pc, tc    -dx       ), d(pc, tc              ), d(pc, tc    +dx       ), d(pc, tc+2.0*dx       )));
      weights[2] = resampler(vec4(d(pc, tc    -dx    +dy), d(pc, tc           +dy), d(pc, tc    +dx    +dy), d(pc, tc+2.0*dx    +dy)));
      weights[3] = resampler(vec4(d(pc, tc    -dx+2.0*dy), d(pc, tc       +2.0*dy), d(pc, tc    +dx+2.0*dy), d(pc, tc+2.0*dx+2.0*dy)));

      dx = dx * SourceSize.zw;
      dy = dy * SourceSize.zw;
      tc = tc * SourceSize.zw;
     
     // reading the texels
     
      vec3 c00 = COMPAT_TEXTURE(Source, tc    -dx    -dy).xyz;
      vec3 c10 = COMPAT_TEXTURE(Source, tc           -dy).xyz;
      vec3 c20 = COMPAT_TEXTURE(Source, tc    +dx    -dy).xyz;
      vec3 c30 = COMPAT_TEXTURE(Source, tc+2.0*dx    -dy).xyz;
      vec3 c01 = COMPAT_TEXTURE(Source, tc    -dx       ).xyz;
      vec3 c11 = COMPAT_TEXTURE(Source, tc              ).xyz;
      vec3 c21 = COMPAT_TEXTURE(Source, tc    +dx       ).xyz;
      vec3 c31 = COMPAT_TEXTURE(Source, tc+2.0*dx       ).xyz;
      vec3 c02 = COMPAT_TEXTURE(Source, tc    -dx    +dy).xyz;
      vec3 c12 = COMPAT_TEXTURE(Source, tc           +dy).xyz;
      vec3 c22 = COMPAT_TEXTURE(Source, tc    +dx    +dy).xyz;
      vec3 c32 = COMPAT_TEXTURE(Source, tc+2.0*dx    +dy).xyz;
      vec3 c03 = COMPAT_TEXTURE(Source, tc    -dx+2.0*dy).xyz;
      vec3 c13 = COMPAT_TEXTURE(Source, tc       +2.0*dy).xyz;
      vec3 c23 = COMPAT_TEXTURE(Source, tc    +dx+2.0*dy).xyz;
      vec3 c33 = COMPAT_TEXTURE(Source, tc+2.0*dx+2.0*dy).xyz;

      //  Get min/max samples
      vec3 min_sample = min4(c11, c21, c12, c22);
      vec3 max_sample = max4(c11, c21, c12, c22);

      float a = luma(c11);
      float b = luma(c21);
      float c = luma(c12);
      float d = luma(c22);

      float a1 = luma(c10);
      float b1 = luma(c20);
      float a0 = luma(c01);
      float c0 = luma(c02);

      float b2 = luma(c31);
      float d2 = luma(c32);
      float c3 = luma(c13);
      float d3 = luma(c23);

      float p = abs(pos.x);
      float q = abs(pos.y);

/*
      c00 c10 c20 c30     a1 b1
      c01 c11 c21 c31  a0  a  b b2
      c02 c12 c22 c32  c0  c  d d2
      c03 c13 c23 c33     c3 d3
*/

      float wd1 = (WP1*abs(a-d) + WP2*(abs(b-a1) + abs(b-d2) + abs(c-a0) + abs(c-d3)) + WP3*(abs(a1-d2) + abs(a0-d3)));
      float wd2 = (WP1*abs(b-c) + WP2*(abs(a-b1) + abs(a-c0) + abs(d-b2) + abs(d-c3)) + WP3*(abs(b1-c0) + abs(b2-c3)));

      float irlv1 = (abs(a-b)+abs(a-c)+abs(a-d));

	if (((wd1+0.1*DDT_THRESHOLD)*DDT_THRESHOLD < wd2) && (irlv1 > 0.0))
	{
		if (q <= p)
		{
			c12 = c11 + c22 - c21;
			c01 = c11 + c00 - c10;
			c23 = c22 + c33 - c32;
			c03 = c13 + c02 - c12;
		}
		else
		{
			c21 = c11 + c22 - c12;
			c10 = c11 + c00 - c01;
			c32 = c22 + c33 - c23;
			c30 = c31 + c20 - c21;
		}
	}
	else if ((wd1 > (wd2+0.1*DDT_THRESHOLD)*DDT_THRESHOLD)  && (irlv1 > 0.0))
	{
		if ((p+q) < 1.0)
		{
			c22 = c21 + c12 - c11;
			c31 = c21 + c30 - c20;
			c13 = c12 + c03 - c02;
			c33 = c23 + c32 - c22;
		}
		else
		{
			c11 = c21 + c12 - c22;
			c20 = c21 + c30 - c31;
			c02 = c12 + c03 - c13;
			c00 = c10 + c01 - c11;
		}
	}

      color = mat4x3(c00, c10, c20, c30) * weights[0];
      color+= mat4x3(c01, c11, c21, c31) * weights[1];
      color+= mat4x3(c02, c12, c22, c32) * weights[2];
      color+= mat4x3(c03, c13, c23, c33) * weights[3];
      color = color/(dot(weights * vec4(1.0), vec4(1.0)));

      // Anti-ringing
      vec3 aux = color;
      color = clamp(color, min_sample, max_sample);

      color = mix(aux, color, JINC2_AR_STRENGTH);
 
      // final sum and weight normalization
      FragColor = vec4(color, 1.0);
}
#endif
