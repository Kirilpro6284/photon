#version 430 compatibility
#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

out vec2 coord;

flat out vec3 directIrradiance;
flat out vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D skyCapture; // Sky capture, lighting color palette,

//--// Includes //------------------------------------------------------------//

#include "/include/atmospherics/atmosphere.glsl"
#include "/include/utility/encoding.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	coord = gl_MultiTexCoord0.xy;

	skyIrradiance = texelFetch(skyCapture, ivec2(255, 2), 0).rgb;

	vec3 rayOrigin = vec3(0.0, planetRadius + 400.0, 0.0);
	vec3 rayDir = cloudsMoonlit ? moonDir : sunDir;

	directIrradiance  = cloudsMoonlit ? moonIrradiance * moonPhaseBrightness : sunIrradiance;
	directIrradiance *= getAtmosphereTransmittance(rayOrigin, rayDir) * smoothstep(0.0, 0.02, abs(sunDir.y + 0.02));
	directIrradiance *= 1.0 - pulse(float(worldTime), 12850.0, 50.0) - pulse(float(worldTime), 23150.0, 50.0);

	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
