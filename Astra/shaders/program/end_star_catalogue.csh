// Original Astra: immutable presence data, initialized by Iris setup/resize.
#define ASTRA_END_STAR_CATALOGUE_WRITE
#include "/lib/settings.glsl"
#include "/global/dimension/end_geometry.glsl"
#include "/lib/end_star_catalogue.glsl"
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
const ivec3 workGroups = ivec3(151,64,1);
layout(rgba32f) uniform image2D colorimg31;
void main() {
    ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
    if (cell.x>=1200 || cell.y>=512) return;
    vec3 row=imageLoad(colorimg31,ivec2(cell.y,0)).rgb;
    if (float(cell.x)>=row.x) return;
    int slot=int(row.z)+cell.x;
    ivec2 destination=ivec2(slot%END_STAR_CATALOGUE_WIDTH,slot/END_STAR_CATALOGUE_WIDTH);
    vec2 c=vec2(cell);
    imageStore(colorimg31,destination,vec4(end_hash2(c+401.0),end_hash2(c+1524.0)));
}
