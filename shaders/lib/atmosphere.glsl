#ifndef AETHERIS_ATMOSPHERE_GLSL
#define AETHERIS_ATMOSPHERE_GLSL

#include "/lib/util.glsl"

/* One atmosphere model, shared by the sun, the sky, the clouds, the fog and the
 * water reflection.
 *
 * Coherence is the point. BSL's strength is not any single effect, it is that the
 * sun colour, the sky, the haze and the bounce light all describe the same air. If
 * those are tuned independently the image falls apart at sunrise, which is where a
 * pack either looks cinematic or looks like a colour filter.
 *
 * What is physical here:
 *   - Sun and moon tint and dim through an exponential Rayleigh plus grey Mie
 *     atmosphere. Optical path length comes from the smooth airmass
 *         airmass(cosZenith) = 1 / sqrt(cosZenith^2 + eps)
 *     which stays finite and well behaved to the horizon and costs one inverse
 *     square root instead of the acos/pow of an exact Kasten-Young fit.
 *   - The Mie phase lobe, normalised so its forward peak is exactly 1.0. That
 *     normalisation is what makes it safe to multiply by any radiance: it can
 *     brighten a backlit cloud edge but can never blow the sky out.
 *
 * What is authored: the dome gradient itself, and the palette below. A full single
 * scattering integrator was evaluated for 1.0.0 and rejected. It costs four times
 * as much per sky pixel and, without a sun disc to calibrate against, is as likely
 * to produce a flat cyan dome as a beautiful one. The authored dome is *driven* by
 * the physical sun tint, so it reddens, cools and dims with the sun, but its
 * luminance ramp is chosen by eye. That is stated plainly in docs/PERFORMANCE.md
 * rather than dressed up as more than it is.
 *
 * Cost note: the dome palette is a pair of mixes, and aetherisSkyState() uses the
 * palette directly instead of evaluating the full gradient twice. The full
 * gradient is only evaluated where a pixel actually shows sky, fog or a reflection
 * that misses geometry.
 */

/* Rayleigh scattering coefficients at sea level, per unit of density. Blue
 * scatters about five times more than red, which is why the sky is blue and the
 * sunset is not. */
const vec3 RAYLEIGH_BETA = vec3(5.80e-3, 13.50e-3, 33.10e-3);

/* Grey Mie scattering: aerosol haze, the reason a real horizon is desaturated
 * rather than a pure saturated gradient. */
const float MIE_BETA = 12.50e-3;

/* The atmosphere is thinner than the real one, in the same sense that Minecraft's
 * sun is closer and its sky is smaller. This scale puts the colour response where
 * the eye expects it at Minecraft's horizon distances. */
const float ATMOSPHERE_DENSITY = 3.15;

/* Linear light palette. Chosen against the ACES curve so the display values land
 * where they should: a deep but not oversaturated zenith blue, and a pale hazy
 * horizon that meets it without a seam. */
const vec3 ZENITH_NIGHT = vec3(0.0100, 0.0150, 0.0330);
const vec3 ZENITH_DAY   = vec3(0.0700, 0.1300, 0.2900);
const vec3 HORIZON_NIGHT = vec3(0.0195, 0.0270, 0.0470);
const vec3 HORIZON_DAY   = vec3(0.3000, 0.3600, 0.4400);

/* Relative optical path through the atmosphere for a given view elevation. */
float airmass(float cosZenith) {
    return inversesqrt(cosZenith * cosZenith + 0.0022);
}

/* Transmittance of sunlight that has travelled the whole way in, at this elevation.
 * This is the palette the pack is painted with: multiply the sun, the sky's warm
 * band, the cloud rim and the water's reflection by it and they cannot disagree. */
vec3 sunTransmittance(float sunElevation) {
    float am = airmass(max(sunElevation, -0.06));
    vec3 tau = (RAYLEIGH_BETA + vec3(MIE_BETA)) * (am * ATMOSPHERE_DENSITY);
    return exp(-tau);
}

