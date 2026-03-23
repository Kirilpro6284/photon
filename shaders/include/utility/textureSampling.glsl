#if !defined INCLUDE_UTILITY_TEXTURE_SAMPLING
#define INCLUDE_UTILITY_TEXTURE_SAMPLING

#include "/include/utility/encoding.glsl"

float linearWeight (float coord, float offset) {
    return 1.0 - abs(coord + offset);
}

float bilinearWeight (vec2 coord, vec2 offset) {
    return linearWeight(coord.x, offset.x) * linearWeight(coord.y, offset.y);
}

float trilinearWeight (vec3 coord, vec3 offset) {
    return bilinearWeight(coord.xy, offset.xy) * linearWeight(coord.z, offset.z);
}

// Source: https://iquilezles.org/www/articles/texture/texture.htm
vec4 textureSmooth (sampler2D tex, vec2 coord, vec2 texSize) {
	coord = coord * texSize + 0.5;

	vec2 i, f = modf(coord, i);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	coord = i + f;

	coord = (coord - 0.5) / texSize;
	return texture(tex, coord);
}

vec4 textureSmooth (sampler2D tex, vec2 coord) {
    return textureSmooth(tex, coord, vec2(textureSize(tex, 0)));
}

vec3 textureRgbe8 (sampler2D rgbeSampler, vec2 coord, vec2 texSize) {
    coord = texSize * coord - 0.5;
    ivec2 texel = ivec2(coord);

    vec3 result = vec3(0.0);

    coord = -fract(coord);

    for (int i = 0; i < 4; i++) {
        ivec2 offset = ivec2(i >> 1, i) & ivec2(1);

        result += bilinearWeight(coord, vec2(offset)) * decodeRgbe8(texelFetch(rgbeSampler, texel + offset, 0));
    }

    return result;
}

vec3 textureRgbe8 (sampler3D rgbeSampler, vec3 coord, vec3 texSize) {
    coord = texSize * coord - 0.5;
    ivec3 texel = ivec3(coord);

    vec3 result = vec3(0.0);

    coord = -fract(coord);

    for (int i = 0; i < 8; i++) {
        ivec3 offset = ivec3(i >> 2, i >> 1, i) & ivec3(1);

        result += trilinearWeight(coord, vec3(offset)) * decodeRgbe8(texelFetch(rgbeSampler, texel + offset, 0));
    }

    return result;
}

#endif // INCLUDE_UTILITY_TEXTURE_SAMPLING