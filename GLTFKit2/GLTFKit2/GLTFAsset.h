#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

#define GLTFKIT2_EXPORT __attribute__((visibility("default"))) FOUNDATION_EXTERN

@class GLTFAccessor;
@class GLTFAnimation, GLTFAnimationChannel, GLTFAnimationSampler;
@class GLTFAsset;
@class GLTFBuffer, GLTFBufferView;
@class GLTFCamera;
@class GLTFImage;
@class GLTFMaterial;
@class GLTFMesh;
@class GLTFObject;
@class GLTFPrimitive;
@class GLTFNode;
@class GLTFScene;
@class GLTFSkin;
@class GLTFSparseStorage;
@class GLTFTexture, GLTFTextureSampler, GLTFTextureParams;

typedef NS_ENUM(NSInteger, GLTFComponentType) {
    GLTFComponentTypeInvalid,
    GLTFComponentTypeByte          = 0x1400,
    GLTFComponentTypeUnsignedByte  = 0x1401,
    GLTFComponentTypeShort         = 0x1402,
    GLTFComponentTypeUnsignedShort = 0x1403,
    GLTFComponentTypeUnsignedInt   = 0x1405,
    GLTFComponentTypeFloat         = 0x1406
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

GLTFKIT2_EXPORT
@interface GLTFObject : NSObject

@property (nonatomic, nullable, copy) NSString *name;
@property (nonatomic, copy) NSDictionary<NSString *, id> *extensions;
@property (nonatomic, nullable, copy) id extras;

@end

typedef NSString * GLTFAssetLoadingOption NS_STRING_ENUM;
GLTFKIT2_EXPORT GLTFAssetLoadingOption const GLTFAssetCreateNormalsIfAbsentKey;
GLTFKIT2_EXPORT GLTFAssetLoadingOption const GLTFAssetAssetDirectoryURLsKey;
GLTFKIT2_EXPORT GLTFAssetLoadingOption const GLTFAssetOverrideAssetURLsKey;

#define GLTFAssetLoadingOptionCreateNormalsIfAbsent GLTFAssetCreateNormalsIfAbsentKey
#define GLTFAssetLoadingOptionAssetDirectoryURLs    GLTFAssetAssetDirectoryURLsKey
#define GLTFAssetLoadingOptionOverrideAssetURLs     GLTFAssetOverrideAssetURLsKey

typedef NS_ENUM(NSInteger, GLTFAssetStatus) {
    GLTFAssetStatusError = -1,
    GLTFAssetStatusParsing = 1,
    GLTFAssetStatusValidating,
    GLTFAssetStatusProcessing,
    GLTFAssetStatusComplete
};

typedef void (^GLTFAssetLoadingHandler)(float progress, GLTFAssetStatus status, GLTFAsset * _Nullable asset,
                                        NSError * _Nullable error, BOOL *stop);

typedef BOOL (^GLTFFilterPredicate)(GLTFObject *entry, NSString *identifier, BOOL *stop);

GLTFKIT2_EXPORT
@interface GLTFAsset : GLTFObject

+ (nullable instancetype)assetWithURL:(NSURL *)url
                              options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                                error:(NSError **)error;

+ (nullable instancetype)assetWithData:(NSData *)data
                               options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                                 error:(NSError **)error;

+ (void)loadAssetWithURL:(NSURL *)url
                 options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                 handler:(nullable GLTFAssetLoadingHandler)handler;

+ (void)loadAssetWithData:(NSData *)data
                  options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                  handler:(nullable GLTFAssetLoadingHandler)handler;

@property (nonatomic, nullable) NSURL *url;
@property (nonatomic, nullable, readonly) NSData *data;
@property (nonatomic, nullable) NSString *copyright;
@property (nonatomic, nullable) NSString *generator;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, nullable, copy) NSString *minVersion;
@property (nonatomic, copy) NSArray<NSString *> *extensionsUsed;
@property (nonatomic, copy) NSArray<NSString *> *extensionsRequired;
@property (nonatomic, copy) NSArray<GLTFAccessor *> *accessors;
@property (nonatomic, copy) NSArray<GLTFAnimation *> *animations;
@property (nonatomic, copy) NSArray<GLTFBuffer *> *buffers;
@property (nonatomic, copy) NSArray<GLTFBufferView *> *bufferViews;
@property (nonatomic, copy) NSArray<GLTFCamera *> *cameras;
@property (nonatomic, copy) NSArray<GLTFImage *> *images;
@property (nonatomic, copy) NSArray<GLTFMaterial *> *materials;
@property (nonatomic, copy) NSArray<GLTFMesh *> *meshes;
@property (nonatomic, copy) NSArray<GLTFNode *> *nodes;
@property (nonatomic, copy) NSArray<GLTFTextureSampler *> *samplers;
@property (nonatomic, nullable, strong) GLTFScene *defaultScene;
@property (nonatomic, copy) NSArray<GLTFScene *> *scenes;
@property (nonatomic, copy) NSArray<GLTFSkin *> *skins;
@property (nonatomic, copy) NSArray<GLTFTexture *> *textures;

