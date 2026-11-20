#include "/lib/settings.glsl"
#include "/lib/util.glsl"

/* Shadow map fragment stage: the cutout, and a colour target it does not use.
 *
 * **The cutout is the point.** Minecraft does not alpha test in fixed function state any
 * more; the cutout lives in the shader. A shadow pass that writes depth unconditionally
 * gives every leaf block and every flower the shadow of a solid cube, which is the single
 * most obvious way a pack can look wrong under a tree. The same coverage preserving
 * threshold the visible pass uses is applied here, so the silhouette that casts the
 * shadow is the silhouette that is drawn.
 *
 * **The colour output exists only because it must.** It was removed in 1.2.0 to save the
 * 2048x2048 RGBA8 write, which is about 16.7 MB of bandwidth per frame that nothing in
 * this pack reads. That is a real saving and it was still the wrong call: a gbuffers-style
 * program that declares no fragment output at all is the least ordinary thing this pack
 * did, it cannot be verified without running the game, and it is not worth a few percent
 * of bandwidth against the risk of the whole pack refusing to load. Reliability first.
 */

uniform sampler2D gtexture;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
    if (texture(gtexture, texcoord).a < aetherisAlphaCoverage(gl_FragCoord.xy)) discard;
    outColor = vec4(1.0);
}
