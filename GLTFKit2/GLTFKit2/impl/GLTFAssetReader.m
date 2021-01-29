
#import "GLTFAssetReader.h"

#define CGLTF_IMPLEMENTATION
#import "cgltf.h"

static NSDictionary *GLTFExtensionsFromCGLTF(cgltf_extension *extensions, size_t extensionCount) {
    return @{}; // TODO: Recursively convert to extension object
}

static GLTFComponentType GLTFComponentTypeForType(cgltf_component_type type) {
    return (GLTFComponentType)type;
}

static GLTFValueDimension GLTFDimensionForAccessorType(cgltf_type type) {
    return (GLTFValueDimension)type;
}

static NSArray *GLTFBuffersFromCGLTF(cgltf_data *const gltf) {
    NSMutableArray *buffers = [NSMutableArray arrayWithCapacity:gltf->buffers_count];
    for (int i = 0; i < gltf->buffers_count; ++i) {
        cgltf_buffer *b = gltf->buffers + i;
        GLTFBuffer *buffer = [[GLTFBuffer alloc] initWithLength:b->size];
        [buffers addObject:buffer];
    }
    return buffers;
}

static NSArray *GLTFBufferViewsFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset) {
    NSMutableArray *bufferViews = [NSMutableArray arrayWithCapacity:gltf->buffer_views_count];
    for (int i = 0; i < gltf->buffer_views_count; ++i) {
        cgltf_buffer_view *bv = gltf->buffer_views + i;
        size_t bufferIndex = bv->buffer - gltf->buffers;
        GLTFBufferView *bufferView = [[GLTFBufferView alloc] initWithBuffer:asset.buffers[bufferIndex]
                                                                     length:bv->size
                                                                     offset:bv->offset
                                                                     stride:bv->stride];
        [bufferViews addObject:bufferView];
    }
    return bufferViews;
}

static NSArray *GLTFAccessorsFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    NSMutableArray *accessors = [NSMutableArray arrayWithCapacity:gltf->accessors_count];
    for (int i = 0; i < gltf->accessors_count; ++i) {
        cgltf_accessor *a = gltf->accessors + i;
        GLTFBufferView *bufferView = nil;
        if (a->buffer_view) {
            size_t bufferViewIndex = a->buffer_view - gltf->buffer_views;
            bufferView = asset.bufferViews[bufferViewIndex];
        }
        GLTFAccessor *accessor = [[GLTFAccessor alloc] initWithBufferView:bufferView
                                                                   offset:a->offset
                                                            componentType:GLTFComponentTypeForType(a->component_type)
                                                                dimension:GLTFDimensionForAccessorType(a->type)
                                                                    count:a->count
                                                               normalized:a->normalized];
        // TODO: Convert min/max values
        // TODO: Sparse
        [accessors addObject:accessor];
    }
    return accessors;
}

static NSArray *GLTFTextureSamplersFromCGLTF(cgltf_data *const gltf)
{
    return @[];
}

static NSArray *GLTFImagesFromCGLTF(cgltf_data *const gltf)
{
    return @[];
}

static NSArray *GLTFTexturesFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static NSArray *GLTFMaterialsFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static NSArray *GLTFMeshesFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static NSArray *GLTFCamerasFromCGLTF(cgltf_data *const gltf)
{
    return @[];
}

static NSArray *GLTFNodesFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static NSArray *GLTFSkinsFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static NSArray *GLTFAnimationsFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static NSArray *GLTFScenesFromCGLTF(cgltf_data *const gltf, GLTFAsset *asset)
{
    return @[];
}

static GLTFAsset *GLTFAssetFromCGLTF(cgltf_data *const gltf) {
    GLTFAsset *asset = [GLTFAsset new];
    asset.buffers = GLTFBuffersFromCGLTF(gltf);
    asset.bufferViews = GLTFBufferViewsFromCGLTF(gltf, asset);
    asset.accessors = GLTFAccessorsFromCGLTF(gltf, asset);
    asset.samplers = GLTFTextureSamplersFromCGLTF(gltf);
    asset.images = GLTFImagesFromCGLTF(gltf);
    asset.textures = GLTFTexturesFromCGLTF(gltf, asset);
    asset.materials = GLTFMaterialsFromCGLTF(gltf, asset);
    asset.meshes = GLTFMeshesFromCGLTF(gltf, asset);
    asset.cameras = GLTFCamerasFromCGLTF(gltf);
    asset.nodes = GLTFNodesFromCGLTF(gltf, asset);
    // resolve parent-child relationships
    asset.skins = GLTFSkinsFromCGLTF(gltf, asset);
    asset.animations = GLTFAnimationsFromCGLTF(gltf, asset);
    asset.scenes = GLTFScenesFromCGLTF(gltf, asset);
    return asset;
}

@interface GLTFAssetReader ()
@property (class, nonatomic, readonly) dispatch_queue_t loaderQueue;
@end

static dispatch_queue_t _loaderQueue;

@implementation GLTFAssetReader

+ (dispatch_queue_t)loaderQueue {
    if (_loaderQueue == nil) {
        _loaderQueue = dispatch_queue_create("com.metalbyexample.gltfkit2.asset-loader", DISPATCH_QUEUE_CONCURRENT);
    }
    return _loaderQueue;
}

+ (void)loadAssetWithURL:(NSURL *)url
                 options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                 handler:(nullable GLTFAssetLoadingHandler)handler
{
    dispatch_async(self.loaderQueue, ^{
        [self _syncLoadAssetWithBaseURL:url data:nil options:options handler:handler];
    });
}

+ (void)loadAssetWithData:(NSData *)data
                  options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                  handler:(nullable GLTFAssetLoadingHandler)handler
{
    dispatch_async(self.loaderQueue, ^{
        [self _syncLoadAssetWithBaseURL:nil data:data options:options handler:handler];
    });
}

+ (void)_syncLoadAssetWithBaseURL:(NSURL * _Nullable)baseURL
                             data:(NSData * _Nullable)data
                          options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                          handler:(nullable GLTFAssetLoadingHandler)handler
{
    BOOL stop = NO;
    NSData *internalData = data ?: [NSData dataWithContentsOfURL:baseURL];
    if (internalData == nil) {
        handler(1.0, GLTFAssetStatusError, nil, nil, &stop);
        return;
    }
    
    cgltf_options parseOptions = {0};
    cgltf_data *gltf = NULL;
    cgltf_result result = cgltf_parse(&parseOptions, internalData.bytes, internalData.length, &gltf);
    
    if (result != cgltf_result_success) {
        handler(1.0, GLTFAssetStatusError, nil, nil, &stop);
    } else {
        GLTFAsset *asset = GLTFAssetFromCGLTF(gltf);
        handler(1.0, GLTFAssetStatusComplete, nil, nil, &stop);
    }
    
    cgltf_free(gltf);
}

@end
