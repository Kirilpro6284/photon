#version 430 compatibility

/*
 * Program description
 * Apply volumetric fog
 */

#include "/include/main.glsl"
#include "/include/utility/textureSampling.glsl"
#include "/include/utility/spaceConversion.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 3 */
layout (location = 0) out vec3 radiance;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex0; // Translucents
uniform sampler2D colortex2; // Clouds
uniform sampler2D colortex3; // Scene radiance
uniform sampler2D colortex6; // Fog transmittance
uniform sampler2D colortex7; // Fog scattering

uniform sampler2D lodDepthTex0;
uniform sampler2D lodDepthTex1;

//--// Functions //-----------------------------------------------------------//

const float fogRenderScale = 0.01 * FOG_RENDER_SCALE;

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	float backDepth  = linearizeDepth(texelFetch(lodDepthTex1, texel, 0).r);
	float frontDepth = linearizeDepth(texelFetch(lodDepthTex0, texel, 0).r);

	float translucentAlpha = mix(1.0 - texelFetch(colortex0, texel, 0).a, 1.0, frontDepth / backDepth);

	vec2 coord = fogRenderScale * gl_FragCoord.xy - 0.5;

    ivec2 sampleTexel = ivec2(coord);

	vec3 fogScattering = vec3(0.0);
	vec3 fogTransmittance = vec3(0.0);
	float weights = 0.0;

    vec2 fractCoord = -fract(coord);

	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i >> 1, i & 1);

		float sampleDepth = linearizeDepth(texelFetch(lodDepthTex1, ivec2((sampleTexel + offset + 0.5) * rcp(fogRenderScale)), 0).r);
		float sampleWeight = bilinearWeight(fractCoord, vec2(offset)) * max(0.001, exp(-4.0 * abs(sampleDepth - backDepth)));

		fogScattering    += sampleWeight * texelFetch(colortex7, sampleTexel + offset, 0).rgb;
		fogTransmittance += sampleWeight * texelFetch(colortex6, sampleTexel + offset, 0).rgb;
		weights += sampleWeight;
	}

	weights = rcp(max(0.001, weights));

	fogScattering *= weights;
	fogTransmittance *= weights;

	if (eyeAltitude > SEA_LEVEL + 0.95 * CLOUDS_LAYER0_ALTITUDE * CLOUDS_SCALE) {
		float cloudTransmittance = texelFetch(colortex2, texel, 0).z;

		fogScattering *= cloudTransmittance;
		fogTransmittance = mix(vec3(1.0), fogTransmittance, cloudTransmittance);
	}

	if (frontDepth < backDepth) fogScattering *= translucentAlpha;

	radiance = texelFetch(colortex3, texel, 0).rgb;
	radiance = radiance * fogTransmittance + fogScattering;
}