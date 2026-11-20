#ifndef AETHERIS_LIGHTING_GLSL
#define AETHERIS_LIGHTING_GLSL

#include "/lib/atmosphere.glsl"
#include "/lib/shadow.glsl"
#include "/lib/vegetation.glsl"

/* The forward lighting model.
 *
 * This pack lights geometry where the albedo is, in the geometry pass, instead of
 * writing a G buffer and lighting it later. That is a deliberate choice for a 24 EU
 * part and it is the single biggest structural decision in the pack:
 *
 *   - No G buffer means no full resolution RGBA16F albedo/normal write and read on a
 *     25 GB/s shared bus. At 1280x720 that is roughly 3.7 MB written and 3.7 MB read
 *     per frame that simply does not happen.
 *   - No deferred reconstruction means no view position rebuild per pixel and no
 *     second round of shadow lookups for the same fragment.
 *   - Overdraw is the cost, and on Minecraft terrain it is small: mostly solid,
 *     mostly front to back within a chunk.
 *
 * What it gives up is screen space ambient occlusion applied before lighting. AO is
 * applied afterwards in composite as a multiplier over the lit result, faded out by
 * distance so it only ever touches the near field where it is visible.
 */

/* Material tags. Passed as a plain int so the branch is a compile time switch at
 * each call site rather than a runtime one. */
const int AETHERIS_MAT_DEFAULT  = 0;
const int AETHERIS_MAT_FOLIAGE  = 1;
const int AETHERIS_MAT_EMISSIVE = 2;

/* Map a block ID from block.properties onto a shading path. Unlisted blocks, and
 * every block if block.properties is ever missing, fall through to default shading.
 * That is a graceful failure: the pack keeps working, the foliage just goes back to
 * plain terrain lighting. */
int aetherisMaterialFromId(float id) {
    if (aetherisIsId(id, AETHERIS_ID_LEAVES) || aetherisIsId(id, AETHERIS_ID_PLANT)) {
        return AETHERIS_MAT_FOLIAGE;
    }
    if (aetherisIsId(id, AETHERIS_ID_EMISSIVE)) return AETHERIS_MAT_EMISSIVE;
    return AETHERIS_MAT_DEFAULT;
}

/* Vanilla's lightmap is a 16 step ramp. Sampling the coordinate directly and
 * applying a mild curve keeps the far end of the ramp at full brightness while
 * deepening the middle, which is where "slightly darker and richer" actually comes
 * from. Multiplications instead of pow. */
float aetherisSkyLightCurve(float raw) {
    float x = saturate(raw);
    return x * x * 0.55 + x * 0.45;
}

float aetherisBlockLightCurve(float raw) {
    float x = saturate(raw);
    return x * (0.35 + 0.65 * x);
}

/* Colour and direction of the light currently casting shadows. */
void aetherisDirectLight(AetherisSky sky, out vec3 lightDir, out vec3 lightColour) {
    // The switch happens slightly below the horizon on purpose. The sun's disc is
    // still visible a little after it sets, and a hard swap exactly at zero produces
    // a one frame black flash on every surface.
    if (sky.sunDir.y > -0.02) {
        lightDir = sky.sunDir;
        lightColour = sky.sunRadiance;
    } else {
        lightDir = sky.moonDir;
        lightColour = sky.moonRadiance;
    }
}

/* Shade one opaque surface.
 *
 * albedo      surface colour, already linear
 * normal      geometric normal, camera relative world space, normalised
 * playerPos   position, camera relative world space
 * lightmap    vanilla lightmap coordinate, x sky light and y block light
 * ao          vanilla smooth lighting vertex AO, from gl_Color.a
 * material    one of the AETHERIS_MAT_ tags
 */
