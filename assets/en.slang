public static const uint32_t LIGHT_MATERIAL = 2u;
public static const uint32_t WHITE_TEXTURE = 0u;
public static const uint32_t BLACK_TEXTURE = 1u;

public struct Geometry
{
    public uint vertex_offset;
    public uint vertex_count;
    public uint base_index;
    public uint index_count;
};

public struct Material
{
    public column_major float4 base_color;
    public uint albedo;
    public uint normal;
    public uint metallic_roughness;
    public uint emissive;
};

public struct Object
{
    public column_major float4x4 transform;
    public uint material;
};

public struct BaseAttributeConstants
{
    public int base_vertex;
    public uint base_instance;
};
public ConstantBuffer<BaseAttributeConstants> BaseAttributes : register(b0, space999);
static uint instance_id_offset : SV_InstanceID;
static uint vertex_id_offset : SV_VertexID;

static uint instance_id_spirv_metal : SV_StartInstanceLocation;
static uint vertex_id_spirv_metal : SV_StartVertexLocation;

[ForceInline]
public uint get_instance_id_offset()
{
    return instance_id_offset;
}

[ForceInline]
public uint get_vertex_id_offset()
{
    return vertex_id_offset;
}

[ForceInline]
public uint get_instance_id()
{
    __target_switch
    {
    case hlsl:
    case dxil_lib:
        return BaseAttributes.base_instance + instance_id_offset;
    default:
        return instance_id_spirv_metal;
    }
}

[ForceInline]
public uint get_vertex_id()
{
    __target_switch
    {
    case hlsl:
    case dxil_lib:
        return BaseAttributes.base_vertex + vertex_id_offset;
    default:
        return vertex_id_spirv_metal;
    }
}

[ForceInline]
public void set_indexed_indirect_arr(RWBuffer<uint> arr, uint index, uint index_count_per_instance, uint instance_count, uint base_index, int vertex_offset, uint base_instance, uint offset)
{
    __target_switch
    {
    case hlsl:
    case dxil_lib:
        arr[offset + index * 7 + 0] = vertex_offset;
        arr[offset + index * 7 + 1] = base_instance;
        arr[offset + index * 7 + 2] = index_count_per_instance;
        arr[offset + index * 7 + 3] = instance_count;
        arr[offset + index * 7 + 4] = base_index;
        arr[offset + index * 7 + 5] = vertex_offset;
        arr[offset + index * 7 + 6] = base_instance;

    default:
        arr[offset + index * 5 + 0] = index_count_per_instance;
        arr[offset + index * 5 + 1] = instance_count;
        arr[offset + index * 5 + 2] = base_index;
        arr[offset + index * 5 + 3] = vertex_offset;
        arr[offset + index * 5 + 4] = base_instance;
    }
}
