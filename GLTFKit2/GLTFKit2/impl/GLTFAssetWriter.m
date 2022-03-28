
#import "GLTFAssetWriter.h"

#define CGLTF_WRITE_IMPLEMENTATION
#import "cgltf_write.h"

@interface GLTFAssetWriter () {
    cgltf_data *gltf;
}
@property (class, nonatomic, readonly) dispatch_queue_t writerQueue;
@property (nonatomic, strong) GLTFAsset *asset;
@end

static dispatch_queue_t _writerQueue;

@implementation GLTFAssetWriter

+ (dispatch_queue_t)writerQueue {
    if (_writerQueue == nil) {
        _writerQueue = dispatch_queue_create("com.metalbyexample.gltfkit2.asset-writer", DISPATCH_QUEUE_CONCURRENT);
    }
    return _writerQueue;
}

+ (void)writeAsset:(GLTFAsset *)asset
             toURL:(NSURL *)url
           options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
   progressHandler:(nullable GLTFAssetURLExportProgressHandler)handler
{
    dispatch_async(self.writerQueue, ^{
        GLTFAssetWriter *writer = [[GLTFAssetWriter alloc] init];
        [writer syncSerializeAsset:asset options:options handler:^(float progress,
                                                                   GLTFAssetStatus status,
                                                                   NSData * _Nullable data,
                                                                   NSError * _Nullable error,
                                                                   BOOL * _Nonnull stop) {
            handler(progress, status, error, stop);
        }];
    });
}

+ (void)serializeAsset:(GLTFAsset *)asset
               options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
       progressHandler:(nullable GLTFAssetDataExportProgressHandler)handler
{
    dispatch_async(self.writerQueue, ^{
        GLTFAssetWriter *writer = [[GLTFAssetWriter alloc] init];
        [writer syncSerializeAsset:asset options:options handler:handler];
    });
}

- (void)syncSerializeAsset:(GLTFAsset *)asset
                   options:(NSDictionary *)options
                   handler:(GLTFAssetDataExportProgressHandler)handler
{
    cgltf_data gltf;
    cgltf_options gltfOptions;
    /*size_t outSize =*/ cgltf_write(&gltfOptions, NULL, 0, &gltf);
}

@end
