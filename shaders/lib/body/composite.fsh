#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/depth.glsl"
#include "/lib/fog.glsl"
#include "/lib/sky.glsl"
#include "/lib/ssao.glsl"
#include "/lib/water_composite.glsl"

/* The composite pass.
 *
 * This is where the pack stops being forward. Three kinds of pixel arrive here:
 *
 *   - Sky. Empty depth. The whole dome, both cloud layers, the sun and the moon are
 *     drawn here and nowhere else, which is why Minecraft's own sky programs discard.
 *   - Water. Flagged in colortex2 by the translucent pass. Fully shaded here, with
 *     refractive sampling, absorption, screen space reflection and Fresnel.
 *   - Everything else. Already lit and already fogged by the geometry pass. The only
 *     work left is ambient occlusion, and even that is skipped past 46 blocks, so
 *     most of a typical frame costs one texture fetch and a branch.
 *
 * That last line is the whole performance story of the pack at a glance.
 */

/* colortex0 is declared by lib/water_composite.glsl, which is included above and reads
 * it for the refraction sample and the reflection march. It must not be declared
 * again here: two declarations of the same uniform in one translation unit are a
 * redefinition, and Mesa rejects the program outright for it. One rejected program is
 * enough for Iris to drop the whole pack and fall back to vanilla rendering, which is
 * a silent, total failure of everything the pack does. */
uniform sampler2D colortex2;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
    vec2 uv = texcoord;
    AetherisSky sky = aetherisSkyState();

    float depth = texture(depthtex0, uv).r;
    vec3 colour;

    if (depth >= 1.0) {
        // No geometry here, so nothing wrote a depth value. This is sky.
        if (isEyeInWater == 1) {
            // Underwater there is no sky to see, only the medium.
            vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewRayDirection(uv));
            colour = aetherisUnderwaterTint(sky, worldDir);
        } else {
            vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewRayDirection(uv));
            colour = aetherisRenderSky(worldDir, sky);
        }
    } else {
        vec3 sceneColour = texture(colortex0, uv).rgb;
        vec4 waterData = texture(colortex2, uv);

        if (waterData.a > 0.5) {
            colour = aetherisWaterSurface(uv, waterData, sky, sceneColour);
        } else {
            colour = sceneColour * aetherisSSAO(uv, depth);
        }
    }

    outColor = vec4(colour, 1.0);
}
