#version 330 compatibility

/* No DRAWBUFFERS line on purpose: the shadow pass is depth only and declares no colour
 * output, so Iris allocates no shadowcolour buffer for it. See lib/body/shadow.fsh. */

#include "/lib/body/shadow.fsh"
