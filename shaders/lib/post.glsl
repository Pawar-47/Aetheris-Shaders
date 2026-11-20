#ifndef AETHERIS_POST_GLSL
#define AETHERIS_POST_GLSL

#include "/lib/util.glsl"

/* Final-resolution post processing: FXAA, tone mapping, grading and quantisation.
 *
 * The final pass stays deliberately small. Bloom and screen-space light shafts are
 * generated earlier in the two quarter-resolution composite stages and arrive here
 * in one compact HDR buffer. This avoids a full-resolution blur chain.
 *
 * Depth of field and motion blur are not currently implemented in Aetheris; do not
 * describe them as active features. There is no temporal history buffer in this pass.
 *
 *   - FXAA, because the target is 720p and below where MSAA is unaffordable.
 *   - ACES filmic, so bright sky and sun roll off instead of clipping to paper.
 *   - A restrained grade: exposure, temperature, saturation, contrast, vignette.
 */

/* Compact FXAA.
 *
 * Five taps to decide the edge direction, then up to four more to blend along it.
 * The early out on flat regions is the important part: most of a rendered frame is
 * not near an edge, and those pixels cost five taps and a compare.
 *
 * Operates on the HDR image rather than the display encoded one. That means tone
 * mapping happens once, after the blend, instead of once per tap. The luma
 * thresholds below are scaled up for HDR values to compensate; a threshold tuned
 * for 0 to 1 would never trigger here and the pass would do nothing. */
vec3 aetherisFXAA(sampler2D image, vec2 uv) {
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);

    vec3 centre = texture(image, uv).rgb;
    vec3 northWest = texture(image, uv + vec2(-1.0, -1.0) * texel).rgb;
    vec3 northEast = texture(image, uv + vec2( 1.0, -1.0) * texel).rgb;
    vec3 southWest = texture(image, uv + vec2(-1.0,  1.0) * texel).rgb;
    vec3 southEast = texture(image, uv + vec2( 1.0,  1.0) * texel).rgb;

    const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

    float lumaCentre = dot(centre, LUMA_WEIGHTS);
    float lumaNorthWest = dot(northWest, LUMA_WEIGHTS);
    float lumaNorthEast = dot(northEast, LUMA_WEIGHTS);
    float lumaSouthWest = dot(southWest, LUMA_WEIGHTS);
    float lumaSouthEast = dot(southEast, LUMA_WEIGHTS);

    float lumaMin = min(lumaCentre, min(min(lumaNorthWest, lumaNorthEast), min(lumaSouthWest, lumaSouthEast)));
    float lumaMax = max(lumaCentre, max(max(lumaNorthWest, lumaNorthEast), max(lumaSouthWest, lumaSouthEast)));

    // Flat region: nothing to antialias. This is the branch that keeps FXAA nearly
    // free on this hardware.
    if ((lumaMax - lumaMin) < max(0.22, lumaMax * 0.16)) return centre;

    vec2 direction;
    direction.x = -((lumaNorthWest + lumaNorthEast) - (lumaSouthWest + lumaSouthEast));
    direction.y =  ((lumaNorthWest + lumaSouthWest) - (lumaNorthEast + lumaSouthEast));

    float reduce = max((lumaNorthWest + lumaNorthEast + lumaSouthWest + lumaSouthEast) * 0.03125, 0.0078125);
    float rcpMin = 1.0 / (min(abs(direction.x), abs(direction.y)) + reduce);
    direction = clamp(direction * rcpMin, vec2(-8.0), vec2(8.0)) * texel;

    vec3 blendA = 0.5 * (texture(image, uv + direction * (1.0 / 3.0 - 0.5)).rgb
                       + texture(image, uv + direction * (2.0 / 3.0 - 0.5)).rgb);
    vec3 blendB = blendA * 0.5 + 0.25 * (texture(image, uv + direction * -0.5).rgb
                                       + texture(image, uv + direction *  0.5).rgb);

    float lumaBlend = dot(blendB, LUMA_WEIGHTS);
    if (lumaBlend < lumaMin || lumaBlend > lumaMax) return blendA;
    return blendB;
}

/* White balance. Positive warms, negative cools. */
vec3 aetherisWhiteBalance(vec3 colour) {
    vec3 warm = vec3(1.065, 1.000, 0.900);
    vec3 cool = vec3(0.930, 1.000, 1.075);
    if (COLOR_TEMPERATURE > 0.0) return colour * mix(vec3(1.0), warm, COLOR_TEMPERATURE);
    return colour * mix(vec3(1.0), cool, -COLOR_TEMPERATURE);
}

/* Saturation, applied around the pixel's own luma so it does not shift brightness. */
vec3 aetherisSaturate(vec3 colour) {
    return mix(vec3(luma(colour)), colour, COLOR_SATURATION);
}

/* Contrast around middle grey, in display space where it behaves predictably. */
vec3 aetherisContrast(vec3 colour) {
    return clamp((colour - 0.5) * COLOR_CONTRAST + 0.5, 0.0, 1.0);
}

/* Vignette.
 *
 * Gentle and slightly oval. A strong vignette is the cheapest way to make an image
 * look processed; a gentle one just gathers the eye towards the centre of the
 * frame. */
float aetherisVignette(vec2 uv) {
    vec2 centred = (uv - 0.5) * vec2(1.05, 1.00);
    float radius = dot(centred, centred);
    return 1.0 - COLOR_VIGNETTE * radius * 1.35;
}

/* The whole final chain, in the order a film recorder would do it. */
vec3 aetherisFinish(vec3 hdr, vec2 uv, vec2 pixel) {
    vec3 colour = hdr * COLOR_EXPOSURE;

    colour = aetherisWhiteBalance(colour);

    // ACES in linear light. Everything above this line is physical, everything below
    // it is display referred.
    colour = acesTonemap(colour);

    colour = linearToSRGB(colour);

    colour = aetherisSaturate(colour);
    colour = aetherisContrast(colour);

    colour *= aetherisVignette(uv);

    // Ordered dither at one quantisation step. The sky is a slow gradient across
    // hundreds of pixels and an 8 bit buffer bands it visibly; this is the whole fix
    // and it costs a table lookup.
    colour += aetherisDither(pixel) * (1.0 / 255.0);

    return clamp(colour, 0.0, 1.0);
}

#endif
