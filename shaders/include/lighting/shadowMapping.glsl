#if !defined INCLUDE_LIGHTING_SHADOWMAPPING
#define INCLUDE_LIGHTING_SHADOWMAPPING

#define KERNEL_BLUE_NOISE_32
#include "/include/fragment/kernel.glsl"

#include "/include/lighting/shadowDistortion.glsl"

#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/rotation.glsl"

const float shadowTexelSize = rcp(floor(float(shadowMapResolution)));

// Fake, lightmap-based shadows for outside of the shadow distance or when shadow mapping is disabled
float lightmapShadows(float skylight, float NoL, out float sssDepth) {
	sssDepth = (0.15 + 6.0 * (1.0 - skylight)) * clamp01(1.0 - 0.8 * NoL);
	return smoothstep(0.97, 0.99, skylight) * step(0.0, NoL);
}

#ifdef SHADOW
float getBlockerDepth (vec3 shadowViewPos, float dither) {
	const uint stepCount = SHADOW_BLOCKER_SEARCH_STEPS;

	float radius = SHADOW_BLOCKER_SEARCH_RADIUS * shadowProjScale.x;

	float blockerDepth = 0.0;
	float weightSum    = 0.0;

	mat2 samplePhase = getRotationMatrix(tau * dither) * radius;

	vec2 shadowClipPos = shadowViewPos.xy * shadowProjScale.xy;

	for (uint i = 0; i < stepCount; ++i) {
		vec2 coord = distortShadowPos(shadowProjScale.xy * shadowViewPos.xy + samplePhase * blueNoiseDisk[i]) * 0.5 + 0.5;

		blockerDepth += clamp(shadowProjScaleInv.z * (texelFetch(shadowtex0, ivec2(coord * shadowMapResolution), 0).r * 2.0 - 1.0) - shadowViewPos.z, 0.0, SHADOW_MAX_BLOCKER_DEPTH);
	}

	return blockerDepth * rcp(float(stepCount));
}

vec3 shadowSimple(vec3 shadowScreenPos) {
#ifdef SHADOW_COLOR
	float shadow0 = texture(shadowtex0HW, shadowScreenPos);

	if (shadow0 < 1.0 - eps) {
		float shadow1 = texture(shadowtex1HW, shadowScreenPos);
		vec3  color   = texture(shadowcolor0, shadowScreenPos.xy).rgb;

		return shadow0 + shadow1 * color * (1.0 - shadow0);
	} else {
		return vec3(shadow0);
	}
#else
	return vec3(texture(shadowtex1HW, shadowScreenPos));
#endif
}

vec3 shadowSoft(
	vec3 shadowScreenPos,
	vec3 shadowClipPos,
	float penumbraSize,
	float biasAmount,
	float dither
) {
	float kernelRadius = shadowProjScale.x * max(SHADOW_SMOOTHING * biasAmount, penumbraSize);

	uint stepCount = uint(SHADOW_PCF_STEPS_MIN + SHADOW_PCF_STEPS_INCREASE * smoothstep(0.2, 0.4, penumbraSize));
	     stepCount = min(stepCount, SHADOW_PCF_STEPS_MAX);

	mat2 rotateAndScale = getRotationMatrix(tau * dither) * kernelRadius;

	float shadow = 0.0;
	vec3 shadowColor = vec3(0.0);

	// perform first 4 iterations
	for (uint i = 0; i < 4; ++i) {
		vec2 offset = rotateAndScale * blueNoiseDisk[i];
		vec2 coord  = distortShadowPos(shadowClipPos.xy + offset) * 0.5 + 0.5;
		  //   coord /= getShadowDistortionFactor(coord);
		  //   coord  = coord * 0.5 + 0.5;

#ifdef SHADOW_COLOR
		shadow += texture(shadowtex0HW, vec3(coord, shadowScreenPos.z));
#else
		shadow += texture(shadowtex1HW, vec3(coord, shadowScreenPos.z));
#endif
	}

	// exit early if outside shadow
	if (shadow > 4.0 - eps)
		return vec3(0.25 * shadow);

	// perform remaining iterations
	for (uint i = 4; i < stepCount; ++i) {
		vec2 offset = rotateAndScale * blueNoiseDisk[i];
		vec2 coord  = distortShadowPos(shadowClipPos.xy + offset) * 0.5 + 0.5;
		 //    coord /= getShadowDistortionFactor(coord);
		  //   coord  = coord * 0.5 + 0.5;

#ifdef SHADOW_COLOR
		shadow += texture(shadowtex0HW, vec3(coord, shadowScreenPos.z));
#else
		shadow += texture(shadowtex1HW, vec3(coord, shadowScreenPos.z));
#endif
	}

	float perSampleWeight = rcp(float(stepCount));

	// sharpening for small penumbra sizes
	shadow = clamp01(mix(0.5, shadow * perSampleWeight, clamp(SHADOW_SMOOTHING * biasAmount / penumbraSize, 1.0, 1.0 + SHADOW_SMOOTHING)));

#ifdef SHADOW_COLOR
	if (shadow > 1.0 - eps) return vec3(shadow);

	//rotateAndScale *= 0.25;

	// filter colored shadow
	for (uint i = 0; i < stepCount; ++i) {
		vec2 offset = rotateAndScale * blueNoiseDisk[i];
		vec2 coord  = distortShadowPos(shadowClipPos.xy + offset) * 0.5 + 0.5;
		//     coord /= getShadowDistortionFactor(coord);
	//	     coord  = coord * 0.5 + 0.5;

		float shadow = texture(shadowtex1HW, vec3(coord, shadowScreenPos.z));
		vec3  color  = texture(shadowcolor0, coord).rgb;

		shadowColor += shadow * color;
	}

	shadowColor *= perSampleWeight;
#endif

	return shadow + (1.0 - shadow) * shadowColor;
}

