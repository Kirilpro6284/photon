#if !defined INCLUDE_FRAGMENT_RAYTRACER
#define INCLUDE_FRAGMENT_RAYTRACER

#include "/include/utility/geometry.glsl"
#include "/include/utility/spaceConversion.glsl"

float raymarchIntersection (
	inout vec3 rayPos,
	vec3 rayDir,
	float dither,
	const uint intersectionStepCount,
	const uint refinementStepCount
) {
	float hitDist = 0.0;

	vec3 rayStep = rayDir * rcp(float(intersectionStepCount));
	rayPos += dither * rayStep;

	float depthTolerance = 0.002; // Todo: better depth tolerance calculation

	bool hit = false;

	//--// Intersection loop

	for (int i = 0; i < intersectionStepCount; ++i, rayPos += rayStep) {
		float depth = texelFetch(lodDepthTex1, ivec2(rayPos.xy * viewSize), 0).x;

		if (depth > rayPos.z) {
			hit = true;
			hitDist = (i + dither) / float(intersectionStepCount);
			break;
		}
	}

	if (!hit) return 1.0;

	//--// Refinement loop

	float w = 1.0;

	for (int i = 0; i < refinementStepCount; ++i) {
		rayStep *= 0.5;
		w *= 0.5;

		float depth = texelFetch(lodDepthTex1, ivec2(rayPos.xy * viewSize), 0).x;

		if (depth > rayPos.z) {
			rayPos -= rayStep;
			hitDist -= w;
		} else {
			rayPos += rayStep;
			hitDist += w;
		}
	}

	return hitDist;
}

float traceScreenSpaceRay (
	vec3 screenPos,
	vec3 viewPos,
	vec3 viewDir,
	float dither,
	const uint maxIntersectionStepCount,
	const uint refinementStepCount,
	out vec3 hitPos
) {
	if (viewDir.z > 0.0 && viewDir.z >= -viewPos.z) return 1.0;
	
	vec3 screenDir = normalize(viewToScreenSpace(viewPos + viewDir, true) - screenPos);

	float rayLength = intersectBox(screenPos, screenDir, mat2x3(vec3(0.0), vec3(1.0))).y;
	uint intersectionStepCount = uint(float(maxIntersectionStepCount) * (dampen(clamp01(rayLength)) * 0.5 + 0.5));

	vec3 rayDir = screenDir * rayLength;
	hitPos = screenPos;

	return raymarchIntersection(
		hitPos,
		rayDir,
		dither,
		intersectionStepCount,
		refinementStepCount
	);
}

#endif // INCLUDE_FRAGMENT_RAYTRACER
