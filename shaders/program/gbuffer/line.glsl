#include "/include/main.glsl"

#ifdef fsh

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 1 */
layout (location = 0) out uvec4 encoded;

//--// Inputs //--------------------------------------------------------------//

in vec2 lmCoord;

flat in vec3 tint;

//--// Includes //------------------------------------------------------------//

#include "/include/utility/encoding.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
#if TAA_UPSCALING_FACTOR > 1
	vec2 coord = gl_FragCoord.xy * viewTexelSize;
	if (clamp01(coord) != coord) discard;
#endif

	const vec3 normal = vec3(0.0, 1.0, 0.0);

	mat2x4 data;
	data[0].xyz = tint;
	data[0].w   = 0.0;
	data[1].xy  = octEncode(normal);
	data[1].zw  = vec2(0.0);

	encoded.x = packUnorm4x8(data[0]);
	encoded.y = packUnorm4x8(data[1]);

#ifdef NORMAL_MAP
	// Pack encoded normal in first 24 bits, material AO in next 7 and parallax shadow in final bit
	vec4 normalData = vec4(octEncode(normal), 1.0, 1.0);
	encoded.z = packUnormArb(normalData, uvec4(12, 12, 7, 1));
#endif

#ifdef SPECULAR_MAP
	encoded.w = packUnorm4x8(vec4(0.0, 0.0, 0.0, 1.0));
#endif

}

#endif

#ifdef vsh

//--// Outputs //-------------------------------------------------------------//

out vec2 lmCoord;

flat out vec3 tint;

//--// Functions //-----------------------------------------------------------//

void main() {
	lmCoord = gl_MultiTexCoord1.xy * rcp(240.0);
	tint    = gl_Color.rgb;

#if defined PROGRAM_GBUFFERS_LINE
	// Ripped from vanilla 1.17's rendertype_lines.vsh

	const float viewShrink = 1.0 - (1.0 / 256.0);
	const mat4 viewScale = mat4(
		viewShrink, 0.0, 0.0, 0.0,
		0.0, viewShrink, 0.0, 0.0,
		0.0, 0.0, viewShrink, 0.0,
		0.0, 0.0, 0.0, 1.0
	);

	const float lineWidth = 2.0;

	vec4 linePosStart = vec4(gl_Vertex.xyz, 1.0);
	     linePosStart = gl_ProjectionMatrix * viewScale * gl_ModelViewMatrix * linePosStart;
	vec4 linePosEnd = vec4(gl_Vertex.xyz + gl_Normal, 1.0);
	     linePosEnd = gl_ProjectionMatrix * viewScale * gl_ModelViewMatrix * linePosStart;

	vec3 ndc1 = linePosStart.xyz / linePosStart.w;
	vec3 ndc2 = linePosEnd.xyz / linePosEnd.w;

	vec2 lineScreenDir = normalize((ndc2.xy - ndc1.xy) * viewSize);
	vec2 lineOffset = vec2(-lineScreenDir.y, lineScreenDir.x) * lineWidth * viewTexelSize;

	if (lineOffset.x < 0.0) lineOffset *= -1.0;

	vec4 clipPos = (gl_VertexID & 1) == 0
		? vec4((ndc1 + vec3(lineOffset, 0.0)) * linePosStart.w, linePosStart.w)
		: vec4((ndc1 - vec3(lineOffset, 0.0)) * linePosStart.w, linePosStart.w);
#else
	vec3 viewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);
	vec4 clipPos = project(gl_ProjectionMatrix, viewPos);
#endif

#ifdef TAA
    clipPos.xy += taa_offset * clipPos.w;
	clipPos.xy  = clipPos.xy * renderScale + clipPos.w * (renderScale - 1.0);
#endif

	gl_Position = clipPos;
}


#endif