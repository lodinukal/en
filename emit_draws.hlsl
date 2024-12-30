#pragma pack_matrix(column_major)
#ifdef SLANG_HLSL_ENABLE_NVAPI
#include "nvHLSLExtns.h"
#endif

#ifndef __DXC_VERSION_MAJOR
    // warning X3557: loop doesn't seem to do anything, forcing loop to unroll
    #pragma warning(disable: 3557)
#endif


#line 48 "assets/common.slangh"
struct Instance_0
{
    float4x4 transform_0;
    uint mesh_id_0;
    uint material_id_0;
};


#line 33 "./assets/forward.slang"
StructuredBuffer<Instance_0 > instances_0 : register(t0, space3);


#line 22
struct SLANG_ParameterGroup_C_0
{
    float4x4 view_0;
    float4x4 projection_0;
};


#line 22
cbuffer C_0 : register(b0)
{
    SLANG_ParameterGroup_C_0 C_0;
}

#line 4
struct VertexStageOutput_0
{
    float3 normal_0 : NORMAL;
    float4 tangent_0 : TANGENT;
    float2 texcoord_0 : TEXCOORD0;
    nointerpolation uint material_id_1 : MATERIAL;
    nointerpolation uint instance_id_0 : INSTANCE;
    float4 sv_position_0 : SV_POSITION;
};

struct Vertex_0
{
    float3 position_0 : POSITION;
    float3 normal_1 : NORMAL;
    float2 texcoord_1 : TEXCOORD0;
};


#line 36
VertexStageOutput_0 vs_main(Vertex_0 input_0, uint VERTEX_ID_OFFSET_0 : SV_VertexID, uint INSTANCE_ID_OFFSET_0 : SV_InstanceID, int BASE_VERTEX_0 : SV_StartVertexLocation, uint BASE_INSTANCE_0 : SV_StartInstanceLocation)
{

#line 74 "assets/common.slangh"
    uint _S1 = INSTANCE_ID_OFFSET_0 - BASE_INSTANCE_0;

#line 38 "./assets/forward.slang"
    Instance_0 instance_0 = instances_0.Load(_S1);

#line 46
    VertexStageOutput_0 output_0;
    output_0.sv_position_0 = mul(mul(mul(C_0.projection_0, C_0.view_0), instance_0.transform_0), float4(input_0.position_0, 1.0));
    output_0.normal_0 = input_0.normal_1;
    output_0.texcoord_0 = input_0.texcoord_1;
    output_0.instance_id_0 = _S1;
    output_0.material_id_1 = instance_0.material_id_0;

    return output_0;
}

