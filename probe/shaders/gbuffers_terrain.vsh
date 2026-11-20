#version 330 compatibility

// Aetheris probe - vertex stage.
//
// This pack exists to answer one question that nothing in the repository can answer:
// does ANY shader pack load on this machine? It is deliberately the smallest thing that
// can be described as a shader pack: one program, no configuration files, no #include,
// no custom render targets, no block map, no language file. It is shaped exactly like
// the Iris 1.21.5 template's gbuffers_terrain.
//
// If this loads and Aetheris does not, the fault is in Aetheris. If this also fails, the
// problem is the Iris install, the Minecraft version, or where the zip was put.

out vec2 texcoord;
out vec4 glcolor;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
}
