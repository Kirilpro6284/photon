#if !defined INCLUDE_LIGHTING_CloudShadows
#define INCLUDE_LIGHTING_CloudShadows

#include "/include/utility/bicubic.glsl"

const ivec2 cloudShadowTileRes = ivec2(256);
const ivec2 cloudShadowMapRes = ivec2(512);

const float cloudShadowIntensity = 0.95;

vec3 projectCloudShadowMap (vec3 scenePos) {
	vec2 cloudShadowPos  = (mat3(shadowModelView) * scenePos).xy + renderDistance * rcp(128.0) * (fract(mat3(shadowModelView) * cameraPosition * rcp(renderDistance) * 128.0).xy - 0.5);

	float cascade = clamp(floor(log2(max(abs(cloudShadowPos.x), abs(cloudShadowPos.y)))) + 1.0, -3.0, 0.0);

	return vec3(cloudShadowPos * exp2(-cascade) * rcp(renderDistance) * 0.5 + 0.5, cascade + 3.0);
}

vec3 unprojectCloudShadowMap (vec2 cloudShadowPos, uint cascade) {
	vec3 shadowViewPos = vec3((cloudShadowPos * 2.0 - 1.0) * exp2(cascade - 3.0) * renderDistance, -1.0);

	shadowViewPos.xy -= renderDistance * rcp(128.0) * (fract(mat3(shadowModelView) * cameraPosition * rcp(renderDistance) * 128.0).xy - 0.5);

	return mat3(shadowModelViewInverse) * shadowViewPos;
}

float getCloudShadows (sampler2D cloudShadowMap, vec3 scenePos) {
#ifndef CLOUD_SHADOWS
	return 1.0;
#else
	vec3 cloudShadowPos     = projectCloudShadowMap(scenePos);
		 cloudShadowPos.xy  = clamp(cloudShadowPos.xy, 1.0 / cloudShadowTileRes, 1.0 - 1.0 / cloudShadowTileRes);
		 cloudShadowPos.xy  = 0.5 * (cloudShadowPos.xy + vec2(uint(cloudShadowPos.z) & 1, uint(cloudShadowPos.z) >> 1));

	if (clamp01(cloudShadowPos.xy) != cloudShadowPos.xy) return 1.0;

		 cloudShadowPos.xy *= vec2(cloudShadowMapRes) / vec2(textureSize(cloudShadowMap, 0));

	// fade out cloud shadows when:
	// - the fragment is above the cloud layer
	// - the sun is near the horizon
	float cloudShadowFade  = 1.0 - smoothstep(CLOUDS_LAYER0_ALTITUDE * CLOUDS_SCALE, (CLOUDS_LAYER0_ALTITUDE + CLOUDS_LAYER0_THICKNESS) * CLOUDS_SCALE, scenePos.y + eyeAltitude - SEA_LEVEL);
	      cloudShadowFade *= smoothstep(0.1, 0.2, shadowDir.y);
		  cloudShadowFade *= cloudShadowIntensity;

	return textureBicubic(cloudShadowMap, cloudShadowPos.xy).x * cloudShadowFade + (1.0 - cloudShadowFade);
#endif
}

#endif // INCLUDE_LIGHTING_CloudShadows
