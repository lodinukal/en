import en;

struct VertexStageOutput
{
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
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

StructuredBuffer<Primitive> primitives : register(t0, space1);
StructuredBuffer<Material> materials : register(t1, space1);
SamplerState sampler : register(s2, space1);
Texture2D textures[] : register(t3, space1);

cbuffer InstanceData : register(b0, space2)
{
    column_major float4x4 i_transform;
    uint i_primitive;
    uint i_material;
};

[shader("vertex")]
VertexStageOutput vs_main(Vertex input)
{
    float4x4 world = i_transform;
    world = mul(mul(projection, view), world);

    float4 position = float4(input.position, 1.0);
    position = mul(world, position);

    VertexStageOutput output;
    output.sv_position = position;
    output.normal = input.normal;
    output.texcoord = input.texcoord;
    output.material_id = i_material;

    return output;
};

[shader("fragment")]
float4 fs_main(VertexStageOutput input)
    : SV_TARGET
{
    // return float4(1.0, 0.0, 0.0, 1.0);
    Material material = materials[input.material_id];
    return textures[material.albedo].Sample(sampler, input.texcoord);
};
