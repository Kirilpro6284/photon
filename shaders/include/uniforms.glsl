#if !defined INCLUDE_UNIFORMS
#define INCLUDE_UNIFORMS

//--// Camera uniforms

uniform int isEyeInWater;
uniform int vxRenderDistance;

uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

uniform float eyeAltitude;
uniform float blindness;
uniform float near;
uniform float far;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;

//--// Shadow uniforms

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

//--// Time uniforms

uniform int worldDay;
uniform int worldTime;
uniform int moonPhase;
uniform int frameCounter;

uniform float frameTime;
uniform float frameTimeCounter;

uniform float rainStrength;
uniform float shadowAngle;
uniform float sunAngle;
uniform float wetness;

//--// Custom uniforms

uniform bool advanceTime;
uniform bool cloudsMoonlit;
uniform bool worldAgeChanged;

uniform float worldAge;

uniform float desertSandstorm;
uniform float lightningFlash;

uniform float biomeCave;
uniform float biomeTemperature;
uniform float biomeHumidity;
uniform float biomeMayRain;

uniform float timeSunset;
uniform float timeNoon;
uniform float timeSunrise;
uniform float timeMidnight;

uniform float eyeSkylight;
uniform float moonPhaseBrightness;

uniform vec3 cameraVelocity;

uniform vec3 sunDir;
uniform vec3 moonDir;
uniform vec3 shadowDir;

uniform vec3 viewSunDir;
uniform vec3 viewMoonDir;
uniform vec3 viewShadowDir;

uniform vec2 taa_offset;
uniform vec2 taa_offset_prev;

uniform vec2 internalScreenSize;
uniform vec2 screenSize;
uniform vec2 internalTexelSize;
uniform vec2 texelSize;

uniform vec4 lodProjMat_0;
uniform vec4 lodProjMat_1;
uniform vec4 lodProjMat_2;
uniform vec4 lodProjMat_3;

uniform vec4 lodProjMatPrev_0;
uniform vec4 lodProjMatPrev_1;
uniform vec4 lodProjMatPrev_2;
uniform vec4 lodProjMatPrev_3;

uniform vec4 lodProjMatInv_0;
uniform vec4 lodProjMatInv_1;
uniform vec4 lodProjMatInv_2;
uniform vec4 lodProjMatInv_3;

#endif // INCLUDE_UNIFORMS