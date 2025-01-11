#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1349 "diff.meta.slang"
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 1349
matrix<float,int(4),int(4)>  unpackStorage_0(_MatrixStorage_float4x4_ColMajornatural_0 _S1)
{

#line 1349
    return matrix<float,int(4),int(4)> (_S1.data_0[int(0)][int(0)], _S1.data_0[int(1)][int(0)], _S1.data_0[int(2)][int(0)], _S1.data_0[int(3)][int(0)], _S1.data_0[int(0)][int(1)], _S1.data_0[int(1)][int(1)], _S1.data_0[int(2)][int(1)], _S1.data_0[int(3)][int(1)], _S1.data_0[int(0)][int(2)], _S1.data_0[int(1)][int(2)], _S1.data_0[int(2)][int(2)], _S1.data_0[int(3)][int(2)], _S1.data_0[int(0)][int(3)], _S1.data_0[int(1)][int(3)], _S1.data_0[int(2)][int(3)], _S1.data_0[int(3)][int(3)]);
}


#line 42 "assets/en.slang"
struct Object_0
{
    matrix<float,int(4),int(4)>  transform_0;
    uint material_0;
};


#line 42
struct Object_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 transform_0;
    uint material_0;
};


#line 42
Object_0 unpackStorage_1(Object_natural_0 _S2)
{

#line 42
    Object_0 _S3 = { unpackStorage_0(_S2.transform_0), _S2.material_0 };

#line 42
    return _S3;
}


#line 3 "assets/forward.slang"
struct VertexStageOutput_0
{
    float3 normal_0 [[user(NORMAL)]];
    float4 tangent_0 [[user(TANGENT)]];
    float2 texcoord_0 [[user(TEXCOORD)]];
    [[flat]] uint object_id_0 [[user(OBJECT)]];
    [[flat]] uint material_id_0 [[user(MATERIAL)]];
    float4 sv_position_0 [[position]];
};


#line 3
struct vertexInput_0
{
    float3 position_0 [[attribute(0)]];
    float3 normal_1 [[attribute(1)]];
    float2 texcoord_1 [[attribute(2)]];
};


#line 3
struct SLANG_ParameterGroup_SingularDispatch_natural_0
{
    Object_natural_0 single_object_0;
};


#line 43
struct SLANG_ParameterGroup_DrawData_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 view_0;
    _MatrixStorage_float4x4_ColMajornatural_0 projection_0;
    float4 light_dir_0;
    float4 light_color_0;
};


#line 43
struct KernelContext_0
{
    SLANG_ParameterGroup_SingularDispatch_natural_0 constant* SingularDispatch_0;
    Object_natural_0 device* objects_0;
    SLANG_ParameterGroup_DrawData_natural_0 constant* DrawData_0;
    uint instance_id_spirv_metal_0;
};


#line 13
struct Vertex_0
{
    float3 position_1 [[user(POSITION)]];
    float3 normal_2 [[user(NORMAL)]];
    float2 texcoord_2 [[user(TEXCOORD0)]];
};


#line 40
[[vertex]] VertexStageOutput_0 vs_main(vertexInput_0 _S4 [[stage_in]], SLANG_ParameterGroup_SingularDispatch_natural_0 constant* SingularDispatch_1 [[buffer(0)]], Object_natural_0 device* objects_1 [[buffer(0)]], SLANG_ParameterGroup_DrawData_natural_0 constant* DrawData_1 [[buffer(0)]])
{

#line 40
    KernelContext_0 kernelContext_0;

#line 40
    (&kernelContext_0)->SingularDispatch_0 = SingularDispatch_1;

#line 40
    (&kernelContext_0)->objects_0 = objects_1;

#line 40
    (&kernelContext_0)->DrawData_0 = DrawData_1;

#line 40
    Vertex_0 _S5 = { _S4.position_0, _S4.normal_1, _S4.texcoord_1 };

    uint _S6 = (&kernelContext_0)->instance_id_spirv_metal_0;
    Object_0 object_0;

#line 43
    if(_S6 == 0U)
    {

#line 43
        object_0 = unpackStorage_1((&kernelContext_0)->SingularDispatch_0->single_object_0);

#line 43
    }
    else
    {

#line 43
        object_0 = unpackStorage_1((&kernelContext_0)->objects_0[_S6 - 1U]);

#line 43
    }

#line 43
    Object_0 _S7 = object_0;

    matrix<float,int(4),int(4)>  world_0 = (((_S7.transform_0) * ((((unpackStorage_0((&kernelContext_0)->DrawData_0->view_0)) * (unpackStorage_0((&kernelContext_0)->DrawData_0->projection_0)))))));

    float4 position_2 = float4(_S4.position_0, 1.0);
    float4 position_3 = (((position_2) * (world_0)));

    thread VertexStageOutput_0 output_0;
    (&output_0)->sv_position_0 = position_3;
    (&output_0)->normal_0 = _S4.normal_1;
    (&output_0)->texcoord_0 = _S4.texcoord_1;
    (&output_0)->object_id_0 = _S6;
    (&output_0)->material_id_0 = object_0.material_0;

    return output_0;
}

