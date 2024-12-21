#define DRAW_INDIRECT
#include "common.slang"

struct VertexStageOutput
{
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint material_id : MATERIAL;
    nointerpolation uint instance_id : INSTANCE;
    float4 sv_position : SV_POSITION;
};

DECLAREC(Constants, 0)
{
    column_major float4x4 view;
    column_major float4x4 projection;
}

DECLARET(StructuredBuffer<Material>, materials, 0, 1);
DECLARES(SamplerState, sampler, 0, 2);
DECLARET(Texture2D, textures[], 1, 2);
DECLARET(StructuredBuffer<Instance>, instances, 0, 3);

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
    // input.material_id == 1
    // materials[1].albedo == 2
    // so I expect material.albedo == 2
    // and renderdoc shows albedo == 2 but shader shows albedo = 1
    // if (material.albedo == 1)
    // {
    //     return float4(1.0, 0.0, 0.0, 1.0);
    // }
    // return float4(0, material.albedo / 2.0, materials[1].albedo / 2.0, 1.0);
};
