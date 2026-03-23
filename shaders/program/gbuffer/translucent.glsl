#include "/include/main.glsl"

#ifdef fsh

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 0,9,11 */
layout (location = 0) out vec4 fragColor;
layout (location = 1) out vec4 waterMask;
layout (location = 2) out vec4 fragDepth;

//--// Inputs //--------------------------------------------------------------//

noperspective in float reversedDepth;

in vec2 texCoord;
in vec2 lmCoord;
in vec3 viewPos;
in vec3 scenePos;
in vec3 viewerDirTangent;

flat in uint blockId;
flat in vec4 tint;
flat in mat3 tbnMatrix;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D noisetex;

uniform sampler2D lodDepthTex1;

uniform sampler2D skyCapture;  // Sky capture
uniform sampler2D colortex7;  // Clear sky
uniform sampler2D colortex8;  // Scene history
uniform sampler2D colortex15; // Cloud shadow map

#if MC_VERSION < 11700
	#define gtexture gcolor
#endif

uniform sampler2D gtexture;

#ifdef NORMAL_MAP
uniform sampler2D normals;
#endif

#ifdef SPECULAR_MAP
uniform sampler2D specular;
#endif

#ifdef SHADOW
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1HW;
#endif

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

void main() {
	vec2 coord = gl_FragCoord.xy * viewTexelSize;
	if (clamp01(coord) != coord) discard;

	/* -- fetch lighting palette -- */

	vec3 ambientIrradiance = texelFetch(skyCapture, ivec2(255, 0), 0).rgb;
	vec3 directIrradiance  = texelFetch(skyCapture, ivec2(255, 1), 0).rgb;
	vec3 skyIrradiance     = texelFetch(skyCapture, ivec2(255, 2), 0).rgb;

	/* -- get material and normal -- */

	Material material;
	vec3 normalTangent = vec3(0.0, 0.0, 1.0);
	float materialAo   = 1.0;

	vec4 baseTex = texture(gtexture, texCoord, lodBias) * tint;

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

		bool isStill = abs(tbnMatrix[2].y) > 0.99;
		vec2 flowDir = isStill ? vec2(0.0) : normalize(tbnMatrix[2].xz);

#ifdef WATER_PARALLAX
		worldPos.xz = waterParallax(normalize(viewerDirTangent), worldPos.xz, flowDir);
#endif

		normalTangent = getWaterNormal(tbnMatrix[2], worldPos, flowDir);
	} else {
		if (baseTex.a < 0.1) discard;

		vec3 albedo = srgbToLinear(baseTex.rgb) * baseTex.a * r709ToAp1Unlit;
		fragColor.a = baseTex.a;

		material = getMaterial(albedo, blockId);

#ifdef SPECULAR_MAP
		vec4 specularTex = textureLod(specular, texCoord, 0);
		decodeSpecularTex(specularTex, material);
#endif

#ifdef NORMAL_MAP
		vec3 normalTex = texture(normals, texCoord, lodBias).xyz;
		decodeNormalTex(normalTex, normalTangent, materialAo);
#endif

		// Hardcoded reflections and SSS for stained glass
		if (blockId == BLOCK_STAINED_GLASS) {
			material.sssAmount = 0.5;
			material.roughness = 0.002;
			material.f0        = vec3(0.04);
		}

		// Hardcoded SSS for slime
		if (blockId == BLOCK_SLIME) {
			material.sssAmount = 0.5;
		}
	}

	float viewerDistance = length(viewPos);

	vec3 normal = tbnMatrix * normalTangent;
	vec3 flatNormal = tbnMatrix[2];
	vec3 viewerDir = (gbufferModelViewInverse[3].xyz - scenePos) * rcp(viewerDistance);

#if defined PROGRAM_GBUFFERS_TEXTURED || defined PROGRAM_GBUFFERS_TEXTURED_LIT
	// no normal attribute
	normal = vec3(0.0, 1.0, 0.0);
	flatNormal = normal;
#endif

	/* -- lighting -- */

	float sssDepth;
	fragColor.rgb = getSceneLighting(
		material,
		scenePos,
		viewPos,
		normal,
		flatNormal,
		viewerDir,
		directIrradiance,
		ambientIrradiance,
		skyIrradiance,
		lmCoord,
		getInterleavedGradientNoise(gl_FragCoord.xy, frameCounter),
		materialAo,
		blockId,
		sssDepth
	);

	/* -- reflections -- */

#if defined SSR && defined PROGRAM_GBUFFERS_WATER
	fragColor.rgb += getSpecularReflections(
		material,
		tbnMatrix,
		vec3(coord, reversedDepth * -0.5),
		viewPos,
		normal,
		viewerDir,
		viewerDirTangent,
		lmCoord.y
	);
#endif

	/* -- fog -- */

	vec3 clearSky = texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0).rgb;
	fragColor.rgb = applyFog(fragColor.rgb, scenePos, clearSky);

	/* -- set water mask -- */

	if (blockId == BLOCK_WATER) {
		float eta = isEyeInWater == 1 ? airN / waterN : waterN / airN;
		float NoV = dot(normal, viewerDir);

		fragColor.a = max(fresnelDielectric(NoV, eta), eps);

		vec2 lightingInfo;
		lightingInfo.x = clamp01(rcp(32.0) * sssDepth);
		lightingInfo.y = lmCoord.y;

		waterMask.x = packUnorm2x8(normalTangent.xy * 0.5 + 0.5);
		waterMask.y = packUnorm2x8(lightingInfo);
		waterMask.z = clamp01(viewerDistance / renderDistance);
		waterMask.w = float(blockId == BLOCK_WATER);
	} else {
		waterMask = vec4(0.0);
	}

	fragColor.rgb *= rcp(fragColor.a);

	fragDepth = vec4(reversedDepth * -0.5, 0.0, 0.0, 1.0);
}

#endif

#ifdef vsh


//--// Outputs //-------------------------------------------------------------//

noperspective out float reversedDepth;

out vec2 texCoord;
out vec2 lmCoord;
out vec3 viewPos;
out vec3 scenePos;
out vec3 viewerDirTangent;

flat out uint blockId;
flat out vec4 tint;
flat out mat3 tbnMatrix;

//--// Inputs //--------------------------------------------------------------//

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D noisetex;

//--// Includes //------------------------------------------------------------//

#include "/block.properties"

#include "/include/utility/spaceConversion.glsl"

#include "/include/vertex/animation.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	texCoord = gl_MultiTexCoord0.xy;
	lmCoord  = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));
	tint     = gl_Color;
	blockId  = uint(max0(mc_Entity.x - 10000.0));

#ifdef PROGRAM_GBUFFERS_TEXTURED_LIT
#ifdef HIDE_WORLD_BORDER
	if (renderStage == MC_RENDER_STAGE_WORLD_BORDER) { gl_Position = vec4(-1.0); return; }
#endif
#endif

	tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
	tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * sign(at_tangent.w);

	viewPos  = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
	scenePos = transform(gbufferModelViewInverse, viewPos);

	reversedDepth = (lodProjMat_2.z * viewPos.z + lodProjMat_3.z) / (lodProjMat_2.w * viewPos.z + lodProjMat_3.w);

	viewerDirTangent = normalize(gbufferModelViewInverse[3].xyz - scenePos) * tbnMatrix;

	vec4 clipPos  = project(gl_ProjectionMatrix, viewPos);

#ifdef TAA
    clipPos.xy += taa_offset * clipPos.w;
	clipPos.xy  = clipPos.xy * renderScale + clipPos.w * (renderScale - 1.0);
#endif

	gl_Position = clipPos;
}


#endif