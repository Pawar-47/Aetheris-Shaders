#include "/lib/settings.glsl"
#include "/lib/util.glsl"

/* Shadow map fragment stage: depth only, with the cutout.
 *
 * Two decisions here.
 *
 * **The cutout.** Minecraft does not alpha test in fixed function state any more; the
 * cutout lives in the shader. A shadow pass that writes depth unconditionally therefore
 * gives every leaf block and every flower the shadow of a solid cube, which is the single
 * most obvious way a pack can look wrong under a tree. The same coverage preserving
 * threshold the visible pass uses is applied here, so the silhouette that casts the
 * shadow is the silhouette that is drawn.
 *
 * **No colour output.** There is no DRAWBUFFERS line and no `out` declaration, so Iris
 * allocates no shadowcolour buffer and this pass writes nothing but depth. It used to
 * write a constant white into a 2048x2048 RGBA8 attachment every frame that nothing in
 * the pack reads; on a 25 GB/s shared memory bus that is a real cost for no information.
 */

uniform sampler2D gtexture;

in vec2 texcoord;

void main() {
    if (texture(gtexture, texcoord).a < aetherisAlphaCoverage(gl_FragCoord.xy)) discard;
}
