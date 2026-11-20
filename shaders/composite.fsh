#version 330 compatibility

/* DRAWBUFFERS:1 */

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA8;
*/

/* Reads colortex0 and colortex2 and writes colortex1. It never reads and writes the
 * same buffer in one pass: on a GPU this small, relying on the driver to ping-pong
 * a target correctly is not a risk worth taking when the fix is one line. */

#include "/lib/body/composite.fsh"
