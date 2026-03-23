#version 430 compatibility
#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

out vec2 coord;

flat out vec3 weather;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D skyCapture; // Sky capture, color palette and weather properties

//--// Includes //------------------------------------------------------------//

#include "/include/atmospherics/weather.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	coord = gl_MultiTexCoord0.xy;

	weather = getWeather();

	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
