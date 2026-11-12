#version 400 compatibility
// Iris 1.11.2 routes this entry only through the solid-terrain OFF-alpha key.
// Keep water optical records for fluid models assigned to the solid layer.
#define ASTRA_SOLID_SHADOW
#include "/program/shadow.fsh"
