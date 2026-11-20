#include "/lib/settings.glsl"
uniform sampler2D colortex3;
in vec2 texcoord;
layout(location = 0) out vec4 outEffects;

vec3 aetherisBlurQuarter(vec2 uv) {
    vec2 texel = 1.0 / vec2(textureSize(colortex3, 0));
    vec3 colour = texture(colortex3, uv).rgb * 0.40;
    colour += texture(colortex3, uv + vec2(texel.x, 0.0)).rgb * 0.15;
    colour += texture(colortex3, uv - vec2(texel.x, 0.0)).rgb * 0.15;
    colour += texture(colortex3, uv + vec2(0.0, texel.y)).rgb * 0.15;
    colour += texture(colortex3, uv - vec2(0.0, texel.y)).rgb * 0.15;
    return colour;
}
void main() {
    outEffects = vec4(aetherisBlurQuarter(texcoord), 1.0);
}
