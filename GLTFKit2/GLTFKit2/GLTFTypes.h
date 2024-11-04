
#import <Foundation/Foundation.h>

#define GLTFKIT2_EXPORT __attribute__((visibility("default"))) FOUNDATION_EXTERN

#if __has_include(<ktx.h>)
#define GLTF_BUILD_WITH_KTX2
#endif

typedef NS_ENUM(NSInteger, GLTFComponentType) {
    GLTFComponentTypeInvalid,
    GLTFComponentTypeByte,
    GLTFComponentTypeUnsignedByte,
    GLTFComponentTypeShort,
    GLTFComponentTypeUnsignedShort,
    GLTFComponentTypeUnsignedInt,
    GLTFComponentTypeFloat
};

typedef NS_ENUM(NSInteger, GLTFValueDimension) {
    GLTFValueDimensionInvalid,
    GLTFValueDimensionScalar,
    GLTFValueDimensionVector2,
    GLTFValueDimensionVector3,
    GLTFValueDimensionVector4,
    GLTFValueDimensionMatrix2,
    GLTFValueDimensionMatrix3,
    GLTFValueDimensionMatrix4
};

typedef NS_ENUM(NSInteger, GLTFPrimitiveType) {
    GLTFPrimitiveTypeInvalid,
    GLTFPrimitiveTypePoints,
    GLTFPrimitiveTypeLines,
    GLTFPrimitiveTypeLineLoop,
    GLTFPrimitiveTypeLineStrip,
    GLTFPrimitiveTypeTriangles,
    GLTFPrimitiveTypeTriangleStrip,
    GLTFPrimitiveTypeTriangleFan
};

typedef NS_ENUM(NSInteger, GLTFMagFilter) {
    GLTFMagFilterNearest = 0x2600,
    GLTFMagFilterLinear  = 0x2601
};

typedef NS_ENUM(NSInteger, GLTFMinMipFilter) {
    GLTFMinMipFilterNearest        = 0x2600,
    GLTFMinMipFilterLinear         = 0x2601,
    GLTFMinMipFilterNearestNearest = 0x2700,
    GLTFMinMipFilterLinearNearest  = 0x2701,
    GLTFMinMipFilterNearestLinear  = 0x2702,
    GLTFMinMipFilterLinearLinear   = 0x2703
};

typedef NS_ENUM(NSInteger, GLTFAddressMode) {
    GLTFAddressModeClampToEdge    = 0x812F,
    GLTFAddressModeMirroredRepeat = 0x8370,
    GLTFAddressModeRepeat         = 0x2901
};

typedef NS_ENUM(NSInteger, GLTFAlphaMode) {
    GLTFAlphaModeOpaque,
    GLTFAlphaModeMask,
    GLTFAlphaModeBlend
};

typedef NS_ENUM(NSInteger, GLTFInterpolationMode) {
    GLTFInterpolationModeLinear,
    GLTFInterpolationModeStep,
    GLTFInterpolationModeCubic
};

typedef NS_ENUM(NSInteger, GLTFLightType) {
    GLTFLightTypeDirectional = 1,
    GLTFLightTypePoint,
    GLTFLightTypeSpot
};
