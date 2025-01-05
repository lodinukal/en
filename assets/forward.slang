import en;

struct VertexStageOutput
{
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint material_id : MATERIAL;
    nointerpolation uint transform_id : INSTANCE;
    float4 sv_position : SV_POSITION;
};

struct Vertex
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
};

cbuffer DrawData : register(t0, space0)
{
    column_major float4x4 view;
    column_major float4x4 projection;
    uint material_index;
    uint transform_index;
    uint vertex_offset;
};

StructuredBuffer<Transform> transforms : register(t0, space1);
StructuredBuffer<Material> materials : register(t1, space1);
SamplerState sampler : register(s2, space1);
Texture2D textures[] : register(t3, space1);

[shader("vertex")]
VertexStageOutput vs_main(Vertex input)
{

    VertexStageOutput output;
    output.sv_position = float4(input.position, 1.0);
    output.normal = input.normal;
    output.texcoord = input.texcoord;
    output.material_id = material_index;

    // float4x4 world = transforms[transform_index].transform;
    // world = mul(mul(projection, view), world);

    // float4 position = float4(input.position, 1.0);
    // position = mul(world, position);

    // VertexStageOutput output;
    // output.sv_position = position;
    // output.normal = input.normal;
    // output.texcoord = input.texcoord;
    // output.transform_id = transform_index;
    // output.material_id = material_index;

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
