#version 400 compatibility
// Iris's opaque Sodium terrain entry. Preserve the common caster projection,
// material exclusion and foliage displacement; other dimensions fall back to
// their own shadow program because their ProgramSets are directory-local.
#define ASTRA_SOLID_SHADOW
#include "/program/shadow.vsh"
