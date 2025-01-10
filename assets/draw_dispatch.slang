import en;

[vk_push_constant]
cbuffer DispatchData : register(b0, space1)
{
    uint instance_count;
};

RWBuffer<uint> draws : register(u0, space0);
StructuredBuffer<Object> objects : register(t1, space0);
StructuredBuffer<Geometry> geometries : register(t2, space0);

groupshared uint shared_draw_count;

const static uint GROUP_SIZE = 1024;

[shader("compute")]
[NumThreads(GROUP_SIZE, 1, 1)]
void cs_main(uint3 thread_loc: SV_DispatchThreadId)
{
    uint thread_id = thread_loc.x;
    if (thread_id == 0)
        shared_draw_count = 0;

    GroupMemoryBarrierWithGroupSync();

    for (uint instance_index = thread_id.x; instance_index < instance_count; instance_index += GROUP_SIZE)
    {
        uint draw_index = 0;
        InterlockedAdd(shared_draw_count, 1, draw_index);

        uint mesh_index = objects[instance_index].geometry;
        const Geometry geometry = geometries[mesh_index];
        set_indexed_indirect_arr(
            draws,
            draw_index,
            geometry.index_count,
            1,
            geometry.base_index,
            geometry.vertex_offset,
            instance_index,
            1); // offset 1 for the readback buffer
    }

    GroupMemoryBarrierWithGroupSync();

    if (thread_id.x == 0)
        draws[0] = shared_draw_count;
}
