#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 33 "assets/en.slang"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 13 "assets/forward.slang"
struct pixelInput_0
{
    float3 normal_0 [[user(NORMAL)]];
    float4 tangent_0 [[user(TANGENT)]];
    float2 texcoord_0 [[user(TEXCOORD)]];
    [[flat]] uint object_id_0 [[user(OBJECT)]];
    [[flat]] uint material_id_0 [[user(MATERIAL)]];
};


#line 3
struct VertexStageOutput_0
{
    float3 normal_1 [[user(NORMAL)]];
    float4 tangent_1 [[user(TANGENT)]];
    float2 texcoord_1 [[user(TEXCOORD0)]];
    [[flat]] uint object_id_1 [[user(OBJECT)]];
    [[flat]] uint material_id_1 [[user(MATERIAL)]];
    float4 sv_position_0;
};


#line 61
[[fragment]] pixelOutput_0 fs_main(pixelInput_0 _S1 [[stage_in]], float4 sv_position_1 [[position]])
{

#line 61
    VertexStageOutput_0 _S2 = { _S1.normal_0, _S1.tangent_0, _S1.texcoord_0, _S1.object_id_0, _S1.material_id_0, sv_position_1 };

#line 71
    pixelOutput_0 _S3 = { float4(float(_S1.object_id_0))  };

#line 71
    return _S3;
}

