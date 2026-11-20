#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/atmosphere.glsl"

/* Lighting for the small additive and blended overlays.
 *
 * Deliberately unshadowed and unfogged. These are effects sitting between the eye
 * and the world: a beam of light, a glint, a raindrop. Shadowing a light beam makes
 * no sense, and the fog on a raindrop two blocks from the eye never moves.
 */

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 tint;
in vec3 playerPosition;

layout(location = 0) out vec4 outColor;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * tint;
    if (albedo.a < 0.004) discard;

    AetherisSky sky = aetherisSkyState();

    // Ambient plus a share of the direct light: enough that rain picks up a sunset
    // and a beacon beam still reads at midnight.
    vec3 light = sky.ambientSky * 1.85
               + sky.sunRadiance * 0.55
               + sky.moonRadiance * 2.20
               + vec3(0.040, 0.052, 0.075) * sky.night;

    outColor = vec4(sRGBToLinear(albedo.rgb) * light, albedo.a);
}
