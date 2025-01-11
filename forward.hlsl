#pragma pack_matrix(column_major)
#ifdef SLANG_HLSL_ENABLE_NVAPI
#include "nvHLSLExtns.h"
#endif

#ifndef __DXC_VERSION_MAJOR
    // warning X3557: loop doesn't seem to do anything, forcing loop to unroll
    #pragma warning(disable: 3557)
#endif


#line 3 "./assets/forward.slang"
struct VertexStageOutput_0
{
    float3 normal_0 : NORMAL;
    float4 tangent_0 : TANGENT;
    float2 texcoord_0 : TEXCOORD0;
    nointerpolation uint object_id_0 : OBJECT;
    nointerpolation uint material_id_0 : MATERIAL;
    float4 sv_position_0 : SV_POSITION;
};


#line 68
[shader("pixel")]float4 fs_main(VertexStageOutput_0 input_0) : SV_TARGET
{


    if(int(input_0.object_id_0) == int(2))
    {

#line 73
        return float4(1.0, 0.0, 0.0, 1.0);
    }

#line 74
    return float4(0.0, 1.0, 0.0, 1.0);
}

