#ifndef AETHERIS_VEGETATION_GLSL
#define AETHERIS_VEGETATION_GLSL

#include "/lib/util.glsl"

/* Vegetation: identity, wind, and the light that comes through a leaf.
 *
 * A note on what shader code can and cannot do here. It cannot change the shape of
 * a vanilla leaf block or a grass tuft; no pack without a resource pack can, and
 * this pack deliberately ships no resource pack. What it can do is decide how those
 * flat quads are lit, how they move, and how they sit in the air. That is where
 * every bit of the improvement below comes from, and the README says so rather than
 * implying the geometry changed.
 *
 * Identity comes from mc_Entity, which Iris fills from shaders/block.properties.
 * If that file is ever dropped the IDs read 0 and the foliage gets plain terrain
 * shading: a graceful degradation, not a crash.
 */

/* IDs assigned in shaders/block.properties. Kept in one place so the two files can
 * be checked against each other. */
const float AETHERIS_ID_LEAVES = 10000.0;
const float AETHERIS_ID_PLANT  = 10100.0;
const float AETHERIS_ID_WATER  = 10200.0;
const float AETHERIS_ID_EMISSIVE = 10300.0;
const float AETHERIS_ID_GLOSS = 10400.0;

bool aetherisIsId(float id, float wanted) {
    return abs(id - wanted) < 0.5;
}

/* True when a fragment is a water surface.
 *
 * Three signals, most specific first, because the whole water pipeline hangs on this
 * one test. Get it wrong and water falls through to the plain translucent path: flat,
 * barely tinted, and indistinguishable from vanilla.
 *
 *   1. The ID from shaders/block.properties.
 *   2. Iris' legacy numbering, used when block.properties is absent or unreadable:
 *      water is 8 (flowing) and 9 (still) in the pre-1.13 block IDs.
 *   3. A fluid that is not lighting itself. Iris documents mc_Entity.y as 1.0 for
 *      fluids and -1.0 otherwise, and lava is the only other fluid that reaches this
 *      pass. Lava always reports block light at its own surface, which is what keeps
 *      it out of the water branch when the ID map has failed and both read -1.
 *
 * The third signal is the reason this is a function rather than an equality test in
 * gbuffers_water: it is the difference between "water works" and "water works only if
 * Iris parsed one particular file the way it was expected to".
 */
bool aetherisIsWater(float id, float renderType, float blockLight) {
    if (aetherisIsId(id, AETHERIS_ID_WATER)) return true;
    if (aetherisIsId(id, 8.0) || aetherisIsId(id, 9.0)) return true;
    return renderType > 0.5 && id < -0.5 && blockLight < 0.5;
}

/* How much this vertex is allowed to move.
 *
 * Leaves are a full cube, so they all move together and a constant weight is right.
 *
 * Plants get their weight from the texture's v coordinate, not from world height.
 * This is not a shortcut, it is the only thing that works: a plant's base and its
 * tip are exactly one block apart in world space, and every 1-periodic function of
 * height returns the same value for both. Any pack that sways grass by
 * fract(worldPos.y) is swaying nothing at all. Minecraft maps the top of a plant
 * model to v = 0, so 1 - v is the height up the plant, and the smoothstep keeps the
 * rooted part still instead of sliding it across the ground.
 */
float aetherisWindWeight(float id, float textureV) {
    if (aetherisIsId(id, AETHERIS_ID_LEAVES)) return 0.34;
    if (aetherisIsId(id, AETHERIS_ID_PLANT)) {
        float t = saturate(1.0 - textureV);
        return t * t * (3.0 - 2.0 * t) * 0.85;
    }
    return 0.0;
}

/* Wind displacement in camera relative world space.
 *
 * Two decisions here do most of the work.
 *
 * First, the gust field is smooth in space, sampled from a slowly travelling value
 * noise rather than from a per block hash. A per block random phase makes every
 * leaf block move on its own and tears the canopy apart at the block seams, which
 * is the difference between wind and confetti.
 *
 * Second, the amplitude is modulated by that same field. Uniform swaying is the
 * tell of a procedural forest: real vegetation moves in patches, as a gust crosses
 * it, with calm space between.
 */
vec3 aetherisWindOffset(vec3 worldPos, float weight) {
#if VEGETATION_WIND == 0
    return vec3(0.0);
#else
    if (weight <= 0.0) return vec3(0.0);

    float time = frameTimeCounter;
    vec2 p = worldPos.xz;

    // Slow gust front travelling across the world, and a faster ripple riding it.
    float gust = valueNoise(p * 0.055 + vec2(time * 0.30, time * 0.19));
    float ripple = valueNoise(p * 0.230 - vec2(time * 0.55, time * 0.41));

    // Two waves at an irrational ratio so the pattern never repeats visibly.
    float phase = time * 1.70 + p.x * 0.42 + p.y * 0.33;
    float sway = sin(phase) * (0.55 + 0.45 * gust)
               + sin(phase * 1.91 + 1.70) * 0.30 * ripple;

    // Rain makes it thrash.
    float storm = 0.055 + 0.085 * gust;
    storm *= 1.0 + 0.60 * saturate(rainStrength);

    vec2 direction = normalize(vec2(0.80, 0.60));
    return vec3(direction.x, 0.0, direction.y) * (sway * storm * weight);
#endif
}

/* Light transmitted through a leaf.
 *
 * A leaf is a thin translucent membrane. Sunlight that comes through it emerges
 * tinted by what the pigment did not absorb, and it is strongest when the eye is
 * looking straight into the light, which is why a canopy against a low sun glows
 * and the same canopy with the sun behind you does not.
 *
 * viewDir points from the eye towards the surface, lightDir points at the sun, so
 * the two agreeing is backlighting. The fourth power keeps it to the true rim
 * rather than washing the whole canopy.
 */
vec3 aetherisLeafTransmission(vec3 albedo, vec3 viewDir, vec3 lightDir,
                              vec3 lightColour, float shadow, float skyLight,
                              vec3 ambientSky) {
    float back = saturate(dot(viewDir, lightDir));
    float rim = back * back;
    rim *= rim;

    // Chlorophyll passes green and yellow, absorbs red and blue.
    vec3 transmitted = albedo * vec3(1.12, 1.26, 0.72);

    vec3 sunThrough = transmitted * lightColour * (rim * 0.85 * skyLight * shadow);
    vec3 skyThrough = transmitted * ambientSky * (0.30 * (0.35 + 0.65 * rim));

    return sunThrough + skyThrough;
}

/* Extra shading for a leaf or a plant, on top of the plain terrain response.
 *
 * The top of a leaf block faces the sky and should take most of its light from
 * there; the underside is in its own shadow and reads almost black in vanilla.
 * Lifting the underside a little and pushing the upward faces keeps a canopy from
 * looking like a solid ball of one flat green, which is the single biggest visual
 * difference between vanilla foliage and shader foliage.
 */
vec3 aetherisFoliageAmbient(vec3 normal, vec3 ambientSky, vec3 ambientGround, float skyLight) {
    // Steeper than the terrain hemisphere term: leaves are thin, so the difference
    // between a face looking up and one looking down is larger than for a wall.
    float up = saturate(normal.y);
    float weight = up * up * 0.75 + up * 0.25;

    vec3 ambient = mix(ambientGround * 0.80, ambientSky, weight);

    // A leaf is translucent to skylight too: it glows faintly from inside even with
    // no direct sun, which is what stops a shaded canopy reading as a black hole.
    ambient += ambientSky * (0.16 * skyLight);

    return ambient * skyLight;
}

#endif
