#version 330 compatibility

/* RENDERTARGETS: 0 */

/* Reads colortex0 and colortex2 and writes colortex0. Reading and writing the same
 * attachment in one pass is legal: the loader keeps two physical buffers per attachment
 * and flips them between passes, which is the layout the Iris 1.21.5 template uses.
 * Nothing here reads colortex0 after the single write at the end of main. */

#include "/lib/body/composite.fsh"
