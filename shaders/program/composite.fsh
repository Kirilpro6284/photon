/*
 * Program description:
 * Blend solid and translucent layers, apply effects behind water
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 3 */
layout (location = 0) out vec3 radiance;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex0;  // Translucent layer
uniform sampler2D colortex3;  // Solid layer + sky
uniform sampler2D skyCapture;  // Sky capture
uniform sampler2D colortex7;  // Sky color
uniform sampler2D colortex9;  // Water mask
uniform sampler2D colortex2; // Clouds
uniform sampler2D colortex15; // Cloud shadow map
uniform sampler2D colortex16; // Voxy translucents
uniform sampler2D colortex17; // Voxy water mask

uniform sampler2D depthtex0;

uniform sampler2D lodDepthTex0;
uniform sampler2D lodDepthTex1;

//--// Includes //------------------------------------------------------------//

#include "/include/atmospherics/sky.glsl"

#include "/include/fragment/aces/matrices.glsl"
#include "/include/fragment/waterVolume.glsl"

#include "/include/lighting/cloudShadows.glsl"

#include "/include/utility/color.glsl"
#include "/include/utility/fastMath.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/spaceConversion.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	/* -- texture fetches -- */

	float backDepth   = texelFetch(lodDepthTex1,  texel, 0).x;
	float frontDepth  = max(backDepth, texelFetch(lodDepthTex0,  texel, 0).x);
	radiance          = texelFetch(colortex3,  texel, 0).rgb;
	vec3 clearSky     = texelFetch(colortex7,  texel, 0).rgb;
	vec4 clouds       = texelFetch(colortex2, texel, 0);

#ifdef VOXY
	vec4 translucents;
	vec4 waterMask;

	if (texelFetch(depthtex0, texel, 0).r == 1.0) {
		translucents = texelFetch(colortex16,  texel, 0);
	 	waterMask    = texelFetch(colortex17,  texel, 0);
	} else {
	 	translucents = texelFetch(colortex0,  texel, 0);
	 	waterMask    = texelFetch(colortex9,  texel, 0);
	}
#else
	vec4 translucents = texelFetch(colortex0,  texel, 0);
	vec4 waterMask    = texelFetch(colortex9,  texel, 0);
#endif

	/* -- fetch lighting palette -- */

	vec3 ambientIrradiance = texelFetch(skyCapture, ivec2(255, 0), 0).rgb;
	vec3 directIrradiance  = texelFetch(skyCapture, ivec2(255, 1), 0).rgb;
	vec3 skyIrradiance     = texelFetch(skyCapture, ivec2(255, 2), 0).rgb;

	/* -- transformations -- */

	vec3 screenPos = vec3(coord, frontDepth);
	vec3 viewPos   = screenToViewPos(coord, frontDepth, true);
	vec3 scenePos  = viewToSceneSpace(viewPos);

	float viewerDistance = length(viewPos);
	vec3 viewerDir = (gbufferModelViewInverse[3].xyz - scenePos) * rcp(viewerDistance);

	/* -- underwater effects -- */

	if (waterMask.a > 0.5) {
		vec2 normalTangentXy       = unpackUnorm2x8(waterMask.x) * 2.0 - 1.0;
		vec2 lightingInfo          = unpackUnorm2x8(waterMask.y);
		float distanceToWater      = waterMask.z * renderDistance;

		// water refraction

#ifdef WATER_REFRACTION
		const float refractionStrength = 0.5;
		vec2 refractedCoord = coord + normalTangentXy * (refractionStrength * rcp(max(distanceToWater, 1.0)));

		radiance         = texture(colortex3, refractedCoord).rgb;
		backDepth        = texture(lodDepthTex1, refractedCoord * renderScale).x;
		vec3 backPosView = screenToViewPos(refractedCoord, backDepth, true);
#endif

		// water volume

		float distanceThroughWater = max0(length(backPosView) - distanceToWater) * float(isEyeInWater != 1);
		float LoV = dot(viewerDir, shadowDir);
		float sssDepth = lightingInfo.x * 32.0;
		float skylight = lightingInfo.y;
		float cloudShadow = getCloudShadows(colortex15, scenePos);

		mat2x3 waterVolume = getSimpleWaterVolume(
			directIrradiance,
			skyIrradiance,
			ambientIrradiance,
			distanceThroughWater,
			LoV,
			sssDepth,
			skylight,
			cloudShadow
		);

		radiance = radiance * waterVolume[1] + waterVolume[0];
	}

	/* -- blend layers -- */

	radiance = radiance * (1.0 - translucents.a) + translucents.rgb;

	/* -- blend with clouds -- */

	if (backDepth > 0.0 && clouds.w < viewerDistance * CLOUDS_SCALE) {
		const float cloudsLightningFlash = 10.0;

		vec3 rayOrigin = vec3(0.0, planetRadius + 400.0, 0.0);
		vec3 rayDir = cloudsMoonlit ? moonDir : sunDir;

		vec3 cloudsDirectIrradiance  = cloudsMoonlit ? moonIrradiance * moonPhaseBrightness : sunIrradiance;
			 cloudsDirectIrradiance *= getAtmosphereTransmittance(rayOrigin, rayDir) * smoothstep(0.0, 0.02, abs(sunDir.y + 0.02));
			 cloudsDirectIrradiance *= 1.0 - pulse(float(worldTime), 12850.0, 50.0) - pulse(float(worldTime), 23150.0, 50.0);

		vec3 cloudsScattering = mat2x3(cloudsDirectIrradiance, skyIrradiance + cloudsLightningFlash * lightningFlash) * clouds.xy;

		radiance = radiance * clouds.z + cloudsScattering;
	}
}
