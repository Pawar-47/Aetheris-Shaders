#ifndef AETHERIS_SETTINGS_GLSL
#define AETHERIS_SETTINGS_GLSL

/* Aetheris Shaders - options and hardware constants.
 *
 * Every user option in this file is a #define with its allowed values in a trailing
 * comment, and that is not a style preference.
 *
 * Iris only recognises a fixed list of `const` option names: shadowMapResolution,
 * shadowDistance, sunPathRotation, ambientOcclusionLevel, superSamplingLevel,
 * noiseTextureResolution and a set of shadow map flags. A `const float SUN_STRENGTH`
 * is not an option at all, whatever comment follows it, and Iris says so only in a
 * diagnostic that never reaches the user. This file declared every slider that way.
 *
 * The consequence is worth writing down because it cost a release: the pack shipped
 * with an option set containing only the #defines, while shaders.properties referred
 * to the const names from screen.*, sliders and every profile.*. Iris builds the
 * settings menu from those references, so choosing the pack failed while applying it
 * and the error details had nothing in them. Anything the user can change is a #define
 * from here on, and tools/validate.py enforces it.
 *
 * Everything is a compile time option, or a constant that describes the machine this
 * pack is tuned for: an Intel Core i3-5005U with Intel HD Graphics 5500.
 *
 * Intel's 5th-generation graphics guide lists 24 EUs (23 on some Core i3 SKUs) and
 * only three texture samplers for HD 5500. The platform shares system RAM with the CPU;
 * 25.6 GB/s is the dual-channel maximum, not a guarantee for every 8 GB configuration.
 * The budget decisions are documented in docs/PERFORMANCE.md: keep one shadow map and
 * forward geometry, bound every ray/sample loop, and run bloom/light shafts in quarter-
 * resolution composite buffers. No effect is removed by the Performance profile.
 */

/* --------------------------------------------------------------------------
 * Quality toggles
 * ----------------------------------------------------------------------- */

// Shadows: 0 disables the shadow render pass entirely, not just the lookups.
#define SHADOWS 1 // [0 1]

// The soft shadow kernel. 4 is hard and cheap, 9 is soft and costs 9 taps.
#define SHADOW_SAMPLES 4 // [4 6 9]

const int shadowMapResolution = 1024; // [512 1024 2048]

const float shadowDistance = 64.0; // [48.0 64.0 80.0 96.0 128.0]

const float shadowDistanceRenderMul = 1.0; // [0.5 0.75 1.0]

// Screen space ambient occlusion. Runs once per screen pixel in composite.
#define SSAO 1 // [0 1]

#define SSAO_SAMPLES 4 // [4 6 9]

// Screen space reflections for the water surface.
#define WATER_REFLECTIONS 1 // [0 1]

// March steps for the reflection ray. This is the single most expensive loop in
// the pack and it only runs on water pixels.
#define REFLECTION_STEPS 5 // [4 5 6 8 10]

// Procedural clouds. 0 removes the whole cloud march.
#define CLOUDS 1 // [0 1]

// Steps through the cloud slab. 5 is soft and cheap, 12 is the most this GPU
// should ever see.
#define CLOUD_STEPS 5 // [4 5 8 12]

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

// Bloom and screen-space volumetric shafts share two quarter-resolution passes.
#define BLOOM 1 // [0 1]
#define BLOOM_STRENGTH 0.10 // [0.05 0.10 0.15 0.25]
#define BLOOM_THRESHOLD 1.2 // [0.8 1.0 1.2 1.5 2.0]
#define VOLUMETRIC_LIGHT 1 // [0 1]
#define VOLUMETRIC_STEPS 4 // [4 6 8]
#define VOLUMETRIC_STRENGTH 0.08 // [0.04 0.08 0.12 0.18]
#define MATERIAL_GLOSS 1 // [0 1]
#define MATERIAL_GLOSS_STRENGTH 0.25 // [0.10 0.25 0.40 0.60]

/* --------------------------------------------------------------------------
 * Scene sliders
 * ----------------------------------------------------------------------- */

