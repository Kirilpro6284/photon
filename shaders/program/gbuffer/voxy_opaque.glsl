#define PROGRAM_VOXY

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

layout (location = 0) out uvec4 encoded;
layout (location = 1) out vec4 fragDepth;

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

#include "/block.properties"
#include "/entity.properties"

#include "/include/fragment/textureFormat.glsl"

#include "/include/utility/dithering.glsl"
#include "/include/utility/encoding.glsl"

//--// Functions //-----------------------------------------------------------//

void voxy_emitFragment (VoxyFragmentParameters parameters) {
#if TAA_UPSCALING_FACTOR > 1
	vec2 coord = gl_FragCoord.xy * internalTexelSize;
	if (clamp01(coord) != coord) discard;
#endif

    vec4 baseTex = parameters.sampledColour * parameters.tinting;
    vec3 normal = vec3(uint((parameters.face>>1)==2), uint((parameters.face>>1)==0), uint((parameters.face>>1)==1)) * (float(int(parameters.face)&1)*2-1);

	float dither = getInterleavedGradientNoise(gl_FragCoord.xy, frameCounter);

    mat2x4 data;

    data[0].xyz = baseTex.rgb;
    data[0].w   = max0(float(parameters.customId) - 10000.0) * rcp(255.0);
    data[1].xy  = octEncode(normal);
    data[1].zw  = dither8Bit(parameters.lightMap * 32.0 / 31.0, dither);

    encoded.x = packUnorm4x8(data[0]);
	encoded.y = packUnorm4x8(data[1]);

#ifdef NORMAL_MAP
	// Pack encoded normal in first 24 bits, material AO in next 7 and parallax shadow in final bit
	vec4 normalData = vec4(octEncode(normal), 0.0, 1.0);
	encoded.z = packUnormArb(normalData, uvec4(12, 12, 7, 1));
#endif

#ifdef SPECULAR_MAP
	encoded.w = packUnorm4x8(vec4(0.0, 0.0, 0.0, 0.0));
#endif

    vec4 viewPos = vxProjInv * vec4(0.0, 0.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);

    viewPos.z /= viewPos.w;

    fragDepth = vec4((lodProjMat_2.z * viewPos.z + lodProjMat_3.z) / (lodProjMat_2.w * viewPos.z) * -0.5, 0.0, 0.0, 1.0);
}