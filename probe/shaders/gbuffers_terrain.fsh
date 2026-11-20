#version 330 compatibility

// Aetheris probe - fragment stage.
//
// The lightmap is deliberately not sampled. Without it the world comes out flatly and
// brightly lit, which is unmistakably not vanilla - that difference is the proof that the
// pack is running. A pack that loads but changes nothing is indistinguishable from a pack
// that did not load, and that ambiguity has cost this project several attempts.

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(gtexture, texcoord) * glcolor;
}
