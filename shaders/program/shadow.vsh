#include "/include/main.glsl"

//--// Outputs //-------------------------------------------------------------//

out vec2 texCoord;
out vec3 worldPos;

flat out uint blockId;
flat out vec3 normal;
flat out vec4 tint;
flat out mat3 tbnMatrix;

//--// Inputs //--------------------------------------------------------------//

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

//--// Uniforms //------------------------------------------------------------//

uniform sampler2DShadow shadowtex1HW;
uniform sampler2DShadow shadowtex0HW;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowtex0;

uniform sampler2D noisetex;

//--// Includes //------------------------------------------------------------//

#include "/block.properties"

#include "/include/lighting/shadowDistortion.glsl"

#include "/include/vertex/animation.glsl"

//--// Functions //-----------------------------------------------------------//

void main() {
	texCoord = gl_MultiTexCoord0.xy;
	blockId  = uint(mc_Entity.x - 10000.0);
	normal   = mat3(shadowModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	tint     = gl_Color;

#ifdef WATER_CAUSTICS
	tbnMatrix[0] = mat3(shadowModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
	tbnMatrix[1] = cross(tbnMatrix[0], normal) * sign(at_tangent.w);
	tbnMatrix[2] = normal;
#endif

	vec3 shadowViewPos = transform(gl_ModelViewMatrix, gl_Vertex.xyz), shadowClipPos;

	vec3 scenePos = transform(shadowModelViewInverse, shadowViewPos);

	worldPos  = scenePos + cameraPosition;
	worldPos += animateVertex(worldPos, texCoord.y < mc_midTexCoord.y, rcp(240.0) * gl_MultiTexCoord1.y, blockId);
	scenePos  = worldPos - cameraPosition;

	shadowViewPos = transform(shadowModelView, scenePos);
	shadowClipPos = shadowProjScale * shadowViewPos;

	shadowClipPos.xy = distortShadowPos(shadowClipPos.xy);

	gl_Position = vec4(shadowClipPos, 1.0);
}
