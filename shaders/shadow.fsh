#version 330 compatibility

/* DRAWBUFFERS:0 */

/* The colour target is written but never read: this pass exists for its depth. It is
 * declared anyway, because a gbuffers-style program with no fragment output is an
 * unusual shape to ask a loader to accept and this pack has to load. */

#include "/lib/body/shadow.fsh"
