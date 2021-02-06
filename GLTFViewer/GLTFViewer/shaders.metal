
#include <metal_stdlib>
using namespace metal;

/*%begin_decls%*/
struct VertexIn {
    float4 position   [[attribute(0)]];
    //float3 normal     [[attribute(1)]];
    //float3 binormal   [[attribute(2)]];
    //float2 texCoords0 [[attribute(3)]];
    //float4 color      [[attribute(4)]];
};

struct VertexOut {
    float4 position [[position]];
    //float2 texCoords0;
};
/*%end_decls%*/

struct InstanceUniforms {
    float4x4 modelMatrix;
    float4x4 modelViewMatrix;
};

struct FrameUniforms {
    float4x4 viewProjectionMatrix;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant InstanceUniforms &instance [[buffer(16)]],
                             constant FrameUniforms &frame [[buffer(17)]])
{
    float4 modelPosition = float4(in.position.xyz, 1.0f);
    float4 clipPosition = frame.viewProjectionMatrix * instance.modelMatrix * modelPosition;
    
    VertexOut out;
    out.position = clipPosition;
    //out.texCoords0 = in.texCoords0;
    
    return out;
}

using FragmentIn = VertexOut;

fragment float4 fragment_main(FragmentIn in [[stage_in]])
{
    return float4(1.0f, 1.0f, 1.0f, 1.0f);
}
