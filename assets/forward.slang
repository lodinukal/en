#define DRAW_INDIRECT
#include "common.slangh"

struct VertexStageOutput
{
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint material_id : MATERIAL;
    nointerpolation uint instance_id : INSTANCE;
    float4 sv_position : SV_POSITION;
};

struct Vertex
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
};

[vk::push_constant]
cbuffer C
{
    column_major float4x4 view;
    column_major float4x4 projection;
}

StructuredBuffer<Material> materials : register(t0, space1);

SamplerState sampler : register(s0, space2);
Texture2D textures[] : register(t1, space2);

StructuredBuffer<Instance> instances : register(t0, space3);

[shader("vertex")]
VertexStageOutput vs_main(Vertex input, DECLARE_DRAW_PARAMETERS)
{
    Instance instance = instances[INSTANCE_ID];

    float4x4 world = instance.transform;
    world = mul(mul(projection, view), world);

    float4 position = float4(input.position, 1.0);
    position = mul(world, position);

    VertexStageOutput output;
    output.sv_position = position;
    output.normal = input.normal;
    output.texcoord = input.texcoord;
    output.instance_id = INSTANCE_ID;
    output.material_id = instance.material_id;

    return output;
};

[shader("fragment")]
float4 fs_main(VertexStageOutput input)
    : SV_TARGET
{
    Material material = materials[input.material_id];

    return textures[material.albedo].Sample(sampler, input.texcoord);
};
