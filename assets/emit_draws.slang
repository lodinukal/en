#include "common.slang"

[vk_push_constant]
cbuffer Constants : register(b0, space0)
{
    uint32_t instance_count;
};

StructuredBuffer<MeshInfo> meshes : register(t0, space1);
StructuredBuffer<Instance> instances : register(t0, space2);

RWBuffer<uint> cmd_buffer : register(u0, space3);
RWBuffer<uint> Readback : register(u1, space3);

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
    let cmd = IndexedIndirectCommand.build(
        mesh.index_count,
        1,
        mesh.base_index,
        mesh.vertex_offset,
        thread_id);
    SET_INDEXED_INDIRECT_ARR(cmd_buffer, draw_index, cmd);

    GroupMemoryBarrierWithGroupSync();

    if (thread_id == 0)
    {
        Readback[0] = shared_draw_count;
    }
}
