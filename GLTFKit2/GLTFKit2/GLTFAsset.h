#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <CoreGraphics/CoreGraphics.h>

#import <GLTFKit2/GLTFTypes.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const GLTFErrorDomain;

enum {
    GLTFErrorCodeDataTooShort         = 1001,
    GLTFErrorCodeUnknownFormat        = 1002,
    GLTFErrorCodeInvalidJSON          = 1003,
    GLTFErrorCodeInvalidGLTF          = 1004,
    GLTFErrorCodeInvalidOptions       = 1005,
    GLTFErrorCodeFileNotFound         = 1006,
    GLTFErrorCodeIOError              = 1007,
    GLTFErrorCodeOutOfMemory          = 1008,
    GLTFErrorCodeLegacyGLTF           = 1009,
    GLTFErrorCodeNoDataToLoad         = 1010,
    GLTFErrorCodeFailedToLoad         = 1011,
    GLTFErrorCodeUnsupportedExtension = 1012,
};

typedef NSInteger GLTFErrorCode;

extern const float LumensPerCandela;

typedef NSString *const GLTFAttributeSemantic NS_TYPED_EXTENSIBLE_ENUM;
extern GLTFAttributeSemantic GLTFAttributeSemanticPosition;
extern GLTFAttributeSemantic GLTFAttributeSemanticNormal;
extern GLTFAttributeSemantic GLTFAttributeSemanticTangent;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord0;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord1;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord2;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord3;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord4;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord5;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord6;
extern GLTFAttributeSemantic GLTFAttributeSemanticTexcoord7;
extern GLTFAttributeSemantic GLTFAttributeSemanticColor0;
extern GLTFAttributeSemantic GLTFAttributeSemanticJoints0;
extern GLTFAttributeSemantic GLTFAttributeSemanticJoints1;
extern GLTFAttributeSemantic GLTFAttributeSemanticWeights0;
extern GLTFAttributeSemantic GLTFAttributeSemanticWeights1;

typedef NSString *const GLTFAnimationPath NS_TYPED_EXTENSIBLE_ENUM;
extern GLTFAnimationPath GLTFAnimationPathTranslation;
extern GLTFAnimationPath GLTFAnimationPathRotation;
extern GLTFAnimationPath GLTFAnimationPathScale;
extern GLTFAnimationPath GLTFAnimationPathWeights;

extern float GLTFDegFromRad(float rad);
extern int GLTFBytesPerComponentForComponentType(GLTFComponentType type);
extern int GLTFComponentCountForDimension(GLTFValueDimension dim);

GLTFKIT2_EXPORT
@interface GLTFObject : NSObject

@property (nonatomic, nullable, copy) NSString *name;
@property (nonatomic, readonly) NSUUID *identifier; // Globally unique; not persisted between runs
@property (nonatomic, copy) NSDictionary<NSString *, id> *extensions;
@property (nonatomic, nullable, copy) id extras;

@end

@class GLTFAsset;

typedef NSString * GLTFAssetLoadingOption NS_STRING_ENUM;

/// This option is not currently implemented.
GLTFKIT2_EXPORT GLTFAssetLoadingOption const GLTFAssetCreateNormalsIfAbsentKey;

/// If a suitable asset directory URL is passed in the options dictionary, connected files (binary buffer files, textures, etc.)
/// will be accessed using security-scoped URLs, as required by the app sandbox model. If an asset directory URL is
/// not provided, it is assumed that the asset file is self-contained (e.g., a .glb) or that any necessary connected files are
/// accessible without security-scoped access (e.g. because they are in the app's container).
GLTFKIT2_EXPORT GLTFAssetLoadingOption const GLTFAssetAssetDirectoryURLKey;

#define GLTFAssetLoadingOptionCreateNormalsIfAbsent GLTFAssetCreateNormalsIfAbsentKey
#define GLTFAssetLoadingOptionAssetDirectoryURL     GLTFAssetAssetDirectoryURLKey

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

@class GLTFAccessor, GLTFAnimation, GLTFBuffer, GLTFBufferView, GLTFCamera, GLTFImage, GLTFLight;
@class GLTFMaterial, GLTFMaterialMapping, GLTFMaterialVariant, GLTFMesh, GLTFNode, GLTFPrimitive;
@class GLTFScene, GLTFSkin, GLTFTexture, GLTFTextureSampler;

@protocol GLTFDracoMeshDecompressor
+ (GLTFPrimitive *)newPrimitiveForCompressedBufferView:(GLTFBufferView *)bufferView
                                          attributeMap:(NSDictionary<NSString *, NSNumber *> *)attributes;
@end

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