/* Rayleigh phase: symmetric, equal forward and backward lobes. */
float phaseRayleigh(float cosTheta) {
    return 0.0596831 * (1.0 + cosTheta * cosTheta);
}

/* Mie phase, Henyey-Greenstein, normalised so the forward peak (cosTheta = 1) is
 * exactly 1.0. Bounded, so it is safe to multiply by any radiance.
 *
 * This is what puts the bright halo around the sun and the silver lining along a
 * backlit cloud edge. The denominator is guarded because at g close to 1 the
 * forward peak is nearly a spike. */
float miePhaseNormalised(float cosTheta, float g) {
    float g2 = g * g;
    float forward = max(1.0 + g2 - 2.0 * g * cosTheta, 1.0e-3);
    float peak = max(1.0 + g2 - 2.0 * g, 1.0e-3);
    float a = inversesqrt(forward);
    float b = inversesqrt(peak);
    return (a * a * a) / (b * b * b);
}

/* Complete sky description for one frame. Built once at the top of a program and
 * handed to every function that needs to know about light. */
struct AetherisSky {
    vec3 sunDir;        // unit vector towards the sun, camera relative world space
    vec3 moonDir;       // unit vector towards the moon
    vec3 lightDir;      // whichever of the two is casting the shadow
    vec3 sunRadiance;   // directional sun colour, already reddened by the atmosphere
    vec3 moonRadiance;  // directional moon colour
    vec3 haze;          // colour distant geometry fades to
    vec3 ambientSky;    // sky dome ambient used for lighting
    vec3 ambientGround; // bounce light coming back off the ground
    float day;          // 0 deep night, 1 full day
    float night;        // 1 - day
    float golden;       // 0 at noon, 1 with the sun on the horizon
    float rain;         // saturate(rainStrength)
};

/* Direction of the sun in camera relative world space.
 *
 * sunPosition arrives in view space, so it is rotated back by
 * gbufferModelViewInverse. This is the one conversion in the pack that would
 * silently rotate the entire sky if it were wrong, so it happens in exactly one
 * place and nowhere else. */
vec3 aetherisSunDirection() {
    return normalize(mat3(gbufferModelViewInverse) * sunPosition);
}

vec3 aetherisMoonDirection() {
    return normalize(mat3(gbufferModelViewInverse) * moonPosition);
}

vec3 aetherisLightDirection() {
    return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
}

/* The dome's two pole colours for this frame. Two mixes, no trigonometry. */
void aetherisDomePalette(AetherisSky sky, out vec3 zenith, out vec3 horizon) {
    zenith = mix(ZENITH_NIGHT, ZENITH_DAY, sky.day);
    horizon = mix(HORIZON_NIGHT, HORIZON_DAY, sky.day);
}

/* The authored dome gradient.
 *
 * dir must be normalised, in camera relative world space. Every colour is linear
 * light in the same units as the sun, so the sun and the dome can be added.
 *
 * pow() is avoided deliberately. This runs for every sky pixel, every water
 * reflection that misses geometry, and for the fog on every terrain pixel. sqrt is
 * one instruction; pow is a call. */
