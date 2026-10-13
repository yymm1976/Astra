#version 400 compatibility
// When prepare builds the low-frequency sky table, reflections consume it here.
// Screen clouds still run after opaque depth in the first deferred slot.
#include "/program/sky_reflection_cache.fsh"
