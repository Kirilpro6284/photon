/*
 * Program description:
 * Perform temporal anti-aliasing/upscaling, store global exposure for later
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 8,14 */
layout (location = 0) out vec4 result;
layout (location = 1) out float temporalDepth;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

flat in float globalExposure;

#if DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
flat in vec4[HISTOGRAM_BINS / 4] histogramPdf;
flat in float histogramSelectedBin;
#endif

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex3;  // Scene radiance
uniform sampler2D colortex5;  // Responsive AA flag
uniform sampler2D colortex6;  // AABB min
uniform sampler2D colortex7;  // AABB max
uniform sampler2D colortex8;  // Scene history

uniform sampler2D lodDepthTex1;

//--// Includes //------------------------------------------------------------//

#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fastMath.glsl"
#include "/include/utility/textureSampling.glsl"
#define TEMPORAL_REPROJECTION
#include "/include/utility/spaceConversion.glsl"

//--// Functions //-----------------------------------------------------------//

/*
const bool colortex3MipmapEnabled = true;
*/

vec3 getClosestFragment(ivec2 texel, float depth) {
	ivec2 texel1 = texel + ivec2(-2, -2);
	ivec2 texel2 = texel + ivec2( 2, -2);
	ivec2 texel3 = texel + ivec2(-2,  2);
	ivec2 texel4 = texel + ivec2( 2,  2);

	float depth1 = texelFetch(lodDepthTex1, texel1, 0).x;
	float depth2 = texelFetch(lodDepthTex1, texel2, 0).x;
	float depth3 = texelFetch(lodDepthTex1, texel3, 0).x;
	float depth4 = texelFetch(lodDepthTex1, texel4, 0).x;

	vec3 pos  = depth  > depth1 ? vec3(texel,  depth ) : vec3(texel1, depth1);
	vec3 pos1 = depth2 > depth3 ? vec3(texel2, depth2) : vec3(texel3, depth3);
	     pos  = pos.z  > pos1.z ? pos : pos1;
	     pos  = pos.z  > depth4 ? pos : vec3(texel4, depth4);

	return vec3((pos.xy + 0.5) * internalTexelSize, pos.z);
}

// AABB clipping from "Temporal Reprojection Anti-Aliasing in INSIDE"
vec3 clipAabb(vec3 q, vec3 aabbMin, vec3 aabbMax, out bool clipped) {
    vec3 pClip = 0.5 * (aabbMax + aabbMin);
    vec3 eClip = 0.5 * (aabbMax - aabbMin);

    vec3 vClip = q - pClip;
    vec3 vUnit = vClip / eClip;
    vec3 aUnit = abs(vUnit);
    float maUnit = maxOf(aUnit);

	clipped = maUnit > 1.0;
    return clipped ? pClip + vClip / maUnit : q;
}

// Flicker reduction using "distance to clamp" method from "High Quality Temporal Supersampling" by
// Brian Karis
// Many thanks to Bálint Csala for helping me to figure this out
float distanceToClip(vec3 history, vec3 aabbMin, vec3 aabbMax) {
	const float flickerSensitivity = 5.0;

	vec3 minOffset = (history - aabbMin);
	vec3 maxOffset = (aabbMax - history);

	float distanceToClip = length(min(minOffset, maxOffset)) * globalExposure * flickerSensitivity;
	return clamp01(distanceToClip);
}

#if DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
void drawHistogram(ivec2 texel) {
	const int width = 512;
	const int height = 256;

	const vec3 backgroundColor = vec3(1.0);
	const vec3 histogramColor  = vec3(0.0);
	const vec3 averageBinColor = vec3(1.0, 0.0, 0.0);

	vec2 coord = texel / vec2(width, height);

	if (all(lessThan(texel, ivec2(width, height)))) {
		int index = int(HISTOGRAM_BINS * coord.x);
		float threshold = coord.y;

		result.rgb = histogramPdf[index >> 2][index & 3] > threshold
			? histogramColor
			: backgroundColor;

		float averageBinMask = max0(1.0 - abs(index - histogramSelectedBin));
		result.rgb = mix(result.rgb, averageBinColor, averageBinMask) / globalExposure;
	}
}
#endif

