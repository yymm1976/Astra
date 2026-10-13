#version 430 compatibility
// Iris 1.11.2 dispatch inserts its host image/texture barrier BEFORE dispatch.
// A final one-invocation setup dispatch makes the preceding catalogue writes
// visible to fragment samplers. No recurring per-frame initialization dispatch.
layout(local_size_x=1, local_size_y=1, local_size_z=1) in;
const ivec3 workGroups = ivec3(1,1,1);
void main() {}
