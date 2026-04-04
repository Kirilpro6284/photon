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

layout (r16f) uniform image2D prevDepthTex;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

flat in vec3 directIrradiance;
flat in vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex0;  // Vanilla sky (sun, moon and custom skies)
uniform sampler2D colortex2; // Clouds history
uniform sampler2D colortex5;  // New cloud sample
uniform sampler2D colortex6; // 4x4 max depth
uniform usampler2D colortex13; // Previous frame depth

uniform sampler3D colortex9; // Atmosphere scattering LUT

uniform sampler2D prevDepthTex1;
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
#include "/include/utility/textureSampling.glsl"

//--// Functions //-----------------------------------------------------------//

#if CLOUDS_TEMPORAL_UPSAMPLING == 1
	const vec2 cloudsRenderScale = vec2(1.0);
	#define checkerboardOffsets ivec2[1](ivec2(0))
#elif CLOUDS_TEMPORAL_UPSAMPLING == 2
	const vec2 cloudsRenderScale = vec2(0.5, 1.0);
	#define checkerboardOffsets checkerboardOffsets2x1
#elif CLOUDS_TEMPORAL_UPSAMPLING == 4
	const vec2 cloudsRenderScale = vec2(0.5);
	#define checkerboardOffsets checkerboardOffsets2x2
#elif CLOUDS_TEMPORAL_UPSAMPLING == 8
	const vec2 cloudsRenderScale = vec2(0.25, 0.5);
	#define checkerboardOffsets checkerboardOffsets4x2
#elif CLOUDS_TEMPORAL_UPSAMPLING == 9
	const vec2 cloudsRenderScale = vec2(1.0 / 3.0);
	#define checkerboardOffsets checkerboardOffsets3x3
#elif CLOUDS_TEMPORAL_UPSAMPLING == 16
	const vec2 cloudsRenderScale = vec2(0.25);
	#define checkerboardOffsets checkerboardOffsets4x4
#elif CLOUDS_TEMPORAL_UPSAMPLING == 25
	const vec2 cloudsRenderScale = vec2(0.2);
	#define checkerboardOffsets checkerboardOffsets5x5
#endif

vec3 reprojectClouds(vec2 coord, float distanceToCloud) {
	const float windSpeed = CLOUDS_LAYER0_WIND_SPEED * CLOUDS_SCALE;
	const float windAngle = CLOUDS_LAYER0_WIND_ANGLE * tau / 360.0;

	vec3 pos = projectAndDivide(gbufferProjectionInverse, vec3(coord, 1.0) * 2.0 - 1.0);
	     pos = mat3(gbufferModelViewInverse) * pos;
	     pos = normalize(pos) * distanceToCloud * CLOUDS_SCALE;

	vec3 velocity  = -cameraVelocity;
	     
	if (advanceTime) velocity += windSpeed * frameTime * vec3(cos(windAngle), sin(windAngle), 0.0).xzy;

	vec4 prevPos = lodProjMatPrev0 * gbufferPreviousModelView * vec4(pos + gbufferModelViewInverse[3].xyz - velocity, 1.0);
	     prevPos.xyz /= prevPos.w;

	return prevPos.w > 0.0 ? vec3(prevPos.xy * 0.5 + 0.5, prevPos.z * -0.5) : vec3(-10.0);
}

