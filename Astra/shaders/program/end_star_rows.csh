// Original Astra compact catalogue layout: 512 metadata entries, then each
// latitude's actual circumference count, with no empty rectangular polar rows.
#define ASTRA_END_STAR_CATALOGUE_WRITE
#include "/lib/settings.glsl"
#include "/global/dimension/end_geometry.glsl"
#include "/lib/end_star_catalogue.glsl"
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
// Each of the 64 lanes owns eight consecutive rows. Integer block prefixes
// preserve the compact offsets without re-evaluating every preceding latitude.
const ivec3 workGroups=ivec3(1,1,1);
shared int rowBlockTotals[64];
layout(rgba32f) uniform writeonly image2D colorimg31;
float end_star_columns(float row) {
    return max(floor(END_STAR_EQUATOR_CELLS
        *sin((row+0.5)*(END_PI/END_STAR_ROWS))+0.5),1.0);
}
void main() {
    int lane=int(gl_LocalInvocationID.x);
    int columns[8];
    int blockTotal=0;
    for (int i=0;i<8;++i) {
        columns[i]=int(end_star_columns(float(lane*8+i)));
        blockTotal+=columns[i];
    }
    rowBlockTotals[lane]=blockTotal;
    barrier();
    int offset=END_STAR_METADATA_COUNT;
    for (int previous=0;previous<lane;++previous)
        offset+=rowBlockTotals[previous];
    for (int i=0;i<8;++i) {
        int row=lane*8+i;
        imageStore(colorimg31,ivec2(row,0),
            vec4(float(columns[i]),end_hash(float(row)+117.0),float(offset),1.0));
        offset+=columns[i];
    }
}
