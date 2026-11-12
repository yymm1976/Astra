// Fullscreen texture coordinates for composite and the End composite entry.
// Scattering owns its light-screen projection in program/scattering.vsh.

out vec2 texcoord;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
