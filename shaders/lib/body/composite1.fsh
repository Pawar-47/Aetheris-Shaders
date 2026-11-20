#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex1;
in vec2 texcoord;
layout(location = 0) out vec4 outEffects;

vec3 aetherisExtractBloom(vec3 colour) {
    // R11F_G11F_B10F is unsigned HDR. Bloom is radiance, so discard any negative
    // pre-grade channel before writing the compact no-sign-bit effect buffer.
    colour = max(colour, vec3(0.0));
    float brightness = max(max(colour.r, colour.g), colour.b);
    float knee = max(BLOOM_THRESHOLD * 0.5, 1.0e-4);
    float soft = clamp(brightness - BLOOM_THRESHOLD + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1.0e-4);
    float contribution = max(brightness - BLOOM_THRESHOLD, soft);
    return colour * (contribution / max(brightness, 1.0e-4));
}

vec3 aetherisDownsampleScene(vec2 uv) {
    vec2 offset = 1.5 / vec2(viewWidth, viewHeight);
    vec3 a = texture(colortex0, uv + vec2(-offset.x, -offset.y)).rgb;
    vec3 b = texture(colortex0, uv + vec2( offset.x, -offset.y)).rgb;
    vec3 c = texture(colortex0, uv + vec2(-offset.x,  offset.y)).rgb;
    vec3 d = texture(colortex0, uv + vec2( offset.x,  offset.y)).rgb;
    return (a + b + c + d) * 0.25;
}

vec3 aetherisLightShafts(vec2 uv) {
#if VOLUMETRIC_LIGHT == 0
    return vec3(0.0);
#else
    vec4 sunClip = gbufferProjection * vec4(sunPosition, 0.0);
    if (sunClip.w <= 1.0e-4) return vec3(0.0);
    vec2 sunUV = sunClip.xy / sunClip.w * 0.5 + 0.5;
    if (sunUV.x <= 0.0 || sunUV.x >= 1.0 || sunUV.y <= 0.0 || sunUV.y >= 1.0) return vec3(0.0);

    vec2 ray = sunUV - uv;
    vec3 accumulated = vec3(0.0);
    float decay = 1.0;
    for (int i = 0; i < VOLUMETRIC_STEPS; i++) {
        float linearStep = (float(i) + 0.5) / float(VOLUMETRIC_STEPS);
        float t = 1.0 - (1.0 - linearStep) * (1.0 - linearStep);
        vec2 sampleUV = uv + ray * t;
        float sceneDepth = texture(depthtex1, sampleUV).r;
        float skyVisibility = smoothstep(0.995, 1.0, sceneDepth);
        if (skyVisibility > 0.001) {
            vec3 source = texture(colortex0, sampleUV).rgb;
            vec3 brightSource = max(source - vec3(BLOOM_THRESHOLD), vec3(0.0));
            accumulated += brightSource * (skyVisibility * decay);
        }
        decay *= 0.86;
    }
    float radialFade = saturate(1.0 - length(ray) * 0.35);
    return accumulated * (VOLUMETRIC_STRENGTH / float(VOLUMETRIC_STEPS)) * radialFade;
#endif
}

void main() {
    vec3 effects = vec3(0.0);
#if BLOOM == 1
    effects += aetherisExtractBloom(aetherisDownsampleScene(texcoord)) * BLOOM_STRENGTH;
#endif
#if VOLUMETRIC_LIGHT == 1
    effects += aetherisLightShafts(texcoord);
#endif
    outEffects = vec4(effects, 1.0);
}
