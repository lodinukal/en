public static const uint32_t LIGHT_MATERIAL = 2u;
public static const uint32_t WHITE_TEXTURE = 0u;
public static const uint32_t BLACK_TEXTURE = 1u;

public struct Globals
{
    public float2 resolution;
    public float time;
    public uint frame;
}

public struct Camera
{
    public float4 position;
    public float4x4 proj;
    public float4x4 view;
    public float4x4 inv_proj;
}

public struct Light
{
    public float3 position;
    public float radius;
    public float3 color;
}

public struct AreaLight
{
    public float3 color;
    public float intensity;
    public float3 points[4];
};

public struct BoundingSphere
{
    public float3 center;
    public float radius;
};

public struct MeshInfo
{
    public uint vertex_offset;
    public uint vertex_count;
    public uint base_index;
    public uint index_count;
};

public struct Instance
{
    public column_major float4x4 transform;
    public uint mesh_id;
    public uint material_id;
};

public struct Material
{
    public float4 base_color;
    public uint albedo;
    public uint normal;
    public uint metallic_roughness;
    public uint emissive;
};

#ifdef __spirv_version
public extern struct IndexedIndirectCommand
{
    public uint index_count_per_instance;
    public uint instance_count;
    public uint base_index;
    public int vertex_offset;
    public uint base_instance;

    public static IndexedIndirectCommand build(uint index_count_per_instance, uint instance_count, uint base_index, int vertex_offset, uint base_instance)
    {
        IndexedIndirectCommand this;
        this.index_count_per_instance = index_count_per_instance;
        this.instance_count = instance_count;
        this.base_index = base_index;
        this.vertex_offset = vertex_offset;
        this.base_instance = base_instance;
        return this;
    }
};

#define SET_INDEXED_INDIRECT_ARR(arr, index, command)      \
    arr[index * 5 + 0] = command.index_count_per_instance; \
    arr[index * 5 + 1] = command.instance_count;           \
    arr[index * 5 + 2] = command.base_index;               \
    arr[index * 5 + 3] = command.vertex_offset;            \
    arr[index * 5 + 4] = command.base_instance;

#ifdef DRAW_INDIRECT
#define DECLARE_DRAW_PARAMETERS                                                                \
    int VERTEX_ID_OFFSET : SV_VertexID,                                                        \
                           uint INSTANCE_ID_OFFSET : SV_InstanceID,                            \
                                                     int BASE_VERTEX : SV_StartVertexLocation, \
                                                                       uint BASE_INSTANCE : SV_StartInstanceLocation

#define VERTEX_ID (VERTEX_ID_OFFSET - BASE_VERTEX)
#define INSTANCE_ID (INSTANCE_ID_OFFSET - BASE_INSTANCE)
#endif
#else
public extern struct IndexedIndirectCommand
{
    public int shader_emulated_base_vertex;
    public uint shader_emulated_base_instance;
    public uint index_count_per_instance;
    public uint instance_count;
    public uint base_index;
    public int vertex_offset;
    public uint base_instance;

    public static IndexedIndirectCommand build(uint index_count_per_instance, uint instance_count, uint base_index, int vertex_offset, uint base_instance)
    {
        IndexedIndirectCommand this;
        this.shader_emulated_base_vertex = vertex_offset;
        this.shader_emulated_base_instance = base_instance;
        this.index_count_per_instance = index_count_per_instance;
        this.instance_count = instance_count;
        this.base_index = base_index;
        this.vertex_offset = vertex_offset;
        this.base_instance = base_instance;
        return this;
    }
};
public struct BaseAttributeConstants
{
    public int base_vertex;
    public uint base_instance;
};

#define SET_INDEXED_INDIRECT_ARR(arr, index, command)           \
    arr[index * 7 + 0] = command.shader_emulated_base_vertex;   \
    arr[index * 7 + 1] = command.shader_emulated_base_instance; \
    arr[index * 7 + 2] = command.index_count_per_instance;      \
    arr[index * 7 + 3] = command.instance_count;                \
    arr[index * 7 + 4] = command.base_index;                    \
    arr[index * 7 + 5] = command.vertex_offset;                 \
    arr[index * 7 + 6] = command.base_instance;

#ifdef DRAW_INDIRECT

ConstantBuffer<BaseAttributeConstants> BaseAttributes : register(b0, space999);

#define DECLARE_DRAW_PARAMETERS          \
    uint VERTEX_ID_OFFSET : SV_VertexID, \
                            uint INSTANCE_ID_OFFSET : SV_InstanceID
#define BASE_VERTEX BaseAttributes.base_vertex
#define BASE_INSTANCE BaseAttributes.base_instance
#define VERTEX_ID (VERTEX_ID_OFFSET + BaseAttributes.base_vertex)
#define INSTANCE_ID (INSTANCE_ID_OFFSET + BaseAttributes.base_instance)
#endif
#endif

public struct Vertex
{
    public float3 position : POSITION;
    public float3 normal : NORMAL;
    public float2 texcoord : TEXCOORD0;
};
