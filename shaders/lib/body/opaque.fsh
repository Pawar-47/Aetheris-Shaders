#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#include "/lib/fog.glsl"

/* Forward shading for every opaque surface.
 *
 * The order is the order light arrives in, and it is applied here rather than in a
 * deferred pass on purpose: see the note at the top of lib/lighting.glsl.
 */

uniform sampler2D gtexture;

in vec2 texcoord;
in vec2 lightmapCoord;
in vec3 playerPosition;
in vec3 playerNormal;
in vec4 tint;
in float blockId;

layout(location = 0) out vec4 outColor;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * tint;

    // Coverage preserving alpha test. Solid blocks have alpha 1 and always pass,
    // cutout foliage keeps its fraction of each 4x4 tile, and it costs a table
    // lookup instead of nothing at all.
    if (albedo.a < aetherisAlphaCoverage(gl_FragCoord.xy)) discard;

    AetherisSky sky = aetherisSkyState();
    int material = aetherisMaterialFromId(blockId);

    // Vanilla stores its smooth lighting AO in the vertex colour's alpha. Compressed
    // rather than used raw: a fully occluded corner at zero would read as a hole,
    // and some geometry comes through with alpha unset, where the compression
    // correctly leaves it fully lit.
    float vertexAO = saturate(tint.a);
    float ao = 0.45 + 0.55 * vertexAO;

    vec3 colour = aetherisShadeSurface(sRGBToLinear(albedo.rgb), normalize(playerNormal),
                                       playerPosition, lightmapCoord, ao, material, sky);

    colour = aetherisApplyFog(colour, playerPosition, sky);

    outColor = vec4(colour, 1.0);
}
