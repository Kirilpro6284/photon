#version 430 compatibility

/*
 * Program description:
 * Calculate lighting color palette and dynamic weather properties
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

flat out vec3 weather;
flat out vec3 cloudsDirectIrradiance;

flat out vec3 ambientIrradiance;
flat out vec3 directIrradiance;
flat out vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler3D colortex9; // Atmosphere scattering LUT

//--// Includes //------------------------------------------------------------//

#define WORLD_OVERWORLD

#define ATMOSPHERE_SCATTERING_LUT colortex9

#include "/include/atmospherics/palette.glsl"
#include "/include/atmospherics/weather.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	weather = getWeather();

	vec3 rayOrigin = vec3(0.0, planetRadius, 0.0);
	vec3 rayDir = cloudsMoonlit ? moonDir : sunDir;

	cloudsDirectIrradiance  = cloudsMoonlit ? moonIrradiance : sunIrradiance;
	cloudsDirectIrradiance *= getAtmosphereTransmittance(rayOrigin, rayDir);
	cloudsDirectIrradiance *= 1.0 - pulse(float(worldTime), 12850.0, 50.0) - pulse(float(worldTime), 23150.0, 50.0);

	paletteSetup();

	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
