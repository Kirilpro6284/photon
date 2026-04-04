/*
 * Program description:
 * Blend voxy translucents, combine solid and translucent depth
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 0,9,11 */
layout (location = 0) out vec4 translucents;
layout (location = 1) out vec4 waterMask;
layout (location = 2) out float frontDepth;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D colortex0;  // Translucent layer
uniform sampler2D colortex9;  // Water mask
uniform sampler2D colortex16; // Voxy translucents
uniform sampler2D colortex17; // Voxy water mask

uniform sampler2D depthtex0;

uniform sampler2D lodDepthTex0;
uniform sampler2D lodDepthTex1;

//--// Includes //------------------------------------------------------------//

#include "/include/atmospherics/sky.glsl"

#include "/include/fragment/aces/matrices.glsl"
#include "/include/fragment/waterVolume.glsl"

#include "/include/lighting/cloudShadows.glsl"

#include "/include/utility/color.glsl"
#include "/include/utility/fastMath.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/spaceConversion.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);

	translucents = texelFetch(colortex0, texel, 0);
	waterMask    = texelFetch(colortex9, texel, 0);
	frontDepth = max(texelFetch(lodDepthTex1, texel, 0).r, texelFetch(lodDepthTex0, texel, 0).r);

#ifdef VOXY
	translucents = mix(texelFetch(colortex16, texel, 0), translucents, translucents.a);
	waterMask    = mix(texelFetch(colortex17, texel, 0), waterMask, waterMask.a);
#endif
}
