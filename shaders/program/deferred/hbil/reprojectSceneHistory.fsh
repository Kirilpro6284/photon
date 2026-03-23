/*
 * Program description:
 * Reproject scene history buffer for HBIL
 */

#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

/* RENDERTARGETS: 15 */
layout (location = 0) out vec3 reprojectedHistory;

//--// Inputs //--------------------------------------------------------------//

in vec2 coord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2D lodDepthTex1;

uniform sampler2D colortex8; // Scene history

//--// Includes //------------------------------------------------------------//

#define TEMPORAL_REPROJECTION

#include "/include/utility/spaceConversion.glsl"

//--// Functions //-----------------------------------------------------------//

/*
const bool colortex8MipmapEnabled = true;
 */

void main() {
	if (coord.y < 0.5) {
		vec2 screenCoord = vec2(1.0, 2.0) * coord;

		float depth = texture(lodDepthTex1, screenCoord).x;

		vec3 screenPos = vec3(screenCoord, depth);
		vec3 previousScreenPos = reproject(screenPos);

		if (clamp01(previousScreenPos.xy) == previousScreenPos.xy) {
			reprojectedHistory = texture(colortex8, previousScreenPos.xy).rgb;
			return;
		}
	}

	reprojectedHistory = vec3(0.0);
}
