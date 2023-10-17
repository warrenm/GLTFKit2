
#import <Foundation/Foundation.h>
#import <GLTFKit2/GLTFAsset.h>

NS_ASSUME_NONNULL_BEGIN

@interface GLTFAssetWriter : NSObject

/// Writes an asset to a .gltf or .glb file at the specified file URL. Does not write companion files like .bin
/// files and textures; these are the responsibility of the caller. If the provided URL is security-scoped,
/// access to it will be wrapped in calls to `[start|stop]AccessingSecurityScopedResource`.
/// If buffers in the file are encoded as data URIs ("Embedded" gltf), they will be written into the serialized
/// asset. If the `GLTFAssetExportAsBinary` option is set to a truthy `NSNumber`, the asset will
/// be assumed to be a GLB file regardless of extension, and the resulting file will contain a GLB header
/// and the first buffer will be included as a binary buffer chunk, if it is in a compatible format. The progress
/// handler block will be called at least once; if the provided `status` value is `GLTFAssetStatusError`,
/// the error parameter will contain an error object with details about the failure. This method operates
/// asynchronously, and the queue on which the progress handler block is invoked is not specified.
+ (void)writeAsset:(GLTFAsset *)asset
             toURL:(NSURL *)url
           options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
   progressHandler:(nullable GLTFAssetURLExportProgressHandler)progressHandler;

/// Serializes an asset to its JSON representation.
/// If the `GLTFAssetExportAsBinary` option is set to a truthy `NSNumber`, the resulting data
/// will include a header that is suitable for writing for writing as a standalone .glb file. It is the
/// caller's responsibility to make sure that the asset is otherwise compatible with the requirements
/// of the GLB format (there can be a maximum of one buffer serialized into  a .glb file, and it must be
/// the first buffer in the `buffers` array if present).
/// This method does not perform file I/O under any circumstances, so any .bin files or texture files
/// must be written separately by the caller. This method operates asynchronously, and the queue on
/// which the progress handler block is invoked is not specified.
+ (void)serializeAsset:(GLTFAsset *)asset
               options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
       progressHandler:(nullable GLTFAssetDataExportProgressHandler)progressHandler;

@end

NS_ASSUME_NONNULL_END
