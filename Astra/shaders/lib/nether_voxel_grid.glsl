#ifndef ASTRA_NETHER_VOXEL_GRID_GLSL
#define ASTRA_NETHER_VOXEL_GRID_GLSL
// Shared coordinate / extent contract for the Nether coloured-light volume.
// Solas V3.7b voxel light architecture adapted to a bounded, same-frame volume.
// This header only centralises the constants and the address maths that capture
// (program/shadow.vsh), propagation (program/nether_light.csh) and display
// (global/dimension/nether_colored_light.glsl) previously each spelled out.
// It declares no image, sampler or uniform, so it is safe on every dimension path.
//
// Convention shared by producer and consumers:
//   volume world index = cameraRelativePosition + fract(cameraPosition)
//                        + vec3(half extent)
// Capture floors that index to an integer cell; propagation uses the integer cell
// directly with texelFetch; display sends the continuous index through the LINEAR
// sampler normalised by the size. Passing fract(cameraPosition) as a parameter
// (instead of reading cameraPosition here) keeps this header uniform-free.
//
// The size below is fixed, not a knob. These external interface literals must stay
// equal to ASTRA_NETHER_VOXEL_SIZE and cannot be derived from this header:
//   shaders.properties:
//     image.astraVoxelImage / astraLightA / astraLightB ... 64 64 64
//   program/nether_light.csh:
//     layout(local_size_x=8,local_size_y=8,local_size_z=8) and workGroups ivec3(8,8,8)
//     -> 8 * 8 = 64 texels per axis
// Changing the volume size therefore requires editing those literals too; this
// header alone does not make the volume resizable. (B4 still owns format,
// storage layout and propagation scheduling.)

#define ASTRA_NETHER_VOXEL_SIZE 64              // cells / texels per axis
#define ASTRA_NETHER_VOXEL_HALF_EXTENT 32.0     // blocks from the volume centre to a face
#define ASTRA_NETHER_VOXEL_INV_SIZE (1.0 / 64.0) // volume index -> normalised sampler coord

// Camera-relative world point -> continuous volume index (0..SIZE spans the volume).
// cameraFraction is fract(cameraPosition); the caller supplies it so this header
// needs no uniform.
vec3 astra_nether_voxel_position(vec3 cameraRelativePosition, vec3 cameraFraction) {
    return cameraRelativePosition + cameraFraction + vec3(ASTRA_NETHER_VOXEL_HALF_EXTENT);
}

// Continuous volume index -> integer capture cell. Capture writes the floor cell.
ivec3 astra_nether_voxel_cell(vec3 cameraRelativePosition, vec3 cameraFraction) {
    return ivec3(floor(astra_nether_voxel_position(cameraRelativePosition, cameraFraction)));
}

// Integer cell guard used by both the capture write and the propagation fetch.
bool astra_nether_voxel_in_bounds(ivec3 cell) {
    return all(greaterThanEqual(cell, ivec3(0)))
        && all(lessThan(cell, ivec3(ASTRA_NETHER_VOXEL_SIZE)));
}

// Distance from the continuous index to the nearest volume face, in cells. The
// display path supplies an already offset index (normal offset added by caller);
// the offset and the resulting edge threshold are not size constants.
float astra_nether_voxel_edge(vec3 voxelPosition) {
    vec3 hi = vec3(ASTRA_NETHER_VOXEL_SIZE) - voxelPosition;
    vec3 lo = voxelPosition;
    return min(min(lo.x, lo.y), min(lo.z, min(hi.x, min(hi.y, hi.z))));
}

// Continuous index -> [0,1] sampler coordinate for the LINEAR RGBA16F volume.
vec3 astra_nether_voxel_normalized(vec3 voxelPosition) {
    return voxelPosition * ASTRA_NETHER_VOXEL_INV_SIZE;
}

#endif
