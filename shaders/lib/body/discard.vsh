#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"

/* Position only, for the sky and cloud programs that discard in the fragment stage.
 * Nothing is drawn by these passes; they exist so that Minecraft's own sky, sun,
 * moon and clouds are suppressed and the pack can draw its own. */
void main() {
    gl_Position = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex);
}
