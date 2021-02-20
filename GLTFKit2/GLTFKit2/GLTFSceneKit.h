
#import <GLTFKit2/GLTFAsset.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCNScene (GLTFSceneKit)
+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset;
@end

NS_ASSUME_NONNULL_END
