#version 430 compatibility
#include "/include/main.glsl"
#include "/include/utility/encoding.glsl"

#include "/include/atmospherics/skyProjection.glsl"

#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"
#include "/include/utility/sphericalHarmonics.glsl"

//--// Outputs //-------------------------------------------------------------//

out vec2 coord;

flat out vec3 directIrradiance;
flat out vec3 skyIrradiance;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D skyCapture; // Sky capture, lighting color palette,

//--// Functions //-----------------------------------------------------------//

void main() {
	coord = gl_MultiTexCoord0.xy;

	#ifdef SH_SKYLIGHT
		vec3 skySh[9];

		// Initialize SH to 0
		for (uint band = 0; band < 9; ++band) skySh[band] = vec3(0.0);

		// Sample into SH
		const uint sampleCount = 64;
		for (uint i = 0; i < sampleCount; ++i) {
			vec3 direction = uniformHemisphereSample(vec3(0.0, 1.0, 0.0), R2(int(i)));
			vec3 radiance  = texture(skyCapture, projectSky(direction)).rgb;
			float[9] coeff = getSphericalHarmonicsCoefficientsOrder2(direction);

			for (uint band = 0; band < 9; ++band) skySh[band] += radiance * coeff[band];
		}

		// Normalize SH
		const float sampleSolidAngle = tau / float(sampleCount);
		for (uint band = 0; band < 9; ++band) skySh[band] *= sampleSolidAngle;

		skyIrradiance = evaluateSphericalHarmonicsIrradiance(skySh, vec3(0.0, 1.0, 0.0), 1.0);
	#else
		skyIrradiance = texelFetch(skyCapture, ivec2(255, 2), 0).rgb;
	#endif

	directIrradiance = texelFetch(skyCapture, ivec2(255, 1), 0).rgb;

	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
