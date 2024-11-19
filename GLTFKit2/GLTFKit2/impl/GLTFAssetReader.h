
#import <Foundation/Foundation.h>
#import <GLTFKit2/GLTFAsset.h>

NS_ASSUME_NONNULL_BEGIN

@interface GLTFAssetReader : NSObject

+ (void)loadAssetWithURL:(NSURL *)url
                 options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                 handler:(nullable GLTFAssetLoadingHandler)handler;

+ (void)loadAssetWithData:(NSData *)data
                  options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                  handler:(nullable GLTFAssetLoadingHandler)handler;

+ (nullable GLTFAsset *)loadAssetWithURL:(NSURL *)url
                                 options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                                   error:(NSError *_Nullable *_Nullable)error;

+ (nullable GLTFAsset *)loadAssetWithData:(NSData *)data
                                  options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                                    error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
