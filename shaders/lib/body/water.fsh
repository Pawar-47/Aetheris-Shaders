#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#include "/lib/fog.glsl"
#include "/lib/vegetation.glsl"
#include "/lib/water.glsl"

/* The translucent pass.
 *
 * Water writes no colour at all. It writes only its surface normal and a mask, and
 * leaves colortex0 holding the opaque scene underneath. That is what lets the
 * composite pass refract the actual bottom of the lake instead of a screen space
 * blur of something that already had water mixed into it, and it is the whole
 * reason the water can be shaded properly without a second copy of the frame.
 *
 * Everything else translucent, stained glass and ice and the rest, is forward lit
 * and blended normally, with the data buffer left untouched.
 */

uniform sampler2D gtexture;

in vec2 texcoord;
in vec2 lightmapCoord;
in vec3 playerPosition;
in vec3 playerNormal;
in vec4 tint;
in float blockId;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outData;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * tint;
    if (albedo.a < 0.02) discard;

    if (aetherisIsId(blockId, AETHERIS_ID_WATER)) {
        float viewDistance = length(playerPosition);
        vec3 normal = aetherisWaterNormal(playerPosition + cameraPosition,
                                          normalize(playerNormal), viewDistance);

        // Alpha zero on the colour target contributes nothing under the pack's
        // blend function, which leaves the scene beneath intact. Alpha one on the
        // data target overwrites it cleanly.
        outColor = vec4(0.0, 0.0, 0.0, 0.0);
        outData = aetherisPackWaterData(normal, clamp(luma(albedo.rgb) * 1.75, 0.0, 1.0));
        return;
    }

    AetherisSky sky = aetherisSkyState();
    vec3 lit = aetherisShadeSurface(sRGBToLinear(albedo.rgb), normalize(playerNormal),
                                    playerPosition, lightmapCoord, 1.0,
                                    AETHERIS_MAT_DEFAULT, sky);

    outColor = vec4(aetherisApplyFog(lit, playerPosition, sky), albedo.a);

    // Alpha zero leaves colortex2 exactly as it was, under the blend function.
    outData = vec4(0.0, 0.0, 0.0, 0.0);
}
