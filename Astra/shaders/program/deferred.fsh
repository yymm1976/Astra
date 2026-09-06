// E2: retain unattenuated HDR in 4; medium is applied once to display buffer 0.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
in vec2 texcoord;
/* RENDERTARGETS: 0,4 */
void main() {
    vec3 source = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;
    vec3 displayed = source;
    if (depth < 0.999999) {
        uint lightData = uint(round(texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0).r * 255.0));
        if ((lightData & 128u) != 0u) depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
        vec3 playerPos = view_player(screen_view(vec3(texcoord, depth)));
        float skylight = float(lightData & 127u) / 127.0;
        displayed = astra_apply_medium(source, playerPos, skylight);
    }
    gl_FragData[0] = vec4(displayed, 1.0);
    gl_FragData[1] = vec4(source, 1.0);
}
