#if !defined INCLUDE_UTILITY_SPACECONVERSION
#define INCLUDE_UTILITY_SPACECONVERSION

float linearizeDepth(float depth) {
	depth *= -2.0;

	return -(lodProjMatInv_2.z * depth + lodProjMatInv_3.z) / (lodProjMatInv_2.w * depth + lodProjMatInv_3.w);
}

float reverseLinearDepth(float linearZ) {
	return -0.5 * (lodProjMat_2.z * -linearZ + lodProjMat_3.z) / (lodProjMat_2.w * -linearZ);
}

vec3 screenToViewPos (vec2 uv, float depth, bool handleJitter) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth * -2.0);

#ifdef TAA
	if (handleJitter) ndc.xy -= taa_offset;
#endif

	return projectAndDivide(lodProjMatInv0, vec3(ndc.xy, ndc.z));
}

vec3 viewToScreenSpace(vec3 viewPos, bool handleJitter) {
	vec3 ndc = projectAndDivide(lodProjMat0, viewPos);

#ifdef TAA
	if (handleJitter) ndc.xy += taa_offset;
#endif

	return vec3(ndc.xy * 0.5 + 0.5, ndc.z * -0.5);
}

vec3 viewToSceneSpace(vec3 viewPos) {
	return transform(gbufferModelViewInverse, viewPos);
}

vec3 sceneToViewSpace(vec3 scenePos) {
	return transform(gbufferModelView, scenePos);
}

mat3 tbnNormalTangent (vec3 normal, vec4 tangent) {
    return mat3(tangent.xyz, cross(tangent.xyz, normal) * sign(tangent.w), normal);
}

mat3 tbnNormal (vec3 normal) {
    return tbnNormalTangent(normal, vec4(normalize(cross(normal, abs(normal.y) > abs(normal.z) ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0))), 1.0));
}

#if defined TEMPORAL_REPROJECTION
vec3 reprojectSceneSpace(vec3 scenePos) {
	vec3 cameraOffset = step(0.08, dot(scenePos, scenePos)) * cameraVelocity;

	vec3 previousPos = transform(gbufferPreviousModelView, scenePos + cameraOffset);
	     previousPos = projectAndDivide(lodProjMatPrev0, previousPos);

	return vec3(previousPos.xy * 0.5 + 0.5, previousPos.z * -0.5);
}

vec3 reproject(vec3 screenPos) {
	vec3 pos = projectAndDivide(lodProjMatInv0, vec3(screenPos.xy * 2.0 - 1.0, screenPos.z * -2.0));
	     pos = viewToSceneSpace(pos);

	return reprojectSceneSpace(pos);
}
#endif

#endif // INCLUDE_UTILITY_SPACECONVERSION