vec4 upscaleClouds(ivec2 dstTexel, vec3 screenPos, vec3 scenePos) {
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
			vec4 sampleData = texelFetch(colortex5, clamp(srcTexel + ivec2(x, y), ivec2(0), ivec2(internalScreenSize)), 0);

			aabbMin = min(aabbMin, sampleData);
			aabbMax = max(aabbMax, sampleData);
		}
	}

	aabbMin *= currentScale;
	aabbMax *= currentScale;

	vec3 previousCoord = reprojectClouds(coord, aabbMin.w);
	vec2 previousCoordClamped = clamp(previousCoord.xy, vec2(0.0), 1.0 - sqrt(CLOUDS_TEMPORAL_UPSAMPLING) * internalTexelSize); // Prevent line at edge of screen

	vec4 current = currData;
	vec4 history = textureCatmullRom(colortex2, previousCoordClamped);

	float clampingStrength  = 0.5 * smoothstep(1.0, 3.0, rcp(CLOUDS_SCALE) * length(cameraVelocity));
	      clampingStrength += 0.8 * smoothstep(0.85 * CLOUDS_LAYER0_ALTITUDE * CLOUDS_SCALE, 0.95 * CLOUDS_LAYER0_ALTITUDE * CLOUDS_SCALE, eyeAltitude - SEA_LEVEL);

	history = mix(history, clamp(history, aabbMin, aabbMax), clamp01(clampingStrength));

	float historyDepth = maxOf(vec4(
		maxOf(textureGather(prevDepthTex1, previousCoordClamped + vec2( internalTexelSize.x,  internalTexelSize.y), 0)),
		maxOf(textureGather(prevDepthTex1, previousCoordClamped + vec2(-internalTexelSize.x,  internalTexelSize.y), 0)),
		maxOf(textureGather(prevDepthTex1, previousCoordClamped + vec2( internalTexelSize.x, -internalTexelSize.y), 0)),
		maxOf(textureGather(prevDepthTex1, previousCoordClamped + vec2(-internalTexelSize.x, -internalTexelSize.y), 0))
	));

	float prevDepth    = linearizeDepth(historyDepth);
	float currentDepth = linearizeDepth(screenPos.z);

	bool offscreen = clamp01(previousCoord.xy) != previousCoord.xy;
	bool disoccluded = (linearizeDepth(max0(previousCoord.z)) - prevDepth) > 4.0 || (historyDepth < eps && abs(prevDepth - currentDepth) > 4.0);
	//bool disoccluded = false;

	bool invalidHistory = offscreen || disoccluded || worldAgeChanged || any(isnan(history)) || any(isinf(history));

	if (invalidHistory) {
		vec2 sampleCoord = internalScreenSize * cloudsRenderScale * coord - 0.5;
		ivec2 sampleTexel = ivec2(sampleCoord);

		float altitudeFraction = smoothstep(SEA_LEVEL, SEA_LEVEL + CLOUDS_LAYER0_ALTITUDE, eyeAltitude + scenePos.y) * 0.4 + 0.1;

		vec4 result = vec4(0.0);
		float weights = 0.0;

    	sampleCoord = -fract(sampleCoord);

		for (int i = 0; i < 4; i++) {
			ivec2 offset = ivec2(i >> 1, i & 1);

			float sampleDepth = linearizeDepth(texelFetch(colortex6, sampleTexel + offset, 0).r);
			float sampleWeight = bilinearWeight(sampleCoord, vec2(offset)) * exp(-altitudeFraction * abs(sampleDepth - currentDepth));

			result += sampleWeight * texelFetch(colortex5, sampleTexel + offset, 0);
			weights += sampleWeight;
		}

		current = weights > 0.0001 ? (result * currentScale * rcp(weights)) : vec4(0.0, 0.0, 1.0, 1e6);
		history = current;
	}

	float historyWeight = 0.75;

	// Soften history sample for newer pixels
	vec4 historySmooth = textureBicubic(colortex2, previousCoordClamped);
	     historySmooth = mix(historySmooth, history, clamp01(historyWeight));
		 historySmooth = invalidHistory ? history : historySmooth;

	// Offcenter rejection from Jessie, which is originally from Zombye
	// Reduces blur in motion
	vec2 pixelOffset = 1.0 - abs(2.0 * fract(previousCoord.xy * internalScreenSize) - 1.0);
	historyWeight *= sqrt(max0(pixelOffset.x * pixelOffset.y)) * 0.5 + 0.5;

	// Checkerboard upscaling
	ivec2 offset0 = dstTexel % ivec2(rcp(cloudsRenderScale));
	ivec2 offset1 = checkerboardOffsets[frameCounter % CLOUDS_TEMPORAL_UPSAMPLING];
	if (offset0 != offset1) current = historySmooth;

	current = mix(current, history, historyWeight);
//	current.w = min(current.w, history.w);

	// Update history for next frame
	cloudsHistory = current;

	return current;
}

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	float depth = texelFetch(lodDepthTex1, texel, 0).x;

	vec3 viewPos = screenToViewPos(coord, depth, true);
	vec3 scenePos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 rayDir = normalize(scenePos);

	scenePos += gbufferModelViewInverse[3].xyz;

	vec4 cloudData = upscaleClouds(texel, vec3(coord, depth), scenePos);

	atmosphereScattering = sunIrradiance * getAtmosphereScattering(rayDir, sunDir)
	                     + moonIrradiance * getAtmosphereScattering(rayDir, moonDir) * moonPhaseBrightness;

	radiance = vec3(0.0);

	imageStore(prevDepthTex, texel, vec4(depth, 0.0, 0.0, 1.0));

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
