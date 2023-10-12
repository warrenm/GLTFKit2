
#import <GLTFKit2/GLTFAsset.h>

NS_ASSUME_NONNULL_BEGIN

@interface GLTFWorkflowHelper : NSObject

- (instancetype)initWithSpecularGlossiness:(GLTFPBRSpecularGlossinessParams *)specularGlossiness;

@property (nonatomic, readonly) simd_float4 baseColorFactor;
@property (nonatomic, nullable, readonly) GLTFTextureParams *baseColorTexture;
@property (nonatomic, readonly) float metallicFactor;
@property (nonatomic, readonly) float roughnessFactor;
@property (nonatomic, nullable, readonly) GLTFTextureParams *metallicRoughnessTexture;

@end

NS_ASSUME_NONNULL_END
