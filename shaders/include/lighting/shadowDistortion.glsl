#if !defined INCLUDE_LIGHTING_SHADOWDISTORTION
#define INCLUDE_LIGHTING_SHADOWDISTORTION

#include "/include/utility/fastMath.glsl"

// https://discord.com/channels/237199950235041794/525510804494221312/1379718853872848896

#define SHADOW_MAP_BIAS 3.6
const float c = exp(SHADOW_MAP_BIAS) - 1.0;

vec2 distortShadowPos (vec2 pos) 
{
	return sign(pos) * log2(c * abs(pos) + 1.0) / log2(c + 1.0);
}

vec2 distortShadowPosDiff (vec2 pos) 
{
	return c / ((c * abs(pos) + 1.0) * log(c + 1.0));
}

#endif // INCLUDE_LIGHTING_SHADOWDISTORTION
