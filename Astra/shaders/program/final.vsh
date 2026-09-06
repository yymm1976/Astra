// Astra v1 - placeholder vertex stage (Z1 skeleton stub)
// Uniforms: built-ins only
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
out vec2 texcoord;
void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