void main() {
	ivec2 dstTexel = ivec2(gl_FragCoord.xy);
	ivec2 srcTexel = ivec2(gl_FragCoord.xy * renderScale);

	float depth = texelFetch(lodDepthTex1, srcTexel, 0).x;

#ifdef TAA
	vec2 adjustedCoord = clamp01(coord + 0.5 * taa_offset);

	vec3 closest = getClosestFragment(srcTexel, depth);
	vec2 velocity = closest.xy - reproject(closest).xy;
	vec2 previousCoord = coord - velocity;

#if TAA_UPSCALING_FACTOR > 1
	float confidence; // Confidence-of-quality factor, see "A Survey of Temporal Antialiasing Techniques" section 5.1
	vec3 current = textureCatmullRom(colortex3, adjustedCoord, confidence).rgb;
	if (minOf(current) < 0.0) current = texture(colortex3, adjustedCoord).rgb;// fix black outline around very bright objects
#else
	vec3 current = texelFetch(colortex3, srcTexel, 0).rgb;
#endif
	vec4 history = textureCatmullRom(colortex8, previousCoord);

	float pixelAge  = (previousCoord.x < 5.5 * texelSize.x && previousCoord.y < 1.5 * texelSize.y) ? 8.0 : history.a;
	      pixelAge *= float(clamp01(previousCoord) == previousCoord);
		  pixelAge += 1.0;
		  pixelAge  = clamp(pixelAge, 1.0, TAA_HISTORY_W_CLAMP);

	if (any(isnan(history)) || pixelAge <= 2.0) history.rgb = current;

	// Interpolate AABB bounds across pixels
	vec3 aabbMin = texture(colortex6, adjustedCoord).rgb;
	vec3 aabbMax = texture(colortex7, adjustedCoord).rgb;

	// Increases responsiveness behind translucents at the expense of quality
	vec3 depthTaaInfo = texture(colortex5, adjustedCoord).xyz;
	float responsiveAa = depthTaaInfo.x;

#ifndef TAA_SKIP_CLIPPING
	bool historyClipped;

	// Perform AABB clipping in YCoCg space, which results in a tighter AABB because luminance (Y)
	// is separated from chrominance (CoCg) as its own axis
	history.rgb = rgbToYcocg(history.rgb);
	history.rgb = clipAabb(history.rgb, aabbMin, aabbMax, historyClipped);

	float flickerReduction = historyClipped ? 0.0 : distanceToClip(history.rgb, aabbMin, aabbMax);

	history.rgb = ycocgToRgb(history.rgb);
#endif

	// Offcenter rejection from Jessie, which is originally from Zombye
	// Reduces blur in motion
	vec2 pixelOffset = 1.0 - abs(2.0 * fract(screenSize * previousCoord) - 1.0);
	float offcenterRejection = sqrt(pixelOffset.x * pixelOffset.y) * TAA_OFFCENTER_REJECTION + (1.0 - TAA_OFFCENTER_REJECTION);

	// Dynamic blend weight lending equal weight to all frames in the history, drastically reduces
	// time taken to converge when upscaling
	float alpha = 1.0 / pixelAge;

#if TAA_UPSCALING_FACTOR > 1
	alpha *= pow(confidence, TAA_CONFIDENCE_REJECTION * sqr(offcenterRejection));
#endif

#ifndef TAA_SKIP_CLIPPING
	alpha *= 1.0 - TAA_FLICKER_REDUCTION * flickerReduction;
#endif

	alpha  = mix(alpha, 0.125, responsiveAa);

	alpha  = 1.0 - alpha;
	alpha *= offcenterRejection;
	alpha  = 1.0 - alpha;

	result.rgb = mix(history.rgb, current, alpha);
	result.a   = pixelAge * offcenterRejection; // recover more quickly

	// Calculate temporally stable linear depth

	vec2 unpack = unpackHalf2x16((uint(depthTaaInfo.y * 65535.0 + 0.5) << 16u) | uint(depthTaaInfo.z * 65535.0 + 0.5));

	temporalDepth = clamp(temporalDepth, reverseLinearDepth(unpack.x), reverseLinearDepth(unpack.y));
	temporalDepth = mix(temporalDepth, linearizeDepth(depth), alpha);
#else
	result.rgb = texelFetch(colortex3, srcTexel, 0).rgb;
	temporalDepth = linearizeDepth(depth);
#endif

#if DEBUG_VIEW == DEBUG_VIEW_HISTOGRAM
	drawHistogram(dstTexel);
#endif

	// Store globalExposure in the alpha component of the bottom left texel of the history buffer
	if (dstTexel == ivec2(0)) result.a = globalExposure;
	else if (dstTexel.x <= 4 && dstTexel.y == 0) result.a = texelFetch(colortex8, dstTexel, 0).a;
}