// Directional sun. The scene is built around 2.1: bright enough to keep highlights off
// the ACES shoulder, dark enough that a lit surface is not already white.
#define SUN_STRENGTH 2.10 // [1.00 2.10 3.00 4.00]

// Sun and moon size. 1.0 is MakeUp's disc, which is already several times vanilla's; 0.5 is
// roughly vanilla, 3.0 is a deliberately stylised big sun. The shape is a soft-edged disc
// with a solid core, so it stays clean at any size.
#define SUN_SIZE 1.0 // [0.5 1.0 1.5 2.0 3.0]

#define AMBIENT_STRENGTH 1.0 // [0.0 1.0 3.0]

#define BLOCKLIGHT_STRENGTH 1.0 // [0.0 1.0 3.0]

// Distance haze and height fog. 0.0 removes fog entirely, including the fade that hides
// the edge of the render distance; 0.5 is the designed look, and anything past 1.5 is
// deliberate mist.
#define FOG_DENSITY 0.35 // [0.0 0.35 0.5 1.0 1.5 2.0]

#define FOG_HEIGHT 72.0 // [24.0 72.0 256.0]

// Blocks before the haze starts to build. Below this the air is clear, which is the
// difference between atmosphere and permanent mist. 512 is effectively off.
#define FOG_START 56.0 // [0.0 32.0 56.0 96.0 160.0 512.0]

#define CLOUD_COVERAGE 0.45 // [0.0 0.45 1.0]

#define CLOUD_ALTITUDE 180.0 // [120.0 180.0 320.0]

#define CLOUD_SCALE 1.0 // [0.5 1.0 2.0]

#define CLOUD_SPEED 1.0 // [0.0 1.0 3.0]

// Cloud edge treatment. 0.0 is the stylised look: defined silhouettes, flat bases and puffs
// that have a body. 1.0 is wispy and soft, which at this step count reads as drizzle rather
// than as weather.
#define CLOUD_SOFTNESS 0.0 // [0.0 0.5 1.0]

#define WATER_WAVE_HEIGHT 1.0 // [0.0 1.0 2.5]

#define WATER_WAVE_SPEED 1.0 // [0.0 1.0 2.0]

#define WATER_CLARITY 1.0 // [0.0 1.0 2.5]

// Refraction offset strength in screen proportions.
#define WATER_REFRACTION 1.0 // [0.0 0.5 1.0 1.5 2.0]

// The sea itself, authored as 0-255 per channel and squared into linear light, the way MakeUp
// authors its water. Blue above green above red is sea water; raising red is what turns it
// into a lake, and raising all three makes it a tropical shelf. These three numbers are the
// whole water body colour, seen both from above and from inside.
#define WATER_RED 27 // [12 27 40 60 90]
#define WATER_GREEN 74 // [40 74 110 140 180]
#define WATER_BLUE 108 // [70 108 150 180 220]

// How strongly the water column colours what is seen through it, and how much of the
// medium there is to see when the eye is inside it. 1.0 is the designed look; 0 turns
// underwater into clear air, which is useful for finding a bug in the fog rather than
// for playing.
#define UNDERWATER_TINT 1.0 // [0.0 1.0 2.0]

// The penumbra width. 0.8 is the Performance preset, 1.25 the Visual one.
#define SHADOW_SOFTNESS 0.8 // [0.5 0.8 1.0 1.25 2.5]

/* --------------------------------------------------------------------------
 * Colour grading
 * ----------------------------------------------------------------------- */

#define COLOR_EXPOSURE 1.0 // [0.25 1.0 2.5]

#define COLOR_SATURATION 1.02 // [0.0 1.02 2.0]

#define COLOR_CONTRAST 1.0 // [0.5 1.0 1.5]

// Positive warms the image, negative cools it.
#define COLOR_TEMPERATURE 0.0 // [-1.0 0.0 1.0]

#define COLOR_VIGNETTE 0.15 // [0.0 0.15 1.0]

#endif