@property (class, nonatomic, copy) NSString *dracoDecompressorClassName;
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
@property (nonatomic, copy) NSArray<GLTFLight *> *lights;
@property (nonatomic, copy) NSArray<GLTFImage *> *images;
@property (nonatomic, copy) NSArray<GLTFMaterial *> *materials;
@property (nonatomic, nullable, copy) NSArray<GLTFMaterialVariant *> *materialVariants;
@property (nonatomic, copy) NSArray<GLTFMesh *> *meshes;
@property (nonatomic, copy) NSArray<GLTFNode *> *nodes;
@property (nonatomic, copy) NSArray<GLTFTextureSampler *> *samplers;
@property (nonatomic, nullable, strong) GLTFScene *defaultScene;
@property (nonatomic, copy) NSArray<GLTFScene *> *scenes;
@property (nonatomic, copy) NSArray<GLTFSkin *> *skins;
@property (nonatomic, copy) NSArray<GLTFTexture *> *textures;

@end

@class GLTFSparseStorage;

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

@class GLTFAnimationChannel;
@class GLTFAnimationSampler;

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

/// If provided, this URL will be used to perform security-scoped access to the corresponding image file URL.
/// Without a security-scoped URL, file access may fail when the image file is not in the app's container, as
/// may happen when loading .gltf assets with connected files. Not necessary when `uri` is a data URI.
@property (nonatomic, nullable) NSURL *assetDirectoryURL;

- (instancetype)initWithURI:(NSURL *)uri NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithBufferView:(GLTFBufferView *)bufferView mimeType:(NSString *)mimeType NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCGImage:(CGImageRef)cgImage NS_DESIGNATED_INITIALIZER; // For internal use.
- (instancetype)init NS_UNAVAILABLE;

- (CGImageRef _Nullable)newCGImage;

@end

GLTFKIT2_EXPORT
@interface GLTFLight : GLTFObject

@property (nonatomic, assign) GLTFLightType type;
@property (nonatomic, assign) simd_float3 color;
@property (nonatomic, assign) float intensity;
// Point and spot light range hint
@property (nonatomic, assign) float range;
// Spot properties
@property (nonatomic, assign) float innerConeAngle;
@property (nonatomic, assign) float outerConeAngle;

- (instancetype)initWithType:(GLTFLightType)type;

@end

@class GLTFTextureParams;

GLTFKIT2_EXPORT
@interface GLTFPBRMetallicRoughnessParams : GLTFObject

@property (nonatomic, assign) simd_float4 baseColorFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *baseColorTexture;
@property (nonatomic, assign) float metallicFactor;
@property (nonatomic, assign) float roughnessFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *metallicRoughnessTexture;

@end

GLTFKIT2_EXPORT
@interface GLTFPBRSpecularGlossinessParams : GLTFObject

@property (nonatomic, assign) simd_float4 diffuseFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *diffuseTexture;
@property (nonatomic, assign) simd_float3 specularFactor;
@property (nonatomic, assign) float glossinessFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *specularGlossinessTexture;

@end

GLTFKIT2_EXPORT
@interface GLTFSpecularParams : GLTFObject

@property (nonatomic, assign) float specularFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *specularTexture;
@property (nonatomic, assign) simd_float3 specularColorFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *specularColorTexture;

@end

GLTFKIT2_EXPORT
@interface GLTFEmissiveParams : GLTFObject

@property (nonatomic, nullable, strong) GLTFTextureParams *emissiveTexture;
@property (nonatomic, assign) simd_float3 emissiveFactor;
// Introduced by the KHR_emissive_strength extension
@property (nonatomic, assign) float emissiveStrength;

@end

GLTFKIT2_EXPORT
@interface GLTFTransmissionParams : GLTFObject

@property (nonatomic, nullable, strong) GLTFTextureParams *transmissionTexture;
@property (nonatomic, assign) float transmissionFactor;

@end

GLTFKIT2_EXPORT
@interface GLTFVolumeParams : GLTFObject

@property (nonatomic, nullable) GLTFTextureParams *thicknessTexture;
@property (nonatomic, assign) float thicknessFactor;
@property (nonatomic, assign) float attenuationDistance;
@property (nonatomic, assign) simd_float3 attenuationColor;

@end

GLTFKIT2_EXPORT
@interface GLTFClearcoatParams : GLTFObject

@property (nonatomic, nullable) GLTFTextureParams *clearcoatTexture;
@property (nonatomic, nullable) GLTFTextureParams *clearcoatRoughnessTexture;
@property (nonatomic, nullable) GLTFTextureParams *clearcoatNormalTexture;
@property (nonatomic, assign) float clearcoatFactor;
@property (nonatomic, assign) float clearcoatRoughnessFactor;

@end

GLTFKIT2_EXPORT
@interface GLTFSheenParams : GLTFObject

@property (nonatomic, assign) simd_float3 sheenColorFactor;
@property (nonatomic, nullable) GLTFTextureParams *sheenColorTexture;
@property (nonatomic, assign) float sheenRoughnessFactor;
@property (nonatomic, nullable) GLTFTextureParams *sheenRoughnessTexture;

@end

GLTFKIT2_EXPORT
@interface GLTFIridescence : NSObject

@property (nonatomic, assign) float iridescenceFactor;
@property (nonatomic, nullable) GLTFTextureParams *iridescenceTexture;
@property (nonatomic, assign) float iridescenceIndexOfRefraction;
@property (nonatomic, assign) float iridescenceThicknessMinimum;
@property (nonatomic, assign) float iridescenceThicknessMaximum;
@property (nonatomic, nullable) GLTFTextureParams *iridescenceThicknessTexture;

