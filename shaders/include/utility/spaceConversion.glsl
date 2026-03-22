#if !defined INCLUDE_UTILITY_SPACECONVERSION
#define INCLUDE_UTILITY_SPACECONVERSION

float linearizeDepth(float depth) {
	// https://wiki.shaderlabs.org/wiki/Shader_tricks#Linearizing_depth
	return (near * far) / (depth * (near - far) + far);
}

float reverseLinearDepth(float linearZ) {
	return (far + near) / (far - near) + (2.0 * far * near) / (linearZ * (far - near));
}

vec3 screenToViewPos (vec2 uv, float depth) {
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;

	return projectAndDivide(gbufferProjectionInverse, vec3(ndc.xy - taa_offset, ndc.z));
}

vec3 viewToScreenSpace(vec3 viewPos, bool handleJitter) {
	vec3 positionNdc = projectAndDivide(gbufferProjection, viewPos);

#ifdef TAA
	if (handleJitter) positionNdc.xy += taa_offset;
#endif

	return positionNdc * 0.5 + 0.5;
}

vec3 viewToSceneSpace(vec3 viewPos) {
	return transform(gbufferModelViewInverse, viewPos);
}

vec3 sceneToViewSpace(vec3 scenePos) {
	return transform(gbufferModelView, scenePos);
}

mat3 getTbnMatrix(vec3 normal) {
	vec3 tangent = normal.y == 1.0 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), normal));
	vec3 bitangent = normalize(cross(tangent, normal));
	return mat3(tangent, bitangent, normal);
}

#if defined TEMPORAL_REPROJECTION
vec3 reprojectSceneSpace(vec3 scenePos, bool isHand) {
	vec3 cameraOffset = isHand
		? vec3(0.0)
		: cameraPosition - previousCameraPosition;

	vec3 previousPos = transform(gbufferPreviousModelView, scenePos + cameraOffset);
	     previousPos = projectAndDivide(gbufferPreviousProjection, previousPos);

	return previousPos * 0.5 + 0.5;
}

vec3 reproject(vec3 screenPos) {
	vec3 pos = projectAndDivide(gbufferProjectionInverse, screenPos * 2.0 - 1.0);
	     pos = viewToSceneSpace(pos);

	bool isHand = screenPos.z < handDepth;

	return reprojectSceneSpace(pos, isHand);
}
#endif

#endif // INCLUDE_UTILITY_SPACECONVERSION
