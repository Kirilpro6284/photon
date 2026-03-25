#version 430 compatibility

/*
 * Program description:
 * Render sky
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 3,7,2,4 */
layout (location = 0) out vec3 radiance;
layout (location = 1) out vec3 atmosphereScattering;
layout (location = 2) out vec4 cloudsHistory;
layout (location = 3) out uint cloudsPixelAge;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

flat in vec3 directIrradiance;
flat in vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex0;  // Vanilla sky (sun, moon and custom skies)
uniform sampler2D colortex5;  // New cloud sample
uniform sampler2D colortex2; // Clouds history
uniform usampler2D colortex4; // Clouds pixel age
uniform sampler2D colortex13; // Previous frame depth

uniform sampler3D colortex9; // Atmosphere scattering LUT

uniform sampler2D lodDepthTex1;

//--// Includes //------------------------------------------------------------//

#define WORLD_OVERWORLD

#define ATMOSPHERE_SCATTERING_LUT colortex9

#include "/block.properties"
#include "/entity.properties"

#include "/include/atmospherics/atmosphere.glsl"
#include "/include/atmospherics/sky.glsl"

#include "/include/fragment/aces/matrices.glsl"
#include "/include/fragment/fog.glsl"

#include "/include/utility/bicubic.glsl"
#include "/include/utility/checkerboard.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/spaceConversion.glsl"

//--// Functions //-----------------------------------------------------------//

#if CLOUDS_UPSCALING_FACTOR == 1
	const vec2 cloudsRenderScale = vec2(1.0);
	#define checkerboardOffsets ivec2[1](ivec2(0))
#elif CLOUDS_UPSCALING_FACTOR == 2
	const vec2 cloudsRenderScale = vec2(0.5, 1.0);
	#define checkerboardOffsets checkerboardOffsets2x1
#elif CLOUDS_UPSCALING_FACTOR == 4
	const vec2 cloudsRenderScale = vec2(0.5);
	#define checkerboardOffsets checkerboardOffsets2x2
#elif CLOUDS_UPSCALING_FACTOR == 8
	const vec2 cloudsRenderScale = vec2(0.25, 0.5);
	#define checkerboardOffsets checkerboardOffsets4x2
#elif CLOUDS_UPSCALING_FACTOR == 9
	const vec2 cloudsRenderScale = vec2(1.0 / 3.0);
	#define checkerboardOffsets checkerboardOffsets3x3
#elif CLOUDS_UPSCALING_FACTOR == 16
	const vec2 cloudsRenderScale = vec2(0.25);
	#define checkerboardOffsets checkerboardOffsets4x4
#endif

vec3 reprojectClouds(vec2 coord, float distanceToCloud) {
	const float windSpeed = CLOUDS_LAYER0_WIND_SPEED / CLOUDS_SCALE;
	const float windAngle = CLOUDS_LAYER0_WIND_ANGLE * tau / 360.0;

	vec3 pos = projectAndDivide(gbufferProjectionInverse, vec3(coord, 1.0) * 2.0 - 1.0);
	     pos = mat3(gbufferModelViewInverse) * pos;
	     pos = normalize(pos) * distanceToCloud * rcp(CLOUDS_SCALE);

	vec3 velocity  = -cameraVelocity;
	     
	if (advanceTime) velocity += windSpeed * frameTime * vec3(cos(windAngle), sin(windAngle), 0.0).xzy;

	vec4 prevPos = lodProjMatPrev0 * gbufferPreviousModelView * vec4(pos + gbufferModelViewInverse[3].xyz - velocity, 1.0);
	     prevPos.xyz /= prevPos.w;

	return prevPos.w > 0.0 ? vec3(prevPos.xy * 0.5 + 0.5, prevPos.z * -0.5) : vec3(-10.0);
}

