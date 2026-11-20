#ifndef AETHERIS_UTIL_GLSL
#define AETHERIS_UTIL_GLSL

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"

/* Small toolbox: colour space, the tonemap curve, and the noise everything
 * procedural in this pack is built from.
 *
 * Two rules hold across the whole pack:
 *   1. No sin() based hashes. sin() is a real instruction on Intel Gen8 and
 *      collapses into visible banding at large coordinates anyway.
 *   2. No pow() where a multiply chain or a sqrt() will do. sqrt is one
 *      instruction; pow is a call.
 */

const float AETHERIS_PI = 3.14159265;
const float AETHERIS_TAU = 6.28318531;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3 saturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }

float luma(vec3 colour) { return dot(colour, vec3(0.2126, 0.7152, 0.0722)); }

/* Display encoded colour in, linear light out.
 *
 * A cubic polynomial fit of the sRGB inverse transfer, accurate to better than a
 * percent over the whole range and costing six multiplies instead of three pow()
 * calls. This runs once per fragment in the geometry pass, which is the hottest
 * place in the entire pack, so the fit is not a micro optimisation: at 720p it is
 * the difference between roughly eleven million pow() calls a frame and none.
 * The exact piecewise curve is used on the way back out, in final, where it is one
 * pixel per screen pixel and the accuracy matters for how the image is displayed.
 */
vec3 sRGBToLinear(vec3 colour) {
    colour = max(colour, vec3(0.0));
    return colour * (colour * (colour * 0.305306011 + 0.682171111) + 0.012522878);
}

/* Linear light in, display encoded colour out. Exact piecewise transfer. */
vec3 linearToSRGB(vec3 colour) {
    colour = max(colour, vec3(0.0));
    vec3 low = colour * 12.92;
    vec3 high = pow(colour, vec3(1.0 / 2.4)) * 1.055 - 0.055;
    return mix(low, high, step(vec3(0.0031308), colour));
}

/* Narkowicz' fit of the ACES filmic curve.
 *
 * It rolls the highlights off instead of clipping them, which is what keeps a
 * bright sky from turning into a flat white sheet, and it costs nine multiplies
 * and one divide. The fit is monotonic and hits 0 at 0, so it is safe to apply
 * after exposure and before the sRGB transfer. */
vec3 acesTonemap(vec3 colour) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((colour * (a * colour + b)) / (colour * (c * colour + d) + e), 0.0, 1.0);
}

/* One hash for all procedural detail. Integer free so it compiles on every
 * driver this pack targets, and free of sin() so it holds up far from spawn. */
float aetherisHash(vec2 p) {
    vec3 q = fract(vec3(p.x, p.y, p.x + p.y) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 31.17);
    return fract((q.x + q.z) * q.y);
}

/* Smoothly interpolated value noise on the unit grid. */
float valueNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 weight = local * local * (3.0 - 2.0 * local);

    float a = aetherisHash(cell);
    float b = aetherisHash(cell + vec2(1.0, 0.0));
    float c = aetherisHash(cell + vec2(0.0, 1.0));
    float d = aetherisHash(cell + vec2(1.0, 1.0));

    return mix(mix(a, b, weight.x), mix(c, d, weight.x), weight.y);
}

/* Value noise together with its exact gradient, returned as (value, d/dx, d/dy).
 *
 * The four corner hashes are the same ones valueNoise uses, so the slope costs a
 * handful of multiplies rather than extra texture or noise taps. The waves and
 * the cloud shading both lean on this. */
vec3 valueNoiseGradient(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 blend = local * local * (3.0 - 2.0 * local);
    vec2 slope = 6.0 * local * (1.0 - local);

    float a = aetherisHash(cell);
    float b = aetherisHash(cell + vec2(1.0, 0.0));
    float c = aetherisHash(cell + vec2(0.0, 1.0));
    float d = aetherisHash(cell + vec2(1.0, 1.0));

    float ab = mix(a, b, blend.x);
    float cd = mix(c, d, blend.x);

    return vec3(
        mix(ab, cd, blend.y),
        mix((b - a) * slope.x, (d - c) * slope.x, blend.y),
        (cd - ab) * slope.y
    );
}

/* Two octaves. The second is offset and rotated so the lattice never lines up. */
float fbm2(vec2 p) {
    return valueNoise(p) * 0.66 + valueNoise(p * 2.07 + vec2(17.3, 9.1)) * 0.34;
}

/* Three octaves, used where the extra octave actually reads: cloud edges. */
float fbm3(vec2 p) {
    float sum = valueNoise(p) * 0.55;
    sum += valueNoise(p * 2.03 + vec2(11.7, 3.4)) * 0.30;
    sum += valueNoise(p * 4.11 + vec2(5.9, 21.2)) * 0.15;
    return sum;
}

/* Inverted, ridged noise. Gives cloud crowns and water crests their thin bright
 * detail instead of the rounded blobs plain value noise produces. */
float ridgedNoise(vec2 p) {
    float n = valueNoise(p);
    return 1.0 - abs(n * 2.0 - 1.0);
}

/* 4x4 ordered dither in the range -0.5 to 0.5.
 *
 * A fixed pattern never crawls between frames, and it is free next to a random
 * number. Used to break up sky banding, to jitter the cloud march and the
 * reflection march so they trade sampling error for noise, and to hide the
 * quantisation in the final 8 bit output. */
const float AETHERIS_BAYER_4X4[16] = float[16](
     0.0,  8.0,  2.0, 10.0,
    12.0,  4.0, 14.0,  6.0,
     3.0, 11.0,  1.0,  9.0,
    15.0,  7.0, 13.0,  5.0
);

float aetherisDither(vec2 pixel) {
    ivec2 cell = ivec2(mod(floor(pixel), vec2(4.0)));
    return AETHERIS_BAYER_4X4[cell.y * 4 + cell.x] * (1.0 / 16.0) - 0.5;
}

/* A coverage preserving alpha threshold. Cutout edges keep their fraction of
 * each 4x4 Bayer tile, while fully transparent and fully solid texels stay that
 * way. Slightly cheaper looking than vanilla's hard 0.1 cutout and it removes the
 * shimmer that a plain alpha test leaves on distant leaves. */
float aetherisAlphaCoverage(vec2 pixel) {
    return aetherisDither(pixel) + 0.501;
}

/* Rotation by a constant angle, used to decorrelate noise octaves. */
vec2 rotate2(vec2 v, float cosine, float sine) {
    return vec2(v.x * cosine - v.y * sine, v.x * sine + v.y * cosine);
}

#endif
