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

public struct Primitive
{
    public uint vertex_offset;
    public uint vertex_count;
    public uint base_index;
    public uint index_count;
};

public struct Material
{
    public float4 base_color;
    public uint albedo;
    public uint normal;
    public uint metallic_roughness;
    public uint emissive;
};

public struct Transform
{
    public float4x4 transform;
};

[ForceInline]
public void set_indexed_indirect_arr<T : IRWArray<uint>>(T arr, uint index, uint index_count_per_instance, uint instance_count, uint base_index, int vertex_offset, uint base_instance)
{
    __target_switch
    {
    case hlsl:
    case dxil_lib:
        arr[index * 7 + 0] = vertex_offset;
        arr[index * 7 + 1] = base_instance;
        arr[index * 7 + 2] = index_count_per_instance;
        arr[index * 7 + 3] = instance_count;
        arr[index * 7 + 4] = base_index;
        arr[index * 7 + 5] = vertex_offset;
        arr[index * 7 + 6] = base_instance;

    default:
        arr[index * 5 + 0] = index_count_per_instance;
        arr[index * 5 + 1] = instance_count;
        arr[index * 5 + 2] = base_index;
        arr[index * 5 + 3] = vertex_offset;
        arr[index * 5 + 4] = base_instance;
    }
}
