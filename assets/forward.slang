#include "en.slang"

struct VertexStageOutput
{
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint object_id : OBJECT;
    nointerpolation uint material_id : MATERIAL;
    float4 sv_position : SV_POSITION;
    float4 position : POSITION;
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
    float4 light_color;
    float4 light_dir;
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
    float4x4 mvp = mul(mul(projection, view), world);

    float4 position = float4(input.position, 1.0);
    position = mul(mvp, position);

    VertexStageOutput output;
    output.sv_position = position;
    output.position = mul(world, float4(input.position, 1.0));
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
    if (input.material_id == 0xFFFFFFFF)
        return float4(1.0, 0.0, 1.0, 1.0);

    Material material = materials[input.material_id];

    float4 base_color = material.base_color;
    base_color *= (material.albedo == 0xFFFFFFFF) ? 1 : textures[material.albedo].Sample(sampler, input.texcoord);

    float4 normal = float4(input.normal, 1.0);
    if (material.normal != 0xFFFFFFFF)
    {
        normal *= textures[material.normal].Sample(sampler, input.texcoord);
    }

    float4 metallic_roughness = float4(0.0, 0.0, 0.0, 0.0);
    metallic_roughness = (material.metallic_roughness == 0xFFFFFFFF) ? metallic_roughness : textures[material.metallic_roughness].Sample(sampler, input.texcoord);

    float4 emissive = float4(0.0, 0.0, 0.0, 0.0);
    emissive = (material.emissive == 0xFFFFFFFF) ? emissive : textures[material.emissive].Sample(sampler, input.texcoord);

    // invert normal green channel
    normal.y = 1.0 - normal.y;

    let cam_pos = view[3].xyz;

    // pbr
    float3 N = normalize(normal.xyz);
    float3 V = normalize(cam_pos - input.position.xyz);

    float3 F0 = float3(0.04);
    F0 = lerp(F0, base_color.rgb, metallic_roughness.x);

    float3 Lo = float3(0.0);
    // should be done per light but it ok
    // for (uint i = 0; i < 2; i++)
    // {
    // float4 light_dir = light_dirs[i];
    // float4 light_color = light_colors[i];

    float3 L = normalize(light_dir.xyz - input.position.xyz);
    float3 H = normalize(V + L);

    float distance = length(light_dir.xyz - input.position.xyz);
    float attenuation = 1.0 / (distance * distance);
    float3 radiance = light_color.rgb * attenuation;

    float NDF = distribution_ggx(N, H, metallic_roughness.y);
    float G = geometry_smith(N, V, L, metallic_roughness.y);
    float3 F = fresnel_schlick(max(dot(H, V), 0.0), float3(0.04));

    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= 1.0 - metallic_roughness.x;

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    float NdotL = max(dot(N, L), 0.0);
    Lo += (kD * base_color.rgb / PI + specular) * radiance * NdotL;
    // }

    float3 ambient = float3(0.01) * base_color.rgb;
    float3 color = ambient + Lo + emissive.rgb;

    return float4(color, 1.0);
};

float3 fresnel_schlick(float cos_theta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

static const float PI = 3.14159265359;

float distribution_ggx(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float geometry_schlick_ggx(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float geometry_smith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = geometry_schlick_ggx(NdotV, roughness);
    float ggx2 = geometry_schlick_ggx(NdotL, roughness);

    return ggx1 * ggx2;
}