@end

GLTFKIT2_EXPORT
@interface GLTFMaterial : GLTFObject

@property (nonatomic, nullable) GLTFPBRMetallicRoughnessParams *metallicRoughness;
@property (nonatomic, nullable) GLTFPBRSpecularGlossinessParams *specularGlossiness;
@property (nonatomic, nullable) GLTFSpecularParams *specular;
@property (nonatomic, nullable) GLTFEmissiveParams *emissive;
@property (nonatomic, nullable) GLTFTransmissionParams *transmission;
@property (nonatomic, nullable) GLTFVolumeParams *volume;
@property (nonatomic, nullable) GLTFClearcoatParams *clearcoat;
@property (nonatomic, nullable) GLTFSheenParams *sheen;
@property (nonatomic, nullable) GLTFIridescence *iridescence;
@property (nonatomic, nullable) GLTFTextureParams *normalTexture;
@property (nonatomic, nullable) GLTFTextureParams *occlusionTexture;
@property (nonatomic, nullable) NSNumber *indexOfRefraction;
@property (nonatomic, assign) GLTFAlphaMode alphaMode;
@property (nonatomic, assign) float alphaCutoff;
@property (nonatomic, assign, getter=isDoubleSided) BOOL doubleSided;
@property (nonatomic, assign, getter=isUnlit) BOOL unlit;

@end

@class GLTFPrimitive;

GLTFKIT2_EXPORT
@interface GLTFMesh : GLTFObject

@property (nonatomic, copy) NSArray<GLTFPrimitive *> *primitives;
@property (nonatomic, nullable, copy) NSArray<NSNumber *> *weights;
@property (nonatomic, nullable, copy) NSArray<NSString *> *targetNames;

- (instancetype)initWithPrimitives:(NSArray<GLTFPrimitive *> *)primitives NS_DESIGNATED_INITIALIZER;

@end

typedef NSDictionary<NSString *, GLTFAccessor *> GLTFMorphTarget;

GLTFKIT2_EXPORT
@interface GLTFPrimitive : GLTFObject

@property (nonatomic, copy) NSDictionary<NSString *, GLTFAccessor *> *attributes;
@property (nonatomic, nullable, strong) GLTFAccessor *indices;
@property (nonatomic, nullable, strong) GLTFMaterial *material;
@property (nonatomic, assign) GLTFPrimitiveType primitiveType;
@property (nonatomic, copy) NSArray<GLTFMorphTarget *> *targets;
@property (nonatomic, nullable, copy) NSArray<GLTFMaterialMapping *> *materialMappings;

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSDictionary<NSString *, GLTFAccessor *> *)attributes
                              indices:(GLTFAccessor * _Nullable)indices NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSDictionary<NSString *, GLTFAccessor *> *)attributes;

- (instancetype)init NS_UNAVAILABLE;

- (GLTFMaterial *)effectiveMaterialForVariant:(GLTFMaterialVariant *)variant;

@end

GLTFKIT2_EXPORT
@interface GLTFNode : GLTFObject

@property (nonatomic, nullable, strong) GLTFCamera *camera;
@property (nonatomic, nullable, strong) GLTFLight *light;
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
@interface GLTFTextureTransform : NSObject

@property (nonatomic, assign) simd_float2 offset;
@property (nonatomic, assign) float rotation;
@property (nonatomic, assign) simd_float2 scale;
@property (nonatomic, assign) BOOL hasTexCoord;
@property (nonatomic, assign) int texCoord;
@property (nonatomic, readonly) simd_float4x4 matrix;

@end

GLTFKIT2_EXPORT
@interface GLTFTextureParams : NSObject

@property (nonatomic, strong) GLTFTexture *texture;
@property (nonatomic, assign) NSInteger texCoord;
@property (nonatomic, assign) float scale; // occlusion map strength or normal map scale
@property (nonatomic, nullable, strong) GLTFTextureTransform *transform;
@property (nonatomic, copy) NSDictionary<NSString *, id> *extensions;
@property (nonatomic, nullable, copy) id extras;

@end

GLTFKIT2_EXPORT
@interface GLTFTexture : GLTFObject

@property (nonatomic, nullable, strong) GLTFTextureSampler *sampler;
@property (nonatomic, nullable, strong) GLTFImage *source;

- (instancetype)initWithSource:(GLTFImage * _Nullable)source NS_DESIGNATED_INITIALIZER;

@end

GLTFKIT2_EXPORT
@interface GLTFMaterialVariant : GLTFObject

- (instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

GLTFKIT2_EXPORT
@interface GLTFMaterialMapping : GLTFObject

@property (nonatomic, strong) GLTFMaterial *material;
@property (nonatomic, strong) GLTFMaterialVariant *variant;

- (instancetype)initWithMaterial:(GLTFMaterial *)material variant:(GLTFMaterialVariant *)variant NS_DESIGNATED_INITIALIZER;
- (id)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