@end

/* NOTE: Lengths, offsets, and strides are *always* denominated in bytes,
         so the word "byte" is often omitted from property names. */

GLTFKIT2_EXPORT
@interface GLTFAccessor : GLTFObject

@property (nonatomic, nullable, strong) GLTFBufferView *bufferView;
@property (nonatomic, assign) NSInteger offset;
@property (nonatomic, assign) GLTFComponentType componentType;
@property (nonatomic, assign) GLTFValueDimension dimension;
@property (nonatomic, assign, getter=isNormalized) BOOL normalized;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, copy) NSArray<NSNumber *> *minValues;
@property (nonatomic, copy) NSArray<NSNumber *> *maxValues;
@property (nonatomic, nullable, strong) GLTFSparseStorage *sparse;

- (instancetype)initWithBufferView:(GLTFBufferView * _Nullable)bufferView
                            offset:(NSInteger)offset
                     componentType:(GLTFComponentType)componentType
                         dimension:(GLTFValueDimension)dimension
                             count:(NSInteger)count
                        normalized:(BOOL)normalized NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFAnimation : GLTFObject

@property (nonatomic, copy) NSArray<GLTFAnimationChannel *> *channels;
@property (nonatomic, copy) NSArray<GLTFAnimationSampler *> *samplers;

- (instancetype)initWithChannels:(NSArray<GLTFAnimationChannel *> *)channels
                        samplers:(NSArray<GLTFAnimationSampler *> *)samplers NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFAnimationTarget : GLTFObject

@property (nonatomic, copy) NSString *path;
@property (nonatomic, nullable, strong) GLTFNode *node;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFAnimationChannel : GLTFObject

@property (nonatomic, strong) GLTFAnimationSampler *sampler;
@property (nonatomic, strong) GLTFAnimationTarget *target;

- (instancetype)initWithTarget:(GLTFAnimationTarget *)target
                       sampler:(GLTFAnimationSampler *)sampler NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFAnimationSampler : GLTFObject

@property (nonatomic, strong) GLTFAccessor *input;
@property (nonatomic, strong) GLTFAccessor *output;
@property (nonatomic, assign) GLTFInterpolationMode interpolationMode;

- (instancetype)initWithInput:(GLTFAccessor *)input output:(GLTFAccessor *)output NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFBuffer : GLTFObject

@property (nonatomic, nullable) NSData *data;
@property (nonatomic, nullable) NSURL *uri;
@property (nonatomic, assign) NSInteger length;

- (instancetype)initWithLength:(NSInteger)length NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithData:(NSData *)data NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFBufferView : GLTFObject

@property (nonatomic, strong) GLTFBuffer *buffer;
@property (nonatomic, assign) NSInteger offset;
@property (nonatomic, assign) NSInteger length;
@property (nonatomic, assign) NSInteger stride;
//@property (nonatomic, assign) NSInteger target;

- (instancetype)initWithBuffer:(GLTFBuffer *)buffer
                        length:(NSInteger)length
                        offset:(NSInteger)offset
                        stride:(NSInteger)stride NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFOrthographicProjectionParams : GLTFObject

@property (nonatomic, assign) float xMag;
@property (nonatomic, assign) float yMag;

@end

GLTFKIT2_EXPORT
@interface GLTFPerspectiveProjectionParams : GLTFObject

@property (nonatomic, assign) float aspectRatio;
@property (nonatomic, assign) float yFOV;

@end

GLTFKIT2_EXPORT
@interface GLTFCamera : GLTFObject

@property (nonatomic, nullable, strong) GLTFOrthographicProjectionParams *orthographic;
@property (nonatomic, nullable, strong) GLTFPerspectiveProjectionParams *perspective;
@property (nonatomic, assign) float zNear;
@property (nonatomic, assign) float zFar;

- (instancetype)initWithOrthographicProjection:(GLTFOrthographicProjectionParams *)orthographic;
- (instancetype)initWithPerspectiveProjection:(GLTFPerspectiveProjectionParams *)perspective;

@end

GLTFKIT2_EXPORT
@interface GLTFImage : GLTFObject

@property (nonatomic, nullable) NSURL *uri;
@property (nonatomic, nullable) GLTFBufferView *bufferView;
@property (nonatomic, nullable) NSString *mimeType;

- (instancetype)initWithURI:(NSURL *)uri NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithBufferView:(GLTFBufferView *)bufferView mimeType:(NSString *)mimeType NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFPBRMetallicRoughnessParams : GLTFObject

@property (nonatomic, assign) simd_float4 baseColorFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *baseColorTexture;
@property (nonatomic, assign) float metallicFactor;
@property (nonatomic, assign) float roughnessFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *metallicRoughnessTexture;

