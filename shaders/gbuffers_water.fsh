#version 330 compatibility

/* RENDERTARGETS: 0,2 */

/* Two targets. Output 0 goes to colortex0 for everything translucent that is not water,
 * and output 1 goes to colortex2 for the water surface data. See lib/body/water.fsh for
 * why water deliberately writes no colour.
 *
 * No space after the comma. Iris parses each entry of this list with Integer.parseInt, so
 * "0, 2" hands it " 2" and the pack fails to load with
 * java.lang.NumberFormatException: For input string: "2". The documentation writes the
 * list as X,Y,Z for exactly this reason. */

#include "/lib/body/water.fsh"
