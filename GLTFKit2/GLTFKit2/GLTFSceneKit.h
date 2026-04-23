
#import <GLTFKit2/GLTFAsset.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString * GLTFSCNAssetOption NS_STRING_ENUM;

/// Use this option to indicate whether alpha-blended glTF materials being converted to
/// SCNMaterials should write to the depth buffer. This may improve rendering fidelity
/// for some scenes, while it may have a detrimental effect on others. Defaults to YES.
GLTFKIT2_EXPORT GLTFSCNAssetOption const GLTFSCNAlphaBlendedMaterialsWriteDepth;

extern NSString *const GLTFAssetPropertyKeyCopyright;
extern NSString *const GLTFAssetPropertyKeyGenerator;
extern NSString *const GLTFAssetPropertyKeyVersion;
extern NSString *const GLTFAssetPropertyKeyMinVersion;
extern NSString *const GLTFAssetPropertyKeyExtensionsUsed;
extern NSString *const GLTFAssetPropertyKeyExtensionsRequired;

@interface GLTFSCNAnimation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) SCNAnimationPlayer *animationPlayer;
@end

@interface SCNScene (GLTFSceneKit)
+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset;
+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset options:(NSDictionary<GLTFSCNAssetOption, id> *)options;
@end

@interface GLTFSCNSceneSource : NSObject

@property (nonatomic, nullable, readonly) SCNScene *defaultScene;
@property (nonatomic, readonly) NSArray<SCNScene *> *scenes;
@property (nonatomic, readonly) NSArray<SCNNode *> *nodes;
@property (nonatomic, readonly) NSArray<SCNLight *> *lights;
@property (nonatomic, readonly) NSArray<SCNCamera *> *cameras;
@property (nonatomic, readonly) NSArray<SCNGeometry *> *geometries;
@property (nonatomic, readonly) NSArray<SCNMaterial *> *materials;
@property (nonatomic, readonly) NSArray<GLTFSCNAnimation *> *animations;

- (instancetype)initWithAsset:(GLTFAsset *)asset;
- (instancetype)initWithAsset:(GLTFAsset *)asset options:(NSDictionary<GLTFSCNAssetOption, id> *)options;
- (instancetype)initWithAsset:(GLTFAsset *)asset applyingMaterialVariant:(GLTFMaterialVariant *)variant;

/*!
 @method propertyForKey:
 @param key The key for which to return the corresponding metadata property.
 @abstract Returns the value corresponding to the provided key, if present in the asset.
 */
- (nullable id)propertyForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
