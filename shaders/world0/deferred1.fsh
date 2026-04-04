#version 430 compatibility

/*
 * Program description:
 * Render clouds
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 5,6 */
layout (location = 0) out vec4 cloudData;
layout (location = 1) out float maxDepth;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

flat in vec3 weather;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D noisetex;

uniform sampler2D lodDepthTex1;

uniform sampler3D depthtex0; // 3D worley noise
uniform sampler3D depthtex2; // 3D curl noise

//--// Includes //------------------------------------------------------------//

#include "/include/atmospherics/clouds.glsl"

#include "/include/utility/checkerboard.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/spaceConversion.glsl"
#include "/include/utility/dithering.glsl"

//--// Functions //-----------------------------------------------------------//

#if   CLOUDS_TEMPORAL_UPSAMPLING == 1
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

float depthMax2x2(sampler2D depthSampler) {
	vec2 samplePos = coord * (renderScale * rcp(cloudsRenderScale));
	vec4 depthSamples0 = textureGather(depthSampler, samplePos);
	return minOf(depthSamples0);
}

float depthMax4x2(sampler2D depthSampler) {
	vec2 samplePos = coord * (renderScale * rcp(cloudsRenderScale));

	vec4 depthSamples0 = textureGather(depthSampler, samplePos + vec2( 2.0 * internalTexelSize.x, internalTexelSize.y));
	vec4 depthSamples1 = textureGather(depthSampler, samplePos + vec2(-2.0 * internalTexelSize.x, internalTexelSize.y));

	return min(minOf(depthSamples0), minOf(depthSamples1));
}

float depthMax4x4(sampler2D depthSampler) {
	vec2 samplePos = coord * (renderScale * rcp(cloudsRenderScale));

	vec4 depthSamples0 = textureGather(depthSampler, samplePos + vec2( 2.0 * internalTexelSize.x,  2.0 * internalTexelSize.y));
	vec4 depthSamples1 = textureGather(depthSampler, samplePos + vec2(-2.0 * internalTexelSize.x,  2.0 * internalTexelSize.y));
	vec4 depthSamples2 = textureGather(depthSampler, samplePos + vec2( 2.0 * internalTexelSize.x, -2.0 * internalTexelSize.y));
	vec4 depthSamples3 = textureGather(depthSampler, samplePos + vec2(-2.0 * internalTexelSize.x, -2.0 * internalTexelSize.y));

	return min(
		min(minOf(depthSamples0), minOf(depthSamples1)),
		min(minOf(depthSamples2), minOf(depthSamples3))
	);
}

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);
	ivec2 viewTexel = texel * ivec2(rcp(cloudsRenderScale)) + checkerboardOffsets[frameCounter % CLOUDS_TEMPORAL_UPSAMPLING];

	if (clamp(viewTexel, ivec2(0), ivec2(internalScreenSize) + 1) != viewTexel) { cloudData = vec4(0.0, 0.0, 0.0, 1e6); maxDepth = 0.0; return; }

	// Get maximum depth from area covered by this fragment
#if   CLOUDS_TEMPORAL_UPSAMPLING == 1
	maxDepth = texelFetch(lodDepthTex1, viewTexel, 0).x;
#elif CLOUDS_TEMPORAL_UPSAMPLING == 2 || CLOUDS_TEMPORAL_UPSAMPLING == 4
	maxDepth = depthMax2x2(lodDepthTex1);
#elif CLOUDS_TEMPORAL_UPSAMPLING == 8
	maxDepth = depthMax4x2(lodDepthTex1);
#elif CLOUDS_TEMPORAL_UPSAMPLING == 9 || CLOUDS_TEMPORAL_UPSAMPLING == 16
	maxDepth = depthMax4x4(lodDepthTex1);
#endif

	vec3 viewPos = screenToViewPos(viewTexel * internalTexelSize, maxDepth, false);

	vec3 rayOrigin = vec3(0.0, rcp(CLOUDS_SCALE) * (eyeAltitude - SEA_LEVEL) + planetRadius, 0.0) + rcp(CLOUDS_SCALE) * gbufferModelViewInverse[3].xyz;
	vec3 rayDir    = mat3(gbufferModelViewInverse) * normalize(viewPos);

	vec3 cloudsLightDir = cloudsMoonlit ? moonDir : sunDir;

	float dither = texelFetch(noisetex, ivec2(viewTexel & 511), 0).b;
	      dither = R1(frameCounter / CLOUDS_TEMPORAL_UPSAMPLING, dither);

	cloudData = renderClouds(
		rayOrigin,
		rayDir,
		cloudsLightDir,
		dither,
		(maxDepth > 0.0)
			? length(viewPos) * rcp(CLOUDS_SCALE)
			: -1.0,
		false
	);

	// Scale scattering and apparent distance to fit into a normalized integer format
	cloudData.xyz = clamp01(vec3(cloudData.xy * 1e-2, cloudData.z) + rcp(65535.0) * getInterleavedGradientNoise(gl_FragCoord.xy, frameCounter / CLOUDS_TEMPORAL_UPSAMPLING) - 0.5 * rcp(65535.0));
	cloudData.w  = clamp01(cloudData.w  * 1e-6);
}
