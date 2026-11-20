#version 330 compatibility

/* RENDERTARGETS: 0 */

/* Buffer formats are declared once, as real code, in lib/body/composite.fsh. Iris reads
 * them from the shader source; keeping them in one place means there is exactly one
 * declaration per attachment and nothing to disagree with. */

#include "/lib/body/opaque.fsh"
