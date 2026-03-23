#include "/include/main.glsl"
#include "/include/utility/encoding.glsl"

//--// Outputs //-------------------------------------------------------------//

out vec2 coord;

flat out vec3 ambientIrradiance;
flat out vec3 directIrradiance;
flat out vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D skyCapture; // Sky capture, lighting color palette, dynamic weather properties

//--// Functions //-----------------------------------------------------------//

void main() {
	coord = gl_MultiTexCoord0.xy;

	ambientIrradiance = texelFetch(skyCapture, ivec2(255, 0), 0).rgb;
	directIrradiance  = texelFetch(skyCapture, ivec2(255, 1), 0).rgb;
	skyIrradiance     = texelFetch(skyCapture, ivec2(255, 2), 0).rgb;

	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
