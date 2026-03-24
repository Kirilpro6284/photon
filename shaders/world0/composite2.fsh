#version 430 compatibility

/*
 * Program description
 * Apply volumetric fog
 */

#include "/include/main.glsl"
#include "/include/utility/textureSampling.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 3 */
layout (location = 0) out vec3 radiance;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex2; // Clouds;
uniform sampler2D colortex3; // Scene radiance
uniform sampler2D colortex6; // Fog transmittance
uniform sampler2D colortex7; // Fog scattering

//--// Functions //-----------------------------------------------------------//

const float fogRenderScale = 0.01 * FOG_RENDER_SCALE;

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	vec3 fogScattering = textureSmooth(colortex7, coord * fogRenderScale, viewSize).rgb;
	vec3 fogTransmittance = textureSmooth(colortex6, coord * fogRenderScale, viewSize).rgb;

	if (eyeAltitude > SEA_LEVEL + 0.95 * CLOUDS_LAYER0_ALTITUDE / CLOUDS_SCALE) {
		float cloudTransmittance = texelFetch(colortex2, texel, 0).z;

		fogScattering *= cloudTransmittance;
		fogTransmittance = mix(vec3(1.0), fogTransmittance, cloudTransmittance);
	}

	radiance = texelFetch(colortex3, texel, 0).rgb;
	radiance = radiance * fogTransmittance + fogScattering;
}