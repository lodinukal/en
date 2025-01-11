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
    float4 light_dir;
    float4 light_color;
};

StructuredBuffer<Object> objects : register(t0, space1);
StructuredBuffer<Material> materials : register(t1, space1);
SamplerState sampler : register(s2, space1);
Texture2D textures[] : register(t3, space1);

[vk_push_constant]
cbuffer SingularDispatch : register(b0, space2)
{
    Object single_object;
};

[shader("vertex")]
VertexStageOutput vs_main(Vertex input, uint instance_id_offset: SV_InstanceID)
{
    uint instance_id = BaseAttributes.base_instance + instance_id_offset;
    Object object = instance_id == 0 ? single_object : objects[instance_id - 1];
    float4x4 world = object.transform;
    world = mul(mul(projection, view), world);

    float4 position = float4(input.position, 1.0);
    position = mul(world, position);

    VertexStageOutput output;
    output.sv_position = position;
    output.normal = input.normal;
    output.texcoord = input.texcoord;
    output.object_id = instance_id;
    output.material_id = object.material;

    return output;
};

[shader("fragment")]
float4 fs_main(VertexStageOutput input)
    : SV_TARGET
{
    // return float4(1.0, 0.0, 0.0, 1.0);
    // return float(input.object_id) / 126.0;
    // return input.material_id;
    // if (input.object_id == 1 + 1)
    //     return float4(1.0, 0.0, 0.0, 1.0);
    // // return float4(0.0, 1.0, 0.0, 1.0);

    if (input.material_id == 0xFFFFFFFF)
        return float4(1.0, 0.0, 1.0, 1.0);

    Material material = materials[input.material_id];

    float4 base_color = material.base_color;
    base_color *= (material.albedo == 0xFFFFFFFF) ? 1 : textures[material.albedo].Sample(sampler, input.texcoord);

    float4 normal = float4(input.normal, 1.0);
    normal = (material.normal == 0xFFFFFFFF) ? normal : textures[material.normal].Sample(sampler, input.texcoord);

    float4 metallic_roughness = float4(0.0, 0.0, 0.0, 0.0);
    metallic_roughness = (material.metallic_roughness == 0xFFFFFFFF) ? metallic_roughness : textures[material.metallic_roughness].Sample(sampler, input.texcoord);

    float4 emissive = float4(0.0, 0.0, 0.0, 0.0);
    emissive = (material.emissive == 0xFFFFFFFF) ? emissive : textures[material.emissive].Sample(sampler, input.texcoord);

    // invert normal green channel
    normal.y = 1.0 - normal.y;

    // pbr
    float3 N = normalize(normal.xyz);
    float3 V = normalize(-input.sv_position.xyz);
    float3 L = normalize(light_dir.xyz);
    float3 H = normalize(L + V);
    float3 R = reflect(-L, N);

    float3 albedo = base_color.xyz;
    float3 F0 = albedo * 0.04 + albedo * metallic_roughness.xyz;
    float3 F = F0 + (1.0 - F0) * pow(1.0 - dot(V, H), 5.0);
    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= 1.0 - metallic_roughness.x;

    float3 irradiance = light_color.xyz;
    float3 diffuse = albedo * kD * irradiance * max(0.0, dot(N, L));
    float3 specular = F * kS * irradiance * max(0.0, dot(N, H)) * max(0.0, dot(N, L));

    float3 ambient = albedo * irradiance * 0.03;

    float3 color = diffuse + specular + ambient + emissive.xyz;

    return float4(color, 1.0);
};