vec3 aetherisShadeSurface(vec3 albedo, vec3 normal, vec3 playerPos, vec2 lightmap,
                          float ao, int material, AetherisSky sky) {
    vec3 viewDir = normalize(-playerPos);

    float skyLight = aetherisSkyLightCurve(lightmap.x);
    float blockLight = aetherisBlockLightCurve(lightmap.y);

    vec3 lightDir;
    vec3 lightColour;
    aetherisDirectLight(sky, lightDir, lightColour);

    float NdotL = dot(normal, lightDir);

    // Skip the whole shadow lookup when it cannot change the result. Most of a
    // night time scene and every fully dark cave takes this path, which is worth
    // six taps a pixel on a part this small.
    float shadow = 1.0;
    if (skyLight > 0.003 && NdotL > 0.0
        && (lightColour.r + lightColour.g + lightColour.b) > 0.0008) {
        shadow = sampleShadow(playerPos, normal, NdotL);
    }

    // Wrapped diffuse. A pure Lambert terminator across one face of a block reads as
    // a hard painted line; a little wrap softens it without turning stone to felt.
    float wrap = saturate((NdotL + 0.10) * 0.909091);
    vec3 direct = lightColour * (skyLight * wrap * shadow * ao);

    // Hemisphere ambient: sky above, bounce below. The up-ness term is what gives
    // every shape in the world a top-lit gradient instead of flat fill light.
    float upness = normal.y * 0.5 + 0.5;
    vec3 ambient;
    if (material == AETHERIS_MAT_FOLIAGE) {
        ambient = aetherisFoliageAmbient(normal, sky.ambientSky, sky.ambientGround, skyLight);
    } else {
        ambient = mix(sky.ambientGround, sky.ambientSky, upness) * skyLight;
    }

    // A floor so a moonless night stays readable. Deep blue rather than grey: a
    // neutral floor is what makes cheap night scenes look like a dimmed day.
    ambient += vec3(0.074, 0.090, 0.124) * (sky.night * (0.55 + 0.45 * upness));

    // Contact shadows. A surface pressed against another reads as a soft dark line even
    // where the sun is not involved: the corner where two blocks meet, the foot of a
    // wall, the underside of an overhang. This is the shadow map used for occlusion
    // rather than for light, and it is bounded to twenty blocks because past that one
    // texel is wider than the feature it is supposed to darken. Four taps, near field
    // only, and folded out before the bound so it cannot end in a visible ring.
    //
    // It multiplies the ambient only. Direct sunlight is already answered by the shadow
    // lookup above, and darkening a sunlit face for a crease it is not in is the classic
    // way contact shadows turn into dirt.
#if SHADOWS == 1
    float eyeDistance = length(playerPos);
    if (eyeDistance < 20.0) {
        float contact = sampleShadowContact(playerPos, normal, NdotL);
        ambient *= mix(1.0, contact, 1.0 - smoothstep(12.0, 20.0, eyeDistance));
    }
#endif

    vec3 blocklightColour = vec3(1.00, 0.72, 0.42) * (blockLight * BLOCKLIGHT_STRENGTH);

    // Block light is local, so it is only partly occluded by vertex AO. Lighting a
    // torch up a corner should still be able to reach into it.
    vec3 colour = albedo * (direct + ambient * ao + blocklightColour * (0.55 + 0.45 * ao));

    if (material == AETHERIS_MAT_FOLIAGE) {
        // No extra albedo multiply here: the transmission term already carries the
        // foliage colour, and multiplying by it again double-darkens every leaf.
        colour += aetherisLeafTransmission(albedo, viewDir, lightDir, lightColour,
                                           shadow, skyLight, sky.ambientSky) * ao;
    }

    // Emissive blocks are handled through block light already, but lava, sea
    // lanterns and glowstone read flat without a little of their own colour added
    // back in, because their lightmap value is high in one channel only.
    if (material == AETHERIS_MAT_EMISSIVE) {
        colour += albedo * (1.25 * BLOCKLIGHT_STRENGTH);
    }

    return colour;
}

#endif