vec3 calculateShadows(
	vec3 shadowViewPos,
	vec3 normal,
	uint blockId,
	float cloudShadow,
	float skylight,
	float NoL,
	float dither,
	float blockerDepth
) {
	//vec3 shadowViewPos = transform(shadowModelView, scenePos);
//	vec3 shadowClipPos = ;

	vec2 distortDiff = distortShadowPosDiff(shadowProjScale.xy * shadowViewPos.xy);

	float biasAmount = shadowDistance * rcp(min(distortDiff.x, distortDiff.y) * float(shadowMapResolution));
 	vec3 shadowClipPos = shadowProjScale * (shadowViewPos + mat3(shadowModelView) * normal * (SHADOW_BIAS + biasAmount));

	vec3 shadowScreenPos = vec3(distortShadowPos(shadowClipPos.xy), shadowClipPos.z) * 0.5 + 0.5;

	// fake, lightmap-based shadows for outside of the shadow distance

	float s = 0.0;

	float distantShadow   = lightmapShadows(skylight, NoL, s);
	float distantSssDepth = s;
	if (clamp01(shadowScreenPos) != shadowScreenPos) return vec3(distantShadow);

	// fade into distant shadows in the distance
	float distanceFade = smoothstep(0.45, 0.5, maxOf(abs(shadowScreenPos.xy - 0.5)));
	distantShadow = mix(1.0, distantShadow, distanceFade);

#ifdef SHADOW_LEAK_PREVENTION
	// fade shadow light when skylight access is very low to hide light leaking underground caused
	// by optifine's poor shadow culling. This creates shadows in places where there should be none,
	// like directly under a floating island. Also, it mustn't be applied when looking through bodies
	// of water, otherwise the floor is completely black
	distantShadow *= (blockId == BLOCK_WATER) == (isEyeInWater == 1)
		? smoothstep(0.0, 0.1, skylight)
		: 1.0;
#endif

#if   SHADOW_QUALITY == SHADOW_QUALITY_FAST
	if (NoL < eps) {
		return vec3(0.0);
	} else {
		return shadowSimple(shadowScreenPos) * distantShadow;
	}
#elif SHADOW_QUALITY == SHADOW_QUALITY_FANCY
	//float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);

//	float blockerDepth = blockerSearch(shadowScreenPos, shadowClipPos, dither);

	//sssDepth = blockerDepth;

	// fade into lightmap-based SSS in the distance
	//sssDepth = mix(sssDepth, distantSssDepth, distanceFade);

	if (NoL < eps) return vec3(0.0);
	if (blockerDepth < eps) return vec3(distantShadow); // blocker search empty handed => no occlusion

	return shadowSoft(
		shadowScreenPos,
		shadowClipPos,
		SHADOW_PENUMBRA_SCALE * 0.02 * blockerDepth,
		biasAmount,
		dither
	) * distantShadow;
#endif
}

#else
vec3 calculateShadows(
	vec3 scenePos,
	vec3 normal,
	float NoL,
	float skylight,
	uint blockId,
	out float sssDepth
) {
	return vec3(lightmapShadows(skylight, NoL, sssDepth));
}
#endif

#endif // INCLUDE_LIGHTING_SHADOWMAPPING
