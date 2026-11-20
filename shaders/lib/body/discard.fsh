#include "/lib/settings.glsl"

/* Discard everything.
 *
 * Used by gbuffers_skybasic, gbuffers_skytextured and gbuffers_clouds. The sky, the
 * sun, the moon, the stars and both cloud layers are all drawn procedurally in the
 * composite pass, where the depth buffer tells us exactly which pixels are sky. So
 * Minecraft's versions are thrown away here and cost nothing but the vertex stage.
 *
 * shaders.properties also sets clouds=off, which stops the cloud quads being
 * submitted at all. This is the belt to that pair of braces: if a future version of
 * Iris stops honouring the property, the clouds still do not appear.
 */

layout(location = 0) out vec4 outColor;

void main() {
    discard;
}
