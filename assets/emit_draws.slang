#include "common.slang"

DECLAREC(Constants, 0)
{
    uint instance_count;
}

DECLARET(StructuredBuffer<MeshInfo>, meshes, 0, 1);
DECLARET(StructuredBuffer<Instance>, instances, 0, 2);
DECLARET(RWBuffer<uint>, cmd_buffer, 0, 3);
DECLARET(RWBuffer<uint>, readback, 1, 3);

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
        readback[0] = shared_draw_count;
    }
}