vec3 aetherisSkyGradient(vec3 dir, AetherisSky sky) {
    float above = saturate(dir.y);
    float height = sqrt(above);

    vec3 zenith;
    vec3 horizon;
    aetherisDomePalette(sky, zenith, horizon);

    // How far this direction looks towards the sun, flattened onto the horizon.
    // The 1e-4 guards against a zero length vector when dir is straight up.
    vec2 flatDir = normalize(vec2(dir.x, dir.z) + vec2(1.0e-4, 0.0));
    vec2 flatSun = normalize(vec2(sky.sunDir.x, sky.sunDir.z) + vec2(1.0e-4, 0.0));
    float towardsSun = saturate(dot(flatDir, flatSun) * 0.5 + 0.5);

    // Warm band along the horizon on the sun's side, only while the sun is low. The
    // sun's own transmittance supplies the colour, so this cannot drift away from
    // the colour of the sunlight falling on the terrain.
    float bandHeight = 1.0 - saturate(abs(dir.y) * 2.2);
    float band = sky.golden * bandHeight * bandHeight * towardsSun * towardsSun;
    vec3 bandTint = sunTransmittance(clamp(sky.sunDir.y, 0.0, 1.0)) * vec3(1.35, 0.95, 0.72);
    horizon = mix(horizon, bandTint * 0.62, saturate(band) * 0.80);

    // The anti solar side cools as the sun sets. This is what stops a sunset from
    // looking like an orange filter laid over a blue photograph.
    horizon = mix(horizon, horizon * vec3(0.72, 0.84, 1.12), sky.golden * (1.0 - towardsSun) * 0.55);

    vec3 colour = mix(horizon, zenith, height);

    // Below the horizon fade into haze instead of wrapping the dome round, so the
    // sky under the cloud deck reads as distance and not as a second sky.
    colour *= mix(1.0, 0.55, 1.0 - smoothstep(-0.35, 0.0, dir.y));

    // A whisper of the vanilla fog colour: enough to keep the Nether red and the
    // End purple, not enough to tint an ordinary horizon.
    colour = mix(colour, fogColor, 0.07 * (1.0 - height));

    // Rain flattens and greys the dome rather than darkening it into a bruise.
    colour = mix(colour, vec3(luma(colour)) * vec3(0.88, 0.91, 0.96), sky.rain * 0.55);

    return colour;
}

/* The colour distant geometry fades to.
 *
 * The dome gradient evaluated at the horizon, which is what makes the fog and the
 * sky agree exactly at the seam where the world ends. Evaluating the same function
 * rather than a parallel ramp is the cheapest trick in the pack for a coherent
 * horizon.
 *
 * Clamping y keeps the haze stable when looking down a valley or off a mountain,
 * and stops the below horizon darkening from making the fog darker than the sky it
 * meets. */
vec3 aetherisHazeColour(vec3 dir, AetherisSky sky) {
    vec3 flat = vec3(dir.x, 0.022, dir.z);
    if (dot(flat, flat) < 1.0e-8) flat = vec3(0.0, 1.0, 0.0);
    return aetherisSkyGradient(normalize(flat), sky);
}

/* Build the frame state. One call per program, in a body file, before anything
 * else. */
AetherisSky aetherisSkyState() {
    AetherisSky sky;

    sky.sunDir = aetherisSunDirection();
    sky.moonDir = aetherisMoonDirection();
    sky.lightDir = aetherisLightDirection();

    sky.day = smoothstep(-0.115, 0.165, sky.sunDir.y);
    sky.night = 1.0 - sky.day;
    sky.rain = saturate(rainStrength);

    vec3 tint = sunTransmittance(sky.sunDir.y);
    sky.sunRadiance = tint * (SUN_STRENGTH * sky.day);

    // Moonlight is reflected sunlight, so it inherits a cool cast and a tiny
    // fraction of the energy. Pure black nights are unplayable and read as broken
    // rather than as night.
    sky.moonRadiance = vec3(0.42, 0.56, 0.92) * (0.085 * sky.night);

    sky.golden = saturate((tint.r - tint.b) * 3.6) * smoothstep(-0.09, 0.13, sky.sunDir.y);

    vec3 zenith;
    vec3 horizon;
    aetherisDomePalette(sky, zenith, horizon);

    // Ambient sky light samples the dome palette, so it tracks the dome's own
    // colour through the day and cannot disagree with what is drawn above.
    vec3 mixed = mix(horizon, zenith, 0.35);
    vec3 warmLift = sunTransmittance(clamp(sky.sunDir.y, 0.0, 1.0)) * (0.055 * sky.golden);

    sky.ambientSky = (mixed * 0.45 + warmLift) * AMBIENT_STRENGTH;
    sky.haze = horizon;

    // Bounce off the ground: warm, desaturated, and darker than the sky. A little of
    // the sun's tint is folded in so a golden hour bounce is golden too.
    sky.ambientGround = sky.ambientSky * vec3(0.52, 0.46, 0.36)
                      + tint * vec3(0.030, 0.024, 0.016) * sky.day;

    return sky;
}

#endif
