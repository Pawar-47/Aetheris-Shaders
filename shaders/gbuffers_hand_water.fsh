#version 330 compatibility

/* DRAWBUFFERS:0 */

/* The held item seen while the eye is submerged. It is lit like any other opaque
 * surface; the water it appears through is handled by the fog when the eye is in
 * water, so this program does not need a second copy of the water shading. */

#include "/lib/body/opaque.fsh"
