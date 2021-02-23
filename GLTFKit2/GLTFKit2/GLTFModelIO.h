
#import <GLTFKit2/GLTFAsset.h>
#import <ModelIO/ModelIO.h>

NS_ASSUME_NONNULL_BEGIN

@interface MDLAsset (GLTFKit2)
+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset;
+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset
                   bufferAllocator:(nullable id <MDLMeshBufferAllocator>)bufferAllocator;
@end

NS_ASSUME_NONNULL_END
