
#import <Foundation/Foundation.h>
#import <GLTFKit2/GLTFKit2.h>

NS_ASSUME_NONNULL_BEGIN

@interface DracoDecompressor : NSObject <GLTFDracoMeshDecompressor>

+ (GLTFPrimitive *)newPrimitiveForCompressedBufferView:(GLTFBufferView *)bufferView
                                          attributeMap:(NSDictionary<NSString *, NSNumber *> *)attributes;

@end

NS_ASSUME_NONNULL_END
