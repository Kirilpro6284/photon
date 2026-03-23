#version 430 compatibility

/*
 * Program description:
 * Render sky from all directions into 256x128 sky capture for reflections and directional skylight
 * Store lighting color palette and dynamic weather properties
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

writeonly uniform image2D imgSkyCapture;

/* RENDERTARGETS: 15 */
layout (location = 0) out vec4 colortex15Out;

//--// Inputs //--------------------------------------------------------------//

flat in vec3 weather;
flat in vec3 cloudsDirectIrradiance;

flat in vec3 ambientIrradiance;
flat in vec3 directIrradiance;
flat in vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D noisetex;

uniform sampler2D colortex15;

uniform sampler3D colortex9; // Atmosphere scattering LUT

uniform sampler3D depthtex0; // 3D worley noise
uniform sampler3D depthtex2; // 3D curl noise

//--// Includes //------------------------------------------------------------//

#define WORLD_OVERWORLD
#define PROGRAM_SKY_CAPTURE
#define ATMOSPHERE_SCATTERING_LUT colortex9

#include "/block.properties"
#include "/entity.properties"

#include "/include/atmospherics/atmosphere.glsl"
#include "/include/atmospherics/clouds.glsl"
#include "/include/atmospherics/sky.glsl"
#include "/include/atmospherics/skyProjection.glsl"
#include "/include/utility/encoding.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	colortex15Out = texelFetch(colortex15, texel, 0);

	if (gl_FragCoord.x > 256.0 || gl_FragCoord.y > 128.0) return;

	vec3 radiance = vec3(0.0);

	if (texel.x == skyCaptureRes.x) {
		switch (texel.y) {
		case 0:
			radiance = ambientIrradiance;
			break;

		case 1:
			radiance = directIrradiance;
			break;

		case 2:
			radiance = skyIrradiance;
			break;
		}
	} else {
		vec2 coord = rcp(vec2(256.0, 128.0)) * gl_FragCoord.xy;

		vec3 rayDir = unprojectSky(coord);

		/* -- atmosphere -- */

		vec3 atmosphereScattering = sunIrradiance * getAtmosphereScattering(rayDir, sunDir)
		                          + moonIrradiance * getAtmosphereScattering(rayDir, moonDir) * moonPhaseBrightness;

		vec3 atmosphereTransmittance = getAtmosphereTransmittance(rayDir.y, planetRadius);

		radiance = atmosphereScattering;

		/* -- clouds -- */

		vec3 rayOrigin = vec3(0.0, CLOUDS_SCALE * 16.0 + planetRadius, 0.0) + CLOUDS_SCALE;

		vec3 cloudsLightDir = cloudsMoonlit ? moonDir : sunDir;

		vec4 cloudData = renderClouds(rayOrigin, rayDir, cloudsLightDir, 0.5, -1.0, true);

		const vec3 cloudsLightningFlash = vec3(10.0);

		vec3 cloudsScattering = mat2x3(cloudsDirectIrradiance, skyIrradiance + cloudsLightningFlash * lightningFlash) * cloudData.xy;
		     cloudsScattering = cloudsAerialPerspective(cloudsScattering, cloudData.rgb, rayDir, atmosphereScattering, cloudData.w);

		#define cloudsTransmittance cloudData.z

		radiance = radiance * cloudsTransmittance + cloudsScattering;
	}

	imageStore(imgSkyCapture, texel, vec4(radiance, 1.0));
}
