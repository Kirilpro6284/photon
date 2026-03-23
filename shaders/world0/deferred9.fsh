#version 430 compatibility

/*
 * Program description:
 * Render cloud shadow map
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 15 */
layout (location = 0) out float cloudShadow;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D noisetex;

uniform sampler2D lodDepthTex1;

uniform sampler3D depthtex0; // 3D worley noise
uniform sampler3D depthtex2; // 3D curl noise

//--// Includes //------------------------------------------------------------//

vec3 weather;
#include "/include/atmospherics/clouds.glsl"

#include "/include/lighting/cloudShadows.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
#ifndef CLOUD_SHADOWS
	return;
#endif

	ivec2 texel = ivec2(gl_FragCoord.xy);

	vec2 coord = gl_FragCoord.xy * rcp(vec2(cloudShadowRes));

	if (clamp01(coord) != coord) discard;

	vec3 rayOrigin = unprojectCloudShadowmap(coord);
	     rayOrigin = vec3(rayOrigin.xz, rayOrigin.y + eyeAltitude - SEA_LEVEL).xzy * CLOUDS_SCALE + vec3(0.0, planetRadius, 0.0);

	cloudShadow = getCloudShadows(rayOrigin, shadowDir);
}
