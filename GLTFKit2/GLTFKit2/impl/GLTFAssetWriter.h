
#import <Foundation/Foundation.h>
#import <GLTFKit2/GLTFAsset.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString * GLTFAssetExportOption NS_STRING_ENUM;
GLTFKIT2_EXPORT GLTFAssetExportOption const GLTFAssetExportAsBinary;

#define GLTFAssetExportOptionExportAsBinary GLTFAssetExportAsBinary

typedef void (^GLTFAssetURLExportProgressHandler)(float progress, GLTFAssetStatus status,
                                                  NSError * _Nullable error, BOOL *stop);

typedef void (^GLTFAssetDataExportProgressHandler)(float progress, GLTFAssetStatus status,
                                                   NSData * _Nullable data, NSError * _Nullable error, BOOL *stop);

@interface GLTFAssetWriter : NSObject

+ (void)writeAsset:(GLTFAsset *)asset
             toURL:(NSURL *)url
           options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
   progressHandler:(nullable GLTFAssetURLExportProgressHandler)progressHandler;

+ (void)serializeAsset:(GLTFAsset *)asset
               options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
       progressHandler:(nullable GLTFAssetDataExportProgressHandler)progressHandler;

@end

NS_ASSUME_NONNULL_END
