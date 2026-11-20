#include "/lib/settings.glsl"
#include "/lib/util.glsl"

/* Shadow map fragment stage.
 *
 * Depth only, so this writes a constant. shadowtex0 is used by the shading and it
 * carries the alpha tested foliage, which is what gives tree shadows the shape of
 * the leaves instead of a solid rectangle.
 *
 * The constant is not just left at white: writing the biome tint here would be the
 * hook for coloured shadows, and the shaders.properties setting is wired up to make
 * that a one line change rather than a new pass.
 */

in float blockId;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(1.0);
}