@end

GLTFKIT2_EXPORT
@interface GLTFMaterial : GLTFObject

@property (nonatomic, nullable) GLTFPBRMetallicRoughnessParams *metallicRoughness;
@property (nonatomic, nullable) GLTFTextureParams *normalTexture;
@property (nonatomic, nullable) GLTFTextureParams *occlusionTexture;
@property (nonatomic, nullable) GLTFTextureParams *emissiveTexture;
@property (nonatomic, assign) simd_float3 emissiveFactor;
@property (nonatomic, assign) GLTFAlphaMode alphaMode;
@property (nonatomic, assign) float alphaCutoff;
@property (nonatomic, assign, getter=isDoubleSided) BOOL doubleSided;

@end

GLTFKIT2_EXPORT
@interface GLTFMesh : GLTFObject

@property (nonatomic, copy) NSArray<GLTFPrimitive *> *primitives;
@property (nonatomic, nullable, copy) NSArray<NSNumber *> *weights;

- (instancetype)initWithPrimitives:(NSArray<GLTFPrimitive *> *)primitives NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

typedef NSDictionary GLTFMorphTarget;

GLTFKIT2_EXPORT
@interface GLTFPrimitive : GLTFObject

@property (nonatomic, copy) NSDictionary<NSString *, GLTFAccessor *> *attributes;
@property (nonatomic, nullable, strong) GLTFAccessor *indices;
@property (nonatomic, nullable, strong) GLTFMaterial *material;
@property (nonatomic, assign) GLTFPrimitiveType primitiveType;
@property (nonatomic, copy) NSArray<GLTFMorphTarget *> *targets;

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSDictionary<NSString *, GLTFAccessor *> *)attributes
                              indices:(GLTFAccessor * _Nullable)indices NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSDictionary<NSString *, GLTFAccessor *> *)attributes;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFNode : GLTFObject

@property (nonatomic, nullable, strong) GLTFCamera *camera;
@property (nonatomic, copy) NSArray<GLTFNode *> *childNodes;
@property (nonatomic, weak) GLTFNode *parentNode;
@property (nonatomic, nullable, strong) GLTFSkin *skin;
@property (nonatomic, assign) simd_float4x4 matrix;
@property (nonatomic, nullable, strong) GLTFMesh *mesh;
@property (nonatomic, assign) simd_quatf rotation;
@property (nonatomic, assign) simd_float3 scale;
@property (nonatomic, assign) simd_float3 translation;
@property (nonatomic, nullable, copy) NSArray<NSNumber *> *weights;

@end

GLTFKIT2_EXPORT
@interface GLTFTextureSampler : GLTFObject

@property (nonatomic, assign) GLTFMagFilter magFilter;
@property (nonatomic, assign) GLTFMinMipFilter minMipFilter;
@property (nonatomic, assign) GLTFAddressMode wrapS;
@property (nonatomic, assign) GLTFAddressMode wrapT;

@end

GLTFKIT2_EXPORT
@interface GLTFScene : GLTFObject

@property (nonatomic, copy) NSArray<GLTFNode *> *nodes;

@end

GLTFKIT2_EXPORT
@interface GLTFSkin : GLTFObject

@property (nonatomic, nullable, strong) GLTFAccessor *inverseBindMatrices;
@property (nonatomic, nullable, strong) GLTFNode *skeleton;
@property (nonatomic, copy) NSArray<GLTFNode *> *joints;

- (instancetype)initWithJoints:(NSArray<GLTFNode *> *)joints NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFSparseStorage : GLTFObject

@property (nonatomic, strong) GLTFBufferView *values;
@property (nonatomic, assign) NSInteger valueOffset;
@property (nonatomic, strong) GLTFBufferView *indices;
@property (nonatomic, assign) NSInteger indexOffset;
@property (nonatomic, assign) GLTFComponentType indexComponentType;
@property (nonatomic, assign) NSInteger count;

- (instancetype)initWithValues:(GLTFBufferView *)values
                   valueOffset:(NSInteger)valueOffset
                       indices:(GLTFBufferView *)indices
                   indexOffset:(NSInteger)indexOffset
            indexComponentType:(GLTFComponentType)indexComponentType
                         count:(NSInteger)count NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFTextureParams : GLTFObject

@property (nonatomic, strong) GLTFTexture *texture;
@property (nonatomic, assign) NSInteger texCoord;
@property (nonatomic, assign) float scale; // occlusion map strength or normal map scale

@end

GLTFKIT2_EXPORT
@interface GLTFTexture : GLTFObject

@property (nonatomic, nullable, strong) GLTFTextureSampler *sampler;
@property (nonatomic, nullable, strong) GLTFImage *source;

- (instancetype)initWithSource:(GLTFImage * _Nullable)source NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
