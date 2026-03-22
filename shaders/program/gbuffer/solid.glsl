#include "/include/main.glsl"

#ifdef fsh

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 1 */
layout (location = 0) out uvec4 encoded;

//--// Inputs //--------------------------------------------------------------//

in vec2 texCoord;
in vec2 lmCoord;
in vec4 tint;

flat in uint blockId;
flat in mat3 tbnMatrix;

//--// Uniforms //------------------------------------------------------------//

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

#ifdef PROGRAM_GBUFFERS_ENTITIES
uniform vec4 entityColor;
uniform int entityId;
#endif

//--// Time uniforms

uniform int frameCounter;

//--// Custom uniforms

uniform vec2 viewTexelSize;

//--// Includes //------------------------------------------------------------//

#include "/block.properties"
#include "/entity.properties"

#include "/include/fragment/textureFormat.glsl"

#include "/include/utility/dithering.glsl"
#include "/include/utility/encoding.glsl"

//--// Functions //-----------------------------------------------------------//

const float lodBias = log2(renderScale);

void main() {
#if TAA_UPSCALING_FACTOR > 1
	vec2 coord = gl_FragCoord.xy * viewTexelSize;
	if (clamp01(coord) != coord) discard;
#endif

	vec4 baseTex = texture(gtexture, texCoord, lodBias);
#ifdef NORMAL_MAP
	vec3 normalTex = texture(normals, texCoord, lodBias).xyz;
#endif
#ifdef SPECULAR_MAP
	vec4 specularTex = textureLod(specular, texCoord, 0);
#endif

	baseTex *= tint;
#ifdef PROGRAM_GBUFFERS_ENTITIES
	if (baseTex.a < 0.1 && entityId != ENTITY_BOAT && entityId != ENTITY_LIGHTNING_BOLT) discard;
#else
	if (baseTex.a < 0.1) discard;
#endif

#if defined PROGRAM_GBUFFERS_ENTITIES
	baseTex.rgb = mix(baseTex.rgb, entityColor.rgb, entityColor.a);
	baseTex.rgb = mix(baseTex.rgb, vec3(1.0), float(entityId == ENTITY_LIGHTNING_BOLT));
#endif

#ifdef NORMAL_MAP
	vec3 normal; float ao;
	decodeNormalTex(normalTex, normal, ao);

	normal = tbnMatrix * normal;
#endif

	float dither = interleavedGradientNoise(gl_FragCoord.xy, frameCounter);

	mat2x4 data;
	data[0].xyz = baseTex.rgb;
#if defined PROGRAM_GBUFFERS_ENTITIES
	data[0].w   = float(entityId) * rcp(255.0);
#else
	data[0].w   = float(blockId) * rcp(255.0);
#endif
	data[1].xy  = encodeUnitVector(tbnMatrix[2]);
	data[1].zw  = dither8Bit(lmCoord, dither);

	encoded.x = packUnorm4x8(data[0]);
	encoded.y = packUnorm4x8(data[1]);

#ifdef NORMAL_MAP
	// Pack encoded normal in first 24 bits, material AO in next 7 and parallax shadow in final bit
	vec4 normalData = vec4(encodeUnitVector(normal), ao, 1.0);
	encoded.z = packUnormArb(normalData, uvec4(12, 12, 7, 1));
#endif

#ifdef SPECULAR_MAP
	encoded.w = packUnorm4x8(specularTex);
#endif

#if defined PROGRAM_GBUFFERS_BEACONBEAM
	// Discard the translucent edge part of the beam
	if (baseTex.a < 0.99) discard;
#endif
}

#endif

#ifdef vsh

//--// Outputs //-------------------------------------------------------------//

out vec2 texCoord;
out vec2 lmCoord;
out vec4 tint;

flat out uint blockId;
flat out mat3 tbnMatrix;

//--// Inputs //--------------------------------------------------------------//

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D noisetex;

//--// Camera uniforms

uniform float near;
uniform float far;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

//--// Time uniforms

uniform float frameTimeCounter;

uniform float rainStrength;

//--// Custom uniforms

uniform vec2 taaOffset;

//--// Includes //------------------------------------------------------------//

#include "/block.properties"

#include "/include/utility/spaceConversion.glsl"

#include "/include/vertex/animation.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	texCoord = gl_MultiTexCoord0.xy;
	lmCoord  = gl_MultiTexCoord1.xy * rcp(240.0);
	tint     = gl_Color;
	blockId  = uint(max0(mc_Entity.x - 10000.0));

	tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
#ifdef NORMAL_MAP
	tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
	tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * sign(at_tangent.w);
#endif

	vec3 viewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

#ifdef PROGRAM_GBUFFERS_TERRAIN
	bool isTopVertex = texCoord.y < mc_midTexCoord.y;

	vec3 scenePos  = viewToSceneSpace(viewPos);
	     scenePos += animateVertex(scenePos + cameraPosition, isTopVertex, lmCoord.y, blockId);

	viewPos = sceneToViewSpace(scenePos);
#endif

	vec4 clipPos = project(gl_ProjectionMatrix, viewPos);

#ifdef TAA
    clipPos.xy += taaOffset * clipPos.w;
	clipPos.xy  = clipPos.xy * renderScale + clipPos.w * (renderScale - 1.0);
#endif

	gl_Position = clipPos;
}


#endif