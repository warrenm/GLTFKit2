
#import "GLTFAssetWriter.h"

#define CGLTF_WRITE_IMPLEMENTATION
#import "cgltf_write.h"

GLTFAssetExportOption const GLTFAssetExportAsBinary = @"GLTFAssetExportAsBinary";

static void *gltf_alloc(void *user, cgltf_size size) {
    (void)user;
    return malloc(size);
}

static void gltf_free(void *user, void *ptr) {
    (void)user;
    free(ptr);
}

@interface GLTFSerializedExtension : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSData *data;

@end

@implementation GLTFSerializedExtension

- (void)copyShallowlyToCGLTFExtension:(cgltf_extension *)outExtension {
    outExtension->name = (char *)self.name.UTF8String;
    outExtension->data = (char *)self.data.bytes;
}

@end

NSData * _Nullable GLTFExtrasFromJSONObject(_Nullable id obj, NSError **outError) {
    if (obj == nil) {
        return nil;
    }

    NSError *internalError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:&internalError];

    if (outError && internalError) {
        *outError = internalError;
    }
    return data;
}

NSArray<GLTFSerializedExtension *> *_Nullable GLTFSerializeExtensions(NSDictionary *extensions, NSError **outError) {
    if (extensions.count == 0) {
        return @[];
    }

    __block NSError *internalError = nil;
    NSMutableArray *serializedExtensions = [NSMutableArray arrayWithCapacity:extensions.count];
    [extensions enumerateKeysAndObjectsUsingBlock:^(NSString *key, id extensionObject, BOOL *stop) {
        GLTFSerializedExtension *serializedExtension = [GLTFSerializedExtension new];
        serializedExtension.name = key;
        NSData *data = [NSJSONSerialization dataWithJSONObject:extensionObject 
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&internalError];
        serializedExtension.data = data;
        if (serializedExtension.name && serializedExtension.data) {
            [serializedExtensions addObject:serializedExtension];
        } else {
            *stop = YES;
        }
    }];

    if (outError && internalError) {
        *outError = internalError;
    }
    return serializedExtensions;
}

