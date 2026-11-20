#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/post.glsl"

/* The final pass: the only place in the pack that is display referred.
 *
 * Everything before this line is linear light at whatever brightness the scene
 * produced. Here it is antialiased, exposed, tone mapped, graded and encoded for the
 * screen, in that order, once.
 */

uniform sampler2D colortex1;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
#if ANTI_ALIASING == 1
    vec3 hdr = aetherisFXAA(colortex1, texcoord);
#else
    vec3 hdr = texture(colortex1, texcoord).rgb;
#endif

    outColor = vec4(aetherisFinish(hdr, texcoord, gl_FragCoord.xy), 1.0);
}
