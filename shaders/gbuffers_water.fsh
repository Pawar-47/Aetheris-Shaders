#version 330 compatibility

/* RENDERTARGETS: 0, 2 */

/*
const int colortex2Format = RGBA16F;
*/

/* Two targets. Output 0 goes to colortex0 for everything translucent that is not
 * water, and output 1 goes to colortex2 for the water surface data. See
 * lib/body/water.fsh for why water deliberately writes no colour. */

#include "/lib/body/water.fsh"
