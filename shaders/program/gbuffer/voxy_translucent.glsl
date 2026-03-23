#define PROGRAM_VOXY

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

layout (location = 0) out vec4 fragColor;
layout (location = 1) out vec4 waterMask;
layout (location = 2) out vec4 fragDepth;

//--// Inputs //--------------------------------------------------------------//

/*
    struct VoxyFragmentParameters {
        vec4 sampledColour;
        vec2 tile;
        vec2 uv;
        uint face;
        uint modelId;
        vec2 lightMap;
        vec4 tinting;
        uint customId;//Same as iris's modelId
    };
*/

//--// Includes //------------------------------------------------------------//

#ifdef SHADOW_COLOR
	#undef SHADOW_COLOR
#endif

#define TEMPORAL_REPROJECTION

#include "/block.properties"
#include "/entity.properties"

#include "/include/fragment/aces/matrices.glsl"
#include "/include/fragment/fog.glsl"
#include "/include/fragment/material.glsl"
#include "/include/fragment/textureFormat.glsl"
#include "/include/fragment/waterNormal.glsl"
#include "/include/fragment/waterVolume.glsl"

#include "/include/lighting/lighting.glsl"
#include "/include/lighting/reflections.glsl"

#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/spaceConversion.glsl"

//--// Functions //-----------------------------------------------------------//

const float lodBias = log2(renderScale);
const float waterOpacity = 0.02;

void voxy_emitFragment (VoxyFragmentParameters parameters) {
	vec2 coord = gl_FragCoord.xy * viewTexelSize;
	if (clamp01(coord) != coord) discard;

	uint blockId = parameters.customId - 10000u;

	vec4 viewPos = vxProjInv * vec4(coord * 2.0 - 1.0 - taa_offset, gl_FragCoord.z * 2.0 - 1.0, 1.0);

    viewPos.xyz /= viewPos.w;

    fragDepth = vec4((lodProjMat_2.z * viewPos.z + lodProjMat_3.z) / (lodProjMat_2.w * viewPos.z) * -0.5, 0.0, 0.0, 1.0);

	vec3 scenePos = transform(gbufferModelViewInverse, viewPos.xyz);

    /* -- fetch lighting palette -- */

	vec3 ambientIrradiance = texelFetch(skyCapture, ivec2(255, 0), 0).rgb;
	vec3 directIrradiance  = texelFetch(skyCapture, ivec2(255, 1), 0).rgb;
	vec3 skyIrradiance     = texelFetch(skyCapture, ivec2(255, 2), 0).rgb;

	/* -- get material and normal -- */

	Material material;
	vec3 normalTangent = vec3(0.0, 0.0, 1.0);
	float materialAo   = 1.0;

    vec4 baseTex = parameters.sampledColour * parameters.tinting;

    vec3 flatNormal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);

    mat3 tbnMatrix = tbnNormal(flatNormal);
	
	float viewerDistance = length(viewPos.xyz);

	vec3 viewerDir = (gbufferModelViewInverse[3].xyz - scenePos) * rcp(viewerDistance);
	vec3 viewerDirTangent = normalize(viewerDir) * tbnMatrix;

	if (blockId == BLOCK_WATER) {
		material.albedo           = vec3(0.0);
		material.f0               = vec3(0.02);
		material.emission         = vec3(0.0);
		material.roughness        = 0.002;
		material.n                = isEyeInWater == 1 ? airN / waterN : waterN / airN;
		material.sssAmount        = 1.0;
		material.porosity         = 0.0;
		material.isMetal          = false;
		material.isHardcodedMetal = false;

#ifdef WATER_TEXTURE
		float textureValue     = getLuminance(srgbToLinear(baseTex.rgb), luminanceWeightsR709);
		float textureHighlight = linearStep(0.08, 0.3, textureValue);

		material.albedo     = clamp01(0.5 * exp(-2.0 * waterExtinctionCoeff) * (textureValue + 0.6 * textureHighlight));
		material.roughness += 0.3 * textureHighlight;
#endif

		vec3 worldPos = scenePos + cameraPosition;

		bool isStill = abs(flatNormal.y) > 0.99;
		vec2 flowDir = isStill ? vec2(0.0) : normalize(flatNormal.xz);
		
		normalTangent = getWaterNormal(flatNormal, worldPos, flowDir);
	} else {
		if (baseTex.a < 0.1) discard;

		vec3 albedo = srgbToLinear(baseTex.rgb) * baseTex.a * r709ToAp1Unlit;
		fragColor.a = baseTex.a;

		material = getMaterial(albedo, blockId);

		// Hardcoded reflections and SSS for stained glass
		if (blockId == BLOCK_STAINED_GLASS) {
			material.sssAmount = 0.5;
			material.roughness = 0.002;
			material.f0        = vec3(0.04);
		}

		// Hardcoded SSS for slime
		if (parameters.customId == BLOCK_SLIME) {
			material.sssAmount = 0.5;
		}
	}

	vec3 normal = tbnMatrix * normalTangent;

	/* -- lighting -- */

	fragColor.rgb = getSceneLighting(
		material,
		scenePos,
		viewPos.xyz,
		normal,
		flatNormal,
		viewerDir,
		directIrradiance,
		ambientIrradiance,
		skyIrradiance,
		parameters.lightMap * 32.0 / 31.0,
		materialAo,
		getInterleavedGradientNoise(gl_FragCoord.xy, frameCounter),
		blockId
	);

	/* -- reflections -- */

#if defined SSR
	fragColor.rgb = getSpecularReflections(
		material,
		tbnMatrix,
		vec3(coord, fragDepth.r),
		viewPos.xyz,
		normal,
		viewerDir,
		viewerDirTangent,
		parameters.lightMap.y * 32.0 / 31.0
	);
#endif

    /* -- fog -- */

	vec3 clearSky = vec3(1.0);
	fragColor.rgb = applyFog(fragColor.rgb, scenePos, clearSky);

	/* -- set water mask -- */

	if (blockId == BLOCK_WATER) {
		float eta = isEyeInWater == 1 ? airN / waterN : waterN / airN;
		float NoV = dot(normal, viewerDir);

		fragColor.a = max(fresnelDielectric(NoV, eta), eps);

		vec2 lightingInfo;
		lightingInfo.x = clamp01(rcp(32.0) * 1.0);
		lightingInfo.y = parameters.lightMap.y;

		waterMask.x = packUnorm2x8(normalTangent.xy * 0.5 + 0.5);
		waterMask.y = packUnorm2x8(lightingInfo);
		waterMask.z = clamp01(viewerDistance / renderDistance);
		waterMask.w = float(blockId == BLOCK_WATER);
	} else {
		waterMask = vec4(0.0);
	}

	fragColor.rgb *= rcp(fragColor.a);
}