
#import <GLTFKit2/GLTFAsset.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GLTFSCNAnimationChannel : NSObject
@property (nonatomic, strong) SCNNode *target;
@property (nonatomic, strong) SCNAnimation *animation;
@end

@interface GLTFSCNAnimation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<GLTFSCNAnimationChannel *> *channels;
@end

@interface SCNScene (GLTFSceneKit)
+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset;
@end

NS_ASSUME_NONNULL_END
