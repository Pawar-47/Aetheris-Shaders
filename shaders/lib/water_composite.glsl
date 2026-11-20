#ifndef AETHERIS_WATER_COMPOSITE_GLSL
#define AETHERIS_WATER_COMPOSITE_GLSL

#include "/lib/depth.glsl"
#include "/lib/sky.glsl"

/* The water surface, shaded in composite.
 *
 * This is where the whole water design pays off, and it rests on one decision made
 * in the geometry pass: gbuffers_water writes no colour at all, only the surface
 * normal and a mask, leaving colortex0 holding the opaque scene underneath.
 *
 * That single choice is what makes real refraction possible without a second copy
 * of the frame. The bottom of the lake is still in colortex0, so sampling it at an
 * offset gives an actually refracted view of the bottom, not a screen space blur of
 * something that already had water over it. It costs one buffer the size of the
 * screen and no extra passes.
 *
 * Order of operations, which is the order light actually takes:
 *   1. Refract: read the bottom, distorted by the surface slope.
 *   2. Absorb: per channel exponential extinction over the water thickness. Red
 *      dies first, which is why deep water is blue-green and shallow water is not.
 *   3. In scatter: add the light that bounced around inside the body.
 *   4. Reflect: screen space march, falling back to the sky plus one layer of cloud.
 *   5. Fresnel: blend body to reflection by the viewing angle.
 *   6. Glitter: a tight sun lobe off the wave normals.
 */

uniform sampler2D colortex0;

/* Extinction per block, per channel. Red absorbs about eight times faster than
 * blue, so a metre of water already looks like a metre of water. */
const vec3 WATER_EXTINCTION = vec3(0.420, 0.088, 0.055);

/* One sample of the cloud deck seen in a reflection.
 *
 * A full march per reflected ray would double the cloud cost for something seen
 * only where the water is calm enough to reflect. One noise sample on the projected
 * cloud plane gets the important part, that the reflection is not an empty sky, and
 * it moves correctly with the waves because it is driven by the reflected
 * direction.
 */
vec4 aetherisCheapCloudSample(vec3 dir, AetherisSky sky) {
    if (dir.y < 0.02) return vec4(0.0);

    float planeDistance = (CLOUD_ALTITUDE - cameraPosition.y) / dir.y;
    if (planeDistance < 0.0 || planeDistance > 14000.0) return vec4(0.0);

    vec2 wind = vec2(frameTimeCounter * 0.0200, frameTimeCounter * 0.0081) * CLOUD_SPEED;
    vec2 p = (cameraPosition.xz + dir.xz * planeDistance) * (CLOUD_FIELD_SCALE * CLOUD_SCALE) + wind;

    float mass = valueNoise(vec2(p.x + p.y * 0.22, p.y * 0.82 - p.x * 0.15));
    float threshold = mix(0.80, 0.52, saturate(CLOUD_COVERAGE));
    float density = saturate((mass - threshold) * 2.6);
    if (density <= 0.01) return vec4(0.0);

    vec3 tone = sky.ambientSky * 4.1 + sky.sunRadiance * 0.55;
    tone = mix(tone, vec3(luma(tone)) * vec3(0.82, 0.85, 0.90), sky.rain * 0.7);

    return vec4(tone * density, density * 0.88);
}

/* What a reflection sees when it misses all geometry. */
vec3 aetherisReflectionFallback(vec3 dir, AetherisSky sky) {
    vec3 colour = aetherisSkyGradient(dir, sky);
    colour += aetherisSunDisc(dir, sky);
    colour += aetherisMoonDisc(dir, sky);

    vec4 cloud = aetherisCheapCloudSample(dir, sky);
    colour = mix(colour, cloud.rgb, cloud.a);

    return colour;
}

/* March a reflected ray through the depth buffer.
 *
 * The ray is walked in view space and projected at each step, which keeps the step
 * sizes in blocks rather than in screen proportions and stops the march from
 * collapsing near the horizon.
 *
 * Steps grow geometrically. Uniform steps either miss thin geometry near the
 * surface or waste most of the budget on the first two blocks.
 *
 * Returns the colour found, and sets hit to how much to trust it. A miss fades back
 * to the sky over the length of the march so a reflection that runs off the screen
 * does not leave a hard edge. */
vec3 aetherisScreenReflection(vec2 uv, vec3 viewPos, vec3 viewReflect, out float hit) {
    hit = 0.0;

    vec3 origin = viewPos + viewReflect * 0.09;
    float travel = 0.45;

    for (int i = 0; i < REFLECTION_STEPS; i++) {
        vec3 samplePos = origin + viewReflect * travel;
        if (samplePos.z > -near) break;

        vec3 screenPos = viewToScreen(samplePos);
        if (!screenPositionValid(screenPos)) break;

        float sceneDistance = linearizeDepth(texture(depthtex1, screenPos.xy).r);
        float rayDistance = -samplePos.z;

        // A hit is where the ray has passed behind the stored surface, but not so far
        // behind that it has gone through a wall and out the other side.
        float thickness = rayDistance - sceneDistance;
        if (thickness > 0.02 && thickness < 4.5) {
            hit = saturate(1.0 - thickness * 0.28);
            return texture(colortex0, screenPos.xy).rgb;
        }

        travel *= 1.55;
    }

    return vec3(0.0);
}

/* Shade the water at one screen pixel.
 *
 * uv            pixel being shaded
 * waterData     the packed normal and texture modulation from colortex2
 * sky           frame state
 * sceneColour   colortex0 at this pixel, which is the water body's floor
 */
