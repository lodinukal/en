import en;

struct VertexStageOutput
{
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint object_id : OBJECT;
    nointerpolation uint material_id : MATERIAL;
    float4 sv_position : SV_POSITION;
};

struct Vertex
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
};

cbuffer DrawData : register(b0, space0)
{
    column_major float4x4 view;
    column_major float4x4 projection;
};

StructuredBuffer<Object> objects : register(t0, space1);
StructuredBuffer<Material> materials : register(t1, space1);
SamplerState sampler : register(s2, space1);
Texture2D textures[] : register(t3, space1);

public struct BaseAttributeConstants
{
    public int base_vertex;
    public uint base_instance;
};
ConstantBuffer<BaseAttributeConstants> BaseAttributes : register(b0, space999);

[shader("vertex")]
VertexStageOutput vs_main(Vertex input, uint instance_id_offset: SV_InstanceID)
{
    uint instance_id = BaseAttributes.base_instance;
    Object instance_data = objects[instance_id];
    float4x4 world = instance_data.transform;
    world = mul(mul(projection, view), world);

    float4 position = float4(input.position, 1.0);
    position = mul(world, position);

    VertexStageOutput output;
    output.sv_position = position;
    output.normal = input.normal;
    output.texcoord = input.texcoord;
    output.object_id = instance_id;
    output.material_id = instance_data.material;

    return output;
};

[shader("fragment")]
float4 fs_main(VertexStageOutput input)
    : SV_TARGET
{
    // return float4(1.0, 0.0, 0.0, 1.0);
    if (input.object_id == 2)
        return float4(1.0, 0.0, 0.0, 1.0);

    Material material = materials[input.material_id];
    return textures[material.albedo].Sample(sampler, input.texcoord);
};