vec4 upscaleClouds(ivec2 dstTexel, vec3 positionScreen) {
	/*
	 * x: sunlight
	 * y: skylight
	 * z: transmittance
	 * w: apparent distance
	 */

	// Scales new sample values back to its actual range
	const vec4 currentScale = vec4(1e2, 1e2, 1.0, 1e6);

	ivec2 srcTexel = ivec2(dstTexel * cloudsRenderScale);

	vec4 currData = texelFetch(colortex5, srcTexel, 0) * currentScale;

	vec4 aabbMin = vec4(1.0); 
	vec4 aabbMax = vec4(0.0);

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec4 sampleData = texelFetch(colortex5, srcTexel + ivec2(x, y), 0);

			aabbMin = min(aabbMin, sampleData);
			aabbMax = max(aabbMax, sampleData);
		}
	}

	aabbMin *= currentScale;
	aabbMax *= currentScale;

	vec3 previousCoord = reprojectClouds(coord, currData.w);
	vec2 previousCoordClamped = clamp(previousCoord.xy, vec2(0.0), 1.0 - sqrt(CLOUDS_UPSCALING_FACTOR) * viewTexelSize); // Prevent line at edge of screen

	vec4 current = currData;
	vec4 history = textureCatmullRom(colortex2, previousCoordClamped);

	float clampingStrength = smoothstep(0.9 * CLOUDS_LAYER0_ALTITUDE * rcp(CLOUDS_SCALE), 0.95 * CLOUDS_LAYER0_ALTITUDE * rcp(CLOUDS_SCALE), eyeAltitude - SEA_LEVEL);

	history.rgb = mix(history.rgb, clamp(history.rgb, aabbMin.rgb, aabbMax.rgb), clampingStrength);
	history.w = clamp(history.w, aabbMin.w, aabbMax.w);

	float historyDepth = maxOf(vec4(
		maxOf(textureGather(colortex13, previousCoordClamped + 0.5 * vec2( viewTexelSize.x,  viewTexelSize.y), 1)),
		maxOf(textureGather(colortex13, previousCoordClamped + 0.5 * vec2(-viewTexelSize.x,  viewTexelSize.y), 1)),
		maxOf(textureGather(colortex13, previousCoordClamped + 0.5 * vec2( viewTexelSize.x, -viewTexelSize.y), 1)),
		maxOf(textureGather(colortex13, previousCoordClamped + 0.5 * vec2(-viewTexelSize.x, -viewTexelSize.y), 1))
	));

	bool offscreen = clamp01(previousCoord.xy) != previousCoord.xy;
	bool disoccluded = previousCoord.z > 0.0 && (linearizeDepth(previousCoord.z) - linearizeDepth(historyDepth) > 10.0);

	bool invalidHistory = offscreen || disoccluded || worldAgeChanged || any(isnan(history)) || any(isinf(history));

	uint pixelAge = texelFetch(colortex4, ivec2(previousCoord.xy * viewSize * cloudsRenderScale), 0).x;

	if (invalidHistory) {
		current = textureBicubic(colortex5, coord * cloudsRenderScale) * currentScale;
		history = current;
		pixelAge = 0;
	}

	float accumulationLimit = 0.8;

	float x = float(pixelAge);
	float historyWeight = min(x / (x + 1.0), accumulationLimit);

	// Soften history sample for newer pixels
	vec4 historySmooth = textureBicubic(colortex2, previousCoordClamped);
	     historySmooth = mix(historySmooth, history, clamp01(historyWeight));
		 historySmooth = invalidHistory ? history : historySmooth;

	// Offcenter rejection from Jessie, which is originally from Zombye
	// Reduces blur in motion
	vec2 pixelOffset = 1.0 - abs(2.0 * fract(previousCoord.xy * viewSize) - 1.0);
	historyWeight *= sqrt(max0(pixelOffset.x * pixelOffset.y)) * 0.5 + 0.5;

	// Velocity rejection
	historyWeight *= exp(-0.1 * CLOUDS_SCALE * length(cameraVelocity));

	// Checkerboard upscaling
	ivec2 offset0 = dstTexel % ivec2(rcp(cloudsRenderScale));
	ivec2 offset1 = checkerboardOffsets[frameCounter % CLOUDS_UPSCALING_FACTOR];
	if (offset0 != offset1 && pixelAge > 1u) current = historySmooth;

	current.rgb = mix(current.rgb, history.rgb, historyWeight);
	current.w = min(history.w, current.w);

	// Update history for next frame
	cloudsHistory = current;
	cloudsPixelAge = min(pixelAge + 1, 254);

	return vec4(current.rgb, mix(currData.w, history.w, 0.8));
}

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	float depth = texelFetch(lodDepthTex1, texel, 0).x;

	vec3 positionScreen = vec3(coord, 1.0);
	vec3 positionView = screenToViewPos(coord, 1.0, true);
	vec3 rayDir = mat3(gbufferModelViewInverse) * normalize(positionView);

	vec4 cloudData = upscaleClouds(texel, vec3(coord, depth));

	atmosphereScattering = sunIrradiance * getAtmosphereScattering(rayDir, sunDir)
	                     + moonIrradiance * getAtmosphereScattering(rayDir, moonDir) * moonPhaseBrightness;

	radiance = vec3(0.0);

	if (depth == 0.0) {

		/* -- space -- */

		vec4 vanillaSky = texelFetch(colortex0, ivec2(gl_FragCoord.xy), 0); // Sun, moon and custom skies
		vec3 vanillaSkyColor = srgbToLinear(vanillaSky.rgb) * r709ToAp1Unlit;
		uint vanillaSkyId = uint(vanillaSky.a + 0.5);

	#ifdef VANILLA_SUN
		if (vanillaSkyId == 2) {
			const vec3 brightnessScale = 5.0 * sunIrradiance;
			radiance += vanillaSkyColor * brightnessScale;
		}
	#else
		radiance += drawSun(rayDir);
	#endif

	#ifdef VANILLA_MOON
		if (vanillaSkyId == 3) {
			const vec3 brightnessScale = 5.0 * moonIrradiance;
			radiance += vanillaSkyColor * brightnessScale;
		}
	#else
		radiance += drawMoon(rayDir);
	#endif

	#ifdef STARS
		radiance += drawStars(rayDir);
	#endif

		/* -- atmosphere -- */

		vec3 atmosphereTransmittance = getAtmosphereTransmittance(rayDir.y, planetRadius);

		radiance = radiance * atmosphereTransmittance + atmosphereScattering;
	}

	/* -- clouds -- */

	const vec3 cloudsLightningFlash = vec3(10.0);

	vec3 cloudsScattering = mat2x3(directIrradiance, skyIrradiance + cloudsLightningFlash * lightningFlash) * cloudData.xy;
	     cloudsScattering = cloudsAerialPerspective(cloudsScattering, cloudData.rgb, rayDir, atmosphereScattering, cloudData.w);

	radiance = radiance * cloudData.z + cloudsScattering;

	// fade lower part of sky into cave fog color when underground so that the sky isn't visible
	// beyond the render distance
	float undergroundSkyFade = biomeCave * smoothstep(-0.1, 0.1, 0.4 - rayDir.y);
	radiance = mix(radiance, caveFogColor, undergroundSkyFade);

	radiance *= 1.0 - blindness;
}
