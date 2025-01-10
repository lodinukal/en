#pragma pack_matrix(column_major)
#ifdef SLANG_HLSL_ENABLE_NVAPI
#include "nvHLSLExtns.h"
#endif

#ifndef __DXC_VERSION_MAJOR
    // warning X3557: loop doesn't seem to do anything, forcing loop to unroll
    #pragma warning(disable: 3557)
#endif


#line 31 "./assets/forward.slang"
struct BaseAttributeConstants_0
{
    int base_vertex_0;
    uint base_instance_0;
};


#line 36
cbuffer BaseAttributes_0 : register(b0, space999)
{
    BaseAttributeConstants_0 BaseAttributes_0;
}

#line 62 "./assets/en.slang"
struct Object_0
{
    float4x4 transform_0;
    uint geometry_0;
    uint material_0;
};


#line 26 "./assets/forward.slang"
StructuredBuffer<Object_0 > objects_0 : register(t0, space1);


#line 20
struct SLANG_ParameterGroup_DrawData_0
{
    float4x4 view_0;
    float4x4 projection_0;
};


#line 20
cbuffer DrawData_0 : register(b0)
{
    SLANG_ParameterGroup_DrawData_0 DrawData_0;
}

#line 3
struct VertexStageOutput_0
{
    float3 normal_0 : NORMAL;
    float4 tangent_0 : TANGENT;
    float2 texcoord_0 : TEXCOORD0;
    nointerpolation uint object_id_0 : OBJECT;
    nointerpolation uint material_id_0 : MATERIAL;
    float4 sv_position_0 : SV_POSITION;
};

struct Vertex_0
{
    float3 position_0 : POSITION;
    float3 normal_1 : NORMAL;
    float2 texcoord_1 : TEXCOORD0;
};


#line 39
[shader("vertex")]VertexStageOutput_0 vs_main(Vertex_0 input_0, uint instance_id_offset_0 : SV_InstanceID)
{
    uint instance_id_0 = BaseAttributes_0.base_instance_0;
    Object_0 instance_data_0 = objects_0.Load(BaseAttributes_0.base_instance_0);

#line 49
    VertexStageOutput_0 output_0;
    output_0.sv_position_0 = mul(mul(mul(DrawData_0.projection_0, DrawData_0.view_0), instance_data_0.transform_0), float4(input_0.position_0, 1.0));
    output_0.normal_0 = input_0.normal_1;
    output_0.texcoord_0 = input_0.texcoord_1;
    output_0.object_id_0 = instance_id_0;
    output_0.material_id_0 = instance_data_0.material_0;

    return output_0;
}

