
#import <Foundation/Foundation.h>
#import <GLTFKit2/GLTFAsset.h>

NS_ASSUME_NONNULL_BEGIN

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
