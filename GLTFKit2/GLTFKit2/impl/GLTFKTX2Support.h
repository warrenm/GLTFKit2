
#import <GLTFKit2/GLTFTypes.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const GLTFMediaTypeKTX2;

#ifdef GLTF_BUILD_WITH_KTX2
extern id<MTLTexture> _Nullable GLTFCreateTextureFromKTX2Data(NSData *data, id<MTLDevice> device);
#endif

NS_ASSUME_NONNULL_END
