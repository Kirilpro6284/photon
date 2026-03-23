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

	vec2 coord = gl_FragCoord.xy * rcp(vec2(cloudShadowMapRes));

	if (clamp01(coord) != coord) discard;

	uint cascade = uint(dot(floor(coord * 2.0), vec2(1.0, 2.0)));

	vec3 rayOrigin = unprojectCloudShadowMap(fract(coord * 2.0), cascade);
	     rayOrigin = vec3(rayOrigin.x, rayOrigin.y + eyeAltitude - SEA_LEVEL, rayOrigin.z) * CLOUDS_SCALE + vec3(0.0, planetRadius, 0.0);
		 rayOrigin += shadowDir * (SEA_LEVEL + CLOUDS_LAYER0_ALTITUDE + planetRadius - 250.0 - rayOrigin.y) / max(0.05, shadowDir.y);

	cloudShadow = getCloudShadows(rayOrigin, shadowDir);
}