vec3 aetherisWaterSurface(vec2 uv, vec4 waterData, AetherisSky sky, vec3 sceneColour) {
    vec3 normal = aetherisUnpackWaterNormal(waterData);

    float surfaceDepth = texture(depthtex0, uv).r;
    vec3 viewPos = screenToView(uv, surfaceDepth);
    vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
    float distance = length(viewPos);

    vec3 toEye = normalize(-worldPos);
    float NdotV = saturate(dot(normal, toEye));

    // ---------------------------------------------------------------- thickness
    float surfaceDistance = linearizeDepth(surfaceDepth);
    float bottomDistance = linearizeDepth(texture(depthtex1, uv).r);

    // The difference between the water surface and the opaque floor is the water
    // column depth, read straight out of the two depth buffers.
    float thickness = max(bottomDistance - surfaceDistance, 0.0);

    // Adding a little view distance makes a large lake deepen towards the horizon,
    // which is both physically right at grazing angles and a safety net if a driver
    // ever declines to write depth for the water pass.
    thickness += surfaceDistance * 0.012;

    // --------------------------------------------------------------- refraction
    // The offset shrinks with distance because the same surface slope covers less of
    // the screen far away.
    float distortionScale = (0.048 * WATER_REFRACTION) / (1.0 + surfaceDistance * 0.055);
    vec2 refractedUV = uv + normal.xz * distortionScale;

    vec3 refracted = sceneColour;
    if (refractedUV.x > 0.002 && refractedUV.x < 0.998
        && refractedUV.y > 0.002 && refractedUV.y < 0.998) {
        // Only accept the offset sample if it is still underneath water. Without this
        // check the distortion drags dry land into the water at a shoreline.
        float candidate = linearizeDepth(texture(depthtex1, refractedUV).r);
        if (candidate > surfaceDistance + 0.04) {
            refracted = texture(colortex0, refractedUV).rgb;
        }
    }

    // ------------------------------------------------------------------ absorb
    vec3 extinction = WATER_EXTINCTION / max(WATER_CLARITY, 0.20);
    vec3 transmittance = exp(-extinction * thickness);

    // Light that scattered inside the body rather than passing straight through.
    vec3 incident = sky.ambientSky * 1.9 + sky.sunRadiance * 0.14;
    vec3 scatterColour = vec3(0.075, 0.240, 0.255) * incident;

    vec3 body = refracted * transmittance + scatterColour * (vec3(1.0) - transmittance);

    // The vanilla water texture keeps its faint modulation, so the surface still
    // reads as Minecraft water and not as a generic procedural plane.
    body *= mix(1.0, waterData.b * 1.85, 0.30);

    // --------------------------------------------------------------- reflection
    vec3 worldReflect = reflect(-toEye, normal);

    float hitWeight = 0.0;
    vec3 reflection = vec3(0.0);

#if WATER_REFLECTIONS == 1
    vec3 viewReflect = mat3(gbufferModelView) * worldReflect;
    reflection = aetherisScreenReflection(uv, viewPos, viewReflect, hitWeight);

    // Reflections that ran off screen, or that are too far away for a screen space
    // march to be meaningful, fall back to the sky.
    float trust = hitWeight * (1.0 - smoothstep(28.0, 96.0, distance));
    reflection = mix(aetherisReflectionFallback(worldReflect, sky), reflection, trust);
#else
    reflection = aetherisReflectionFallback(worldReflect, sky);
#endif

    // Underwater the surface is seen from below; Snell's window is far too much
    // machinery for this, so the reflection is simply damped and the body colour
    // dominates, which is what the eye reads anyway.
    if (isEyeInWater == 1) reflection *= 0.35;

    // ------------------------------------------------------------------ fresnel
    // Schlick, with water's real F0 of 0.02. Written out rather than pow(x, 5.0)
    // because five multiplies beat a function call.
    float oneMinusNdotV = 1.0 - NdotV;
    float fresnel = oneMinusNdotV * oneMinusNdotV;
    fresnel *= fresnel;
    fresnel *= oneMinusNdotV;
    fresnel = 0.02 + 0.98 * fresnel;

    // Rain roughens the surface and lifts the reflected share of a grey sky.
    fresnel = mix(fresnel, 0.55, sky.rain * 0.35);

    vec3 colour = mix(body, reflection, saturate(fresnel));

    // ------------------------------------------------------------------ glitter
    // Two lobes: a tight one for the glints that ride individual wave crests, and a
    // broad one that gives the whole surface a sheen towards a low sun.
    vec3 halfDir = normalize(toEye + sky.lightDir);
    float NdotH = saturate(dot(normal, halfDir));
    float tight = NdotH * NdotH;
    tight *= tight;
    tight *= tight;
    tight *= tight;
    tight *= tight;          // NdotH to the 256th

    float broad = NdotH * NdotH;
    broad *= broad;
    broad *= broad;
    broad *= broad;          // NdotH to the 64th

    float sunAbove = saturate(dot(normal, sky.lightDir));
    vec3 glitter = (sky.sunRadiance + sky.moonRadiance * 6.0)
                 * (tight * 5.4 + broad * 0.30) * (sunAbove * (1.0 - sky.rain * 0.85));

    colour += glitter;

    // A touch of the sun's own colour across the body, so a sunset tints the water
    // it shines on rather than leaving a grey slab in an orange scene.
    colour += body * sky.sunRadiance * (0.05 * sky.golden);

    return colour;
}

#endif
