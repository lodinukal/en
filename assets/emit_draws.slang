#include "common.slangh"

[vk::push_constant]
cbuffer C
{
    uint instance_count;
}

StructuredBuffer<MeshInfo> meshes : register(t0, space1);

StructuredBuffer<Instance> instances : register(t0, space2);

RWStructuredBuffer<uint> cmd_buffer : register(t0, space3);
RWBuffer<uint> readback : register(t1, space3);

groupshared uint shared_draw_count;

const static uint GROUP_SIZE = 128;

[shader("compute")]
[NumThreads(GROUP_SIZE, 1, 1)]
void cs_main(uint thread_id: SV_DispatchThreadId)
{
    if (thread_id == 0)
        shared_draw_count = 0;

    if (thread_id >= instance_count)
        return;

    GroupMemoryBarrierWithGroupSync();

    uint draw_index = 0;
    InterlockedAdd(shared_draw_count, 1, draw_index);

    uint mesh_index = instances[thread_id].mesh_id;
    const MeshInfo mesh = meshes[mesh_index];
    set_indexed_indirect_arr(cmd_buffer, draw_index, mesh.index_count, 1, mesh.base_index, mesh.vertex_offset, thread_id);

    GroupMemoryBarrierWithGroupSync();

    if (thread_id == 0)
    {
        readback[0] = shared_draw_count;
    }
}
