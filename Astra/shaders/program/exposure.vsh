// Astra v1 - placeholder vertex stage for the auto-exposure meter (Z1 stub shape).
// Uniforms: built-ins only. The fragment stage reads no varying, so none is written.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
void main() {
	gl_Position = ftransform();
}
