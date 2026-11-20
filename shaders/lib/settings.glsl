#ifndef AETHERIS_SETTINGS_GLSL
#define AETHERIS_SETTINGS_GLSL

/* Aetheris Shaders - options and hardware constants.
 *
 * Everything in this file is either a compile time option that Iris exposes in
 * the shader pack settings screen, or a constant that describes the machine this
 * pack is tuned for: an Intel Core i3-5005U with Intel HD Graphics 5500.
 *
 * The HD 5500 is a 24 EU Broadwell part sharing a 25.6 GB/s memory bus with the
 * CPU. The budget decisions that follow from that are documented in
 * docs/PERFORMANCE.md: one shadow map, one geometry pass, two fullscreen passes,
 * no bloom chain, and every expensive loop bounded by a constant the user can
 * turn down.
 */

/* --------------------------------------------------------------------------
 * Quality toggles
 * ----------------------------------------------------------------------- */

// Shadows: 0 disables the shadow render pass entirely, not just the lookups.
#define SHADOWS 1 // [0 1]

// The soft shadow kernel. 4 is hard and cheap, 9 is soft and costs 9 taps.
#define SHADOW_SAMPLES 6 // [4 6 9]

const int shadowMapResolution = 2048; // [1024 1536 2048 3072]

const float shadowDistance = 96.0; // [64.0 80.0 96.0 128.0]

// Screen space ambient occlusion. Runs once per screen pixel in composite.
#define SSAO 1 // [0 1]

#define SSAO_SAMPLES 6 // [4 6 9]

// Screen space reflections for the water surface.
#define WATER_REFLECTIONS 1 // [0 1]

// March steps for the reflection ray. This is the single most expensive loop in
// the pack and it only runs on water pixels.
#define REFLECTION_STEPS 8 // [6 8 10]

// Refraction offset strength in screen proportions.
const float WATER_REFRACTION = 1.0; // [0.0 0.5 1.0 1.5 2.0]

// Procedural clouds. 0 removes the whole cloud march.
#define CLOUDS 1 // [0 1]

// Steps through the cloud slab. 5 is soft and cheap, 12 is the most this GPU
// should ever see.
#define CLOUD_STEPS 8 // [5 8 12]

// Rag cloud edges with a second noise octave.
#define CLOUD_DETAIL 1 // [0 1]

// Cirrus veil high above the cumulus deck.
#define CLOUD_CIRRUS 1 // [0 1]

// Wind animation for leaves, grass and crops. Matched in the shadow pass.
#define VEGETATION_WIND 1 // [0 1]

// Wind animation for the water surface.
#define WATER_WAVES 1 // [0 1]

// FXAA in final. Cheap, and this GPU needs it at 720p and below.
#define ANTI_ALIASING 1 // [0 1]

/* --------------------------------------------------------------------------
 * Scene sliders
 * ----------------------------------------------------------------------- */

const float SUN_STRENGTH = 2.10; // [0.25 2.1500000953674316 4.0]

const float AMBIENT_STRENGTH = 1.00; // [0.0 1.0 3.0]

const float BLOCKLIGHT_STRENGTH = 1.00; // [0.0 1.0 3.0]

const float FOG_DENSITY = 1.00; // [0.0 1.0 3.0]

const float FOG_HEIGHT = 72.0; // [24.0 72.0 256.0]

const float CLOUD_COVERAGE = 0.45; // [0.0 0.45 1.0]

const float CLOUD_ALTITUDE = 180.0; // [120.0 180.0 320.0]

const float CLOUD_SCALE = 1.00; // [0.5 1.0 2.0]

const float CLOUD_SPEED = 1.00; // [0.0 1.0 3.0]

const float WATER_WAVE_HEIGHT = 1.00; // [0.0 1.0 2.5]

const float WATER_WAVE_SPEED = 1.00; // [0.0 1.0 2.0]

const float WATER_CLARITY = 1.00; // [0.0 1.0 2.5]

// How strongly the water column colours what is seen through it, and how much of the
// medium there is to see when the eye is inside it. 1.0 is the designed look; 0 turns
// underwater into clear air, which is useful for finding a bug in the fog rather than
// for playing.
const float UNDERWATER_TINT = 1.00; // [0.0 1.0 2.0]

const float SHADOW_SOFTNESS = 1.00; // [0.5 1.0 2.5]

/* --------------------------------------------------------------------------
 * Colour grading
 * ----------------------------------------------------------------------- */

const float COLOR_EXPOSURE = 1.00; // [0.25 1.0 2.5]

const float COLOR_SATURATION = 1.02; // [0.0 1.02 2.0]

const float COLOR_CONTRAST = 1.00; // [0.5 1.0 1.5]

// Positive warms the image, negative cools it.
const float COLOR_TEMPERATURE = 0.00; // [-1.0 0.0 1.0]

const float COLOR_VIGNETTE = 0.15; // [0.0 0.15 1.0]

#endif
