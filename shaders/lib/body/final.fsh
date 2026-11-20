#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/post.glsl"

/* The final pass: the only place in the pack that is display referred.
 *
 * Everything before this line is linear light at whatever brightness the scene produced.
 * Here it is antialiased, exposed, tone mapped, graded and encoded for the screen, in that
 * order, once.
 *
 * It reads the full-resolution scene in colortex0 plus one quarter-resolution effects
 * buffer. composite1 and composite2 create that buffer only when bloom or volumetric light
 * shafts are enabled; final upsamples it before tone mapping.
 */

uniform sampler2D colortex0;
uniform sampler2D colortex4;

in vec2 texcoord;

layout(location = 0) out vec4 outColor;

void main() {
#if ANTI_ALIASING == 1
    vec3 hdr = aetherisFXAA(colortex0, texcoord);
#else
    vec3 hdr = texture(colortex0, texcoord).rgb;
#endif

#if BLOOM == 1 || VOLUMETRIC_LIGHT == 1
    hdr += texture(colortex4, texcoord).rgb;
#endif

    outColor = vec4(aetherisFinish(hdr, texcoord, gl_FragCoord.xy), 1.0);
}
