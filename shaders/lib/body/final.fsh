#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/post.glsl"

/* The final pass: the only place in the pack that is display referred.
 *
 * Everything before this line is linear light at whatever brightness the scene produced.
 * Here it is antialiased, exposed, tone mapped, graded and encoded for the screen, in that
 * order, once.
 *
 * It reads colortex0, which is also what composite writes. That is the same single buffer
 * layout the Iris 1.21.5 template uses: one colour attachment, read and written by the
 * fullscreen passes, with the loader flipping between two physical textures so a pass can
 * read what the previous one wrote. There is no second colour buffer, and therefore no way
 * for this pass to read an attachment that nothing has filled.
 */

uniform sampler2D colortex0;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
#if ANTI_ALIASING == 1
    vec3 hdr = aetherisFXAA(colortex0, texcoord);
#else
    vec3 hdr = texture(colortex0, texcoord).rgb;
#endif

    outColor = vec4(aetherisFinish(hdr, texcoord, gl_FragCoord.xy), 1.0);
}
