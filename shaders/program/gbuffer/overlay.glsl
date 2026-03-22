#include "/include/main.glsl"

#ifdef fsh

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 fragColor;

//--// Inputs //--------------------------------------------------------------//

in vec2 texCoord;

//--// Uniforms //------------------------------------------------------------//

#if MC_VERSION < 11700
	#define gtexture gcolor
#endif

uniform sampler2D gtexture;

//--// Functions //-----------------------------------------------------------//

void main() {
	fragColor = texture(gtexture, texCoord, log2(renderScale));
	if (fragColor.a < 0.1) discard;

#if defined PROGRAM_GBUFFERS_ARMOR_GLINT
	// alpha of 0 <=> enchantment glint
	fragColor.a = 0.0;
#elif defined PROGRAM_GBUFFERS_DAMAGEDBLOCK
	// alpha of 1 <=> damage overlay
	fragColor.a = 1.0;
#endif
}

#endif

#ifdef vsh

//--// Outputs //-------------------------------------------------------------//

out vec2 texCoord;

//--// Uniforms //------------------------------------------------------------//

uniform vec2 taaOffset;

//--// Functions //-----------------------------------------------------------//

void main() {
	texCoord = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;

	vec3 viewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
	vec4 clipPos = project(gl_ProjectionMatrix, viewPos);

#ifdef TAA
    clipPos.xy += taaOffset * clipPos.w;
	clipPos.xy  = clipPos.xy * renderScale + clipPos.w * (renderScale - 1.0);
#endif

	gl_Position = clipPos;
}


#endif