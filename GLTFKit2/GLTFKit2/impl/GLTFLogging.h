
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define GLTFKIT2_LOG_LEVEL 3

#if GLTFKIT2_LOG_LEVEL >= 3
#   define GLTFLogInfo NSLog
#   define GLTFLogWarning NSLog
#   define GLTFLogError NSLog
#elif GLTFKIT2_LOG_LEVEL == 2
#   define GLTFLogInfo
#   define GLTFLogWarning NSLog
#   define GLTFLogError NSLog
#elif GLTFKIT2_LOG_LEVEL == 1
#   define GLTFLogInfo
#   define GLTFLogWarning
#   define GLTFLogError NSLog
#else
#   define GLTFLogInfo NSLog
#   define GLTFLogWarning NSLog
#   define GLTFLogError NSLog
#endif

NS_ASSUME_NONNULL_END
