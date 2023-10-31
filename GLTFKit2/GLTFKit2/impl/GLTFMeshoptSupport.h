
#import <Foundation/Foundation.h>
#import "GLTFTypes.h"

@class GLTFBufferView;

NS_ASSUME_NONNULL_BEGIN

GLTFKIT2_EXPORT
BOOL GLTFMeshoptDecodeBufferView(GLTFBufferView *bufferView, uint8_t *decodedData, NSError **outError);

NS_ASSUME_NONNULL_END