@interface GLTFAssetWriter ()
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
    NSError *internalError = nil;

    cgltf_memory_options memory = { gltf_alloc, gltf_free, NULL };

    cgltf_data *gltf = calloc(1, sizeof(cgltf_data));
    gltf->memory = memory;

    if (asset.copyright) {
        gltf->asset.copyright = strdup(asset.copyright.UTF8String);
    }
    gltf->asset.generator = strdup("GLTFKit2 v0.6 (based on cgltf v1.13)");
    gltf->asset.version = strdup("2.0");
    gltf->asset.min_version = NULL;
    // TODO: Handle extensions, extras

    //buffers
    //bufferViews
    //accessors

    //cameras
    //lights

    gltf->images = calloc(asset.images.count, sizeof(cgltf_image));
    gltf->images_count = asset.images.count;
    for (size_t i = 0; i < asset.images.count; ++i) {
        GLTFImage *image = asset.images[i];
        cgltf_image *gltfImage = gltf->images + i;
        if (image.name) {
            gltfImage->name = strdup(image.name.UTF8String);
        }
        if (image.uri) {
            gltfImage->uri = strdup(image.uri.lastPathComponent.UTF8String);
        }
        if (image.bufferView) {
            NSInteger bufferViewIndex = [asset.bufferViews indexOfObject:image.bufferView];
            if (bufferViewIndex != NSNotFound) {
                gltfImage->buffer_view = gltf->buffer_views + bufferViewIndex;
            }
        }
        if (image.mimeType) {
            gltfImage->mime_type = strdup(image.mimeType.UTF8String);
        }
        //gltfImage->extras
        //gltfImage->extensions_count
        //gltfImage->extensions
    }
    gltf->samplers = calloc(asset.samplers.count, sizeof(cgltf_sampler));
    gltf->samplers_count = asset.samplers.count;
    for (size_t i = 0; i < asset.samplers.count; ++i) {
        GLTFTextureSampler *sampler = asset.samplers[i];
        cgltf_sampler *gltfSampler = gltf->samplers + i;
        if (sampler.name) {
            gltfSampler->name = strdup(sampler.name.UTF8String);
        }
        gltfSampler->mag_filter = (cgltf_int)sampler.magFilter;
        gltfSampler->min_filter = (cgltf_int)sampler.minMipFilter;
        gltfSampler->wrap_s = (cgltf_int)sampler.wrapS;
        gltfSampler->wrap_t = (cgltf_int)sampler.wrapT;
        //gltfSampler->extras
        //gltfSampler->extensions_count
        //gltfSampler->extensions
    }
    gltf->textures = calloc(asset.textures.count, sizeof(cgltf_texture));
    gltf->textures_count = asset.textures.count;
    for (size_t i = 0; i < asset.textures.count; ++i) {
        GLTFTexture *texture = asset.textures[i];
        cgltf_texture *gltfTexture = gltf->textures + i;
        if (texture.name) {
            gltfTexture->name = strdup(texture.name.UTF8String);
        }
        if (texture.source) {
            NSInteger sourceIndex = [asset.images indexOfObject:texture.source];
            if (sourceIndex != NSNotFound) {
                gltfTexture->image = gltf->images + sourceIndex;
            }
        }
        if (texture.sampler) {
            NSInteger samplerIndex = [asset.samplers indexOfObject:texture.sampler];
            if (samplerIndex != NSNotFound) {
                gltfTexture->sampler = gltf->samplers + samplerIndex;
            }
        }
        //gltfTexture->has_basisu
        //gltfTexture->basisu_image
        //gltfTexture->extras
        //gltfTexture->extensions_count
        //gltfTexture->extensions
    }

    //materials

    //meshes

    //TODO: skins
    //TODO: animations

    gltf->nodes = calloc(asset.nodes.count, sizeof(cgltf_node));
    gltf->nodes_count = asset.nodes.count;
    for (size_t i = 0; i < asset.nodes.count; ++i) {
        GLTFNode *node = asset.nodes[i];
        cgltf_node *gltfNode = gltf->nodes + i;
        if (node.name) {
            gltfNode->name = strdup(node.name.UTF8String);
        }
        if (node.parentNode) {
            NSInteger parentIndex = [asset.nodes indexOfObject:node.parentNode];
            if (parentIndex != NSNotFound) {
                gltfNode->parent = gltf->nodes + parentIndex;
            }
        }
        if (node.childNodes.count > 0) {
            gltfNode->children = calloc(node.childNodes.count, sizeof(cgltf_node *));
            gltfNode->children_count = node.childNodes.count;
            for (int j = 0; j < node.childNodes.count; ++j) {
                NSInteger childIndex = [asset.nodes indexOfObject:node.childNodes[j]];
                if (childIndex != NSNotFound) {
                    gltfNode->children[gltfNode->children_count++] = gltf->nodes + childIndex;
                }
            }
        }
        gltfNode->skin = NULL;
        gltfNode->mesh = NULL;
        gltfNode->camera = NULL;
        gltfNode->light = NULL;
        gltfNode->weights = NULL;
        gltfNode->weights_count = 0;
        gltfNode->has_translation = 0;
        gltfNode->has_rotation = 0;
        gltfNode->has_scale = 0;
        gltfNode->has_matrix = 0;
        simd_float4x4 M = node.matrix;
        // TODO: Write TRS properties instead if our transform is an animation target
        memcpy(&gltfNode->matrix[0], &M, sizeof(float) * 16);
        //gltfNode->extras
        gltfNode->has_mesh_gpu_instancing = 0;
        //gltfNode->extensions;
        //gltfNode->extensions_count;
    }
    gltf->scenes = calloc(asset.scenes.count, sizeof(cgltf_scene));
    gltf->scenes_count = asset.scenes.count;
    for (size_t i = 0; i < asset.scenes.count; ++i) {
        GLTFScene *scene = asset.scenes[i];
        cgltf_scene *gltfScene = gltf->scenes + i;
        gltfScene->name = strdup(scene.name.UTF8String);
        gltfScene->nodes = calloc(scene.nodes.count, sizeof(cgltf_node *));
        for (size_t j = 0; j < scene.nodes.count; ++j) {
            NSInteger nodeIndex = [asset.nodes indexOfObject:scene.nodes[j]];
            if (nodeIndex != NSNotFound) {
                gltfScene->nodes[gltfScene->nodes_count++] = gltf->nodes + nodeIndex;
            }
        }
        //gltfScene->extras;
        //gltfScene->extensions;
        //gltfScene->extensions_count;
    }
    if (asset.defaultScene) {
        NSInteger defaultSceneIndex = [asset.scenes indexOfObject:asset.defaultScene];
        if (defaultSceneIndex != NSNotFound) {
            gltf->scene = gltf->scenes + defaultSceneIndex;
        }
    }
    //extensions
    //TODO: variants

    cgltf_options gltfOptions;
    bzero(&gltfOptions, sizeof(cgltf_options));
    gltfOptions.type = cgltf_file_type_gltf;
    gltfOptions.memory = memory;
    //gltfOptions.file = cgltf_file_options;

    cgltf_size bufferSize = cgltf_write(&gltfOptions, NULL, 0, gltf);
    void *buffer = realloc(NULL, bufferSize);
    cgltf_size outSize = cgltf_write(&gltfOptions, (char *)buffer, bufferSize, gltf);

    // We omit the trailing NIL, since we treat the buffer as binary data, not a string
    NSData *data = [NSData dataWithBytesNoCopy:buffer length:(outSize - 1) freeWhenDone:YES];

    cgltf_free(gltf);
    gltf = NULL;

    BOOL stop = NO;
    handler(1.0, GLTFAssetStatusComplete, data, internalError, &stop);
}

@end
