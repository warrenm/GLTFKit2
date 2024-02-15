
#import "GLTFAssetReader.h"
#import "GLTFMeshoptSupport.h"

#define CGLTF_IMPLEMENTATION
#import "cgltf.h"

static NSString *const GLTFExtensionEXTMeshoptCompression = @"EXT_meshopt_compression";

@interface GLTFUniqueNameGenerator : NSObject
- (NSString *)nextUniqueNameWithPrefix:(NSString *)prefix;
@end

@interface GLTFUniqueNameGenerator ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *countsForPrefixes;
@end

@interface GLTFAssetReader () {
    cgltf_data *gltf;
}
@property (class, nonatomic, readonly) dispatch_queue_t loaderQueue;
@property (nonatomic, nullable, strong) NSURL *assetURL;
@property (nonatomic, nullable, strong) NSURL *assetDirectoryURL;
@property (nonatomic, nullable, strong) NSString *lastAccessedPath;
@property (nonatomic, strong) GLTFAsset *asset;
@property (nonatomic, strong) GLTFUniqueNameGenerator *nameGenerator;
@end

@implementation GLTFUniqueNameGenerator

- (instancetype)init {
    if (self = [super init]) {
        _countsForPrefixes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)nextUniqueNameWithPrefix:(NSString *)prefix {
    NSNumber *existingCount = self.countsForPrefixes[prefix];
    if (existingCount != nil) {
        self.countsForPrefixes[prefix] = @(existingCount.integerValue + 1);
        return [NSString stringWithFormat:@"%@%@", prefix, existingCount];
    }
    self.countsForPrefixes[prefix] = @(1);
    return [NSString stringWithFormat:@"%@%d", prefix, 1];
}

@end

static NSString *_Nullable GLTFUnescapeJSONString(char *str) {
    cgltf_decode_string(str); // This function operates in-place.
    return [NSString stringWithUTF8String:str];
}

static GLTFComponentType GLTFComponentTypeForType(cgltf_component_type type) {
    return (GLTFComponentType)type;
}

static GLTFValueDimension GLTFDimensionForAccessorType(cgltf_type type) {
    return (GLTFValueDimension)type;
}

static GLTFAlphaMode GLTFAlphaModeFromMode(cgltf_alpha_mode mode) {
    return (GLTFAlphaMode)mode;
}

static GLTFPrimitiveType GLTFPrimitiveTypeFromType(cgltf_primitive_type type) {
    return (GLTFPrimitiveType)type;
}

static GLTFInterpolationMode GLTFInterpolationModeForType(cgltf_interpolation_type type) {
    return (GLTFInterpolationMode)type;
}

static NSString *GLTFTargetPathForPath(cgltf_animation_path_type path) {
    switch (path) {
        case cgltf_animation_path_type_rotation:
            return GLTFAnimationPathRotation;
        case cgltf_animation_path_type_scale:
            return GLTFAnimationPathScale;
        case cgltf_animation_path_type_translation:
            return GLTFAnimationPathTranslation;
        case cgltf_animation_path_type_weights:
            return GLTFAnimationPathWeights;
        default:
            return @"";
    }
}

static GLTFLightType GLTFLightTypeForType(cgltf_light_type type) {
    return (GLTFLightType)type;
}

static cgltf_result GLTFReadFile(const struct cgltf_memory_options *memory_options, const struct cgltf_file_options *file_options, const char *path, cgltf_size *size, void **data)
{
    void* (*memory_alloc)(void*, cgltf_size) = memory_options->alloc_func ? memory_options->alloc_func : &cgltf_default_alloc;
    void (*memory_free)(void*, void*) = memory_options->free_func ? memory_options->free_func : &cgltf_default_free;
    GLTFAssetReader *reader = (__bridge GLTFAssetReader *)file_options->user_data;

    NSString *pathString = [NSString stringWithUTF8String:path];
    reader.lastAccessedPath = pathString;
    __block NSURL *fileURL = [NSURL fileURLWithPath:pathString];

    BOOL isAccessingSecurityScoped = [fileURL startAccessingSecurityScopedResource];

    NSInputStream *fileStream = [NSInputStream inputStreamWithURL:fileURL];
    if (!fileStream) {
        return cgltf_result_file_not_found;
    }

    cgltf_size file_size = size ? *size : 0;

    if (file_size == 0) {
        NSNumber *fileSizeValue = nil;
        [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:nil];

        if (!fileSizeValue) {
            return cgltf_result_io_error;
        }

        file_size = fileSizeValue.integerValue;
    }

    uint8_t *file_data = (uint8_t *)memory_alloc(memory_options->user_data, file_size);
    if (!file_data)  {
        return cgltf_result_out_of_memory;
    }

    [fileStream open];
    if (fileStream.streamStatus != NSStreamStatusOpen) {
        memory_free(memory_options->user_data, file_data);
        return cgltf_result_io_error;
    }

    NSInteger read_size = [fileStream read:file_data maxLength:file_size];
    [fileStream close];

    if (read_size != file_size) {
        memory_free(memory_options->user_data, file_data);
        return cgltf_result_io_error;
    }

    if (size) {
        *size = file_size;
    }
    if (data) {
        *data = file_data;
    }

    if (isAccessingSecurityScoped) {
        [fileURL stopAccessingSecurityScopedResource];
    }

    return cgltf_result_success;
}

static cgltf_result GLTFReadFileSecurityScoped(const struct cgltf_memory_options *memory_options, const struct cgltf_file_options *file_options, const char *path, cgltf_size *size, void **data)
{
    GLTFAssetReader *reader = (__bridge GLTFAssetReader *)file_options->user_data;
    void* (*memory_alloc)(void*, cgltf_size) = memory_options->alloc_func ? memory_options->alloc_func : &cgltf_default_alloc;
    void (*memory_free)(void*, void*) = memory_options->free_func ? memory_options->free_func : &cgltf_default_free;

    if (reader.assetDirectoryURL == nil) {
        NSLog(@"Security-scoped access for asset directory was requested but no directory URL was provided. Falling back to ordinary file reading path...");
        return GLTFReadFile(memory_options, file_options, path, size, data);
    }

    NSString *pathString = [NSString stringWithUTF8String:path];
    reader.lastAccessedPath = pathString;

    NSURL *directoryURL = reader.assetDirectoryURL;
    BOOL isAccessingDirectorySecurityScoped = [directoryURL startAccessingSecurityScopedResource];

    __block cgltf_size file_size = size ? *size : 0;
    __block NSInteger read_size = 0;
    __block uint8_t *file_data = NULL;
    __block cgltf_result result = cgltf_result_file_not_found;

    NSURL *fileURL = nil;
    if ([pathString hasPrefix:directoryURL.path]) {
        NSString *pathSuffix = [pathString substringFromIndex:[[pathString commonPrefixWithString:directoryURL.path options:0] length] + 1];
        fileURL = [directoryURL URLByAppendingPathComponent:pathSuffix];
    }

    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    [coordinator coordinateReadingItemAtURL:fileURL options:0 error:&coordinationError byAccessor:^(NSURL *newURL) {
        NSInputStream *fileStream = [NSInputStream inputStreamWithURL:newURL];
        if (!fileStream) {
            result = cgltf_result_file_not_found; return;
        }

        if (file_size == 0) {
            NSNumber *fileSizeValue = nil;
            [newURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:nil];

            if (!fileSizeValue) {
                result = cgltf_result_io_error;
            }

            file_size = fileSizeValue.integerValue;
        }

        file_data = (uint8_t *)memory_alloc(memory_options->user_data, file_size);
        if (!file_data)  {
            result = cgltf_result_out_of_memory; return;
        }

        [fileStream open];
        if (fileStream.streamStatus != NSStreamStatusOpen) {
            result = cgltf_result_io_error; return;
        }

        read_size = [fileStream read:file_data maxLength:file_size];
        [fileStream close];
    }];

    if (isAccessingDirectorySecurityScoped) {
        [directoryURL stopAccessingSecurityScopedResource];
        isAccessingDirectorySecurityScoped = NO;
    }

    if (read_size != file_size) {
        memory_free(memory_options->user_data, file_data);
        return cgltf_result_io_error;
    }

    if (size) {
        *size = file_size;
    }
    if (data) {
        *data = file_data;
    }

    return cgltf_result_success;
}

static NSError *GLTFErrorForCGLTFStatus(cgltf_result result, NSString *_Nullable failedFilePath) {
    NSString *description = @"";
    switch (result) {
        case cgltf_result_success:
            description = @"The operation succeeded.";
            break;
        case cgltf_result_data_too_short:
            description = @"Data was too short.";
            break;
        case cgltf_result_unknown_format:
            description = @"The asset is in an unknown format.";
            break;
        case cgltf_result_invalid_json:
            description = @"The asset contains invalid JSON data.";
            break;
        case cgltf_result_invalid_gltf:
            description = @"The asset is not a valid glTF asset.";
            break;
        case cgltf_result_invalid_options:
            description = @"Invalid options were provided to the glTF parser.";
            break;
        case cgltf_result_file_not_found:
            description = [NSString stringWithFormat:@"The file at %@ could not be found",
                           failedFilePath ?: @"the provided path"];
            break;
        case cgltf_result_io_error:
            description = @"An I/O error occurred.";
            break;
        case cgltf_result_out_of_memory:
            description = @"The system is out of memory.";
            break;
        case cgltf_result_legacy_gltf:
            description = @"The asset is in an unsupported (legacy) glTF format.";
            break;
        default:
            description = @"An unknown error occurred.";
            break;
    }

    return [NSError errorWithDomain:GLTFErrorDomain code:(result + 1000) userInfo:@{
        NSLocalizedDescriptionKey : description
    }];
}

_Nullable id GLTFObjectFromExtras(char const* json, cgltf_extras extras, NSError **outError) {
    size_t length = extras.end_offset - extras.start_offset;
    if (length == 0) {
        return nil;
    }
    NSError *internalError = nil;
    NSData *jsonData = [NSData dataWithBytesNoCopy:(void *)(json + extras.start_offset)
                                            length:length
                                      freeWhenDone:NO];
    id obj = [NSJSONSerialization JSONObjectWithData:jsonData
                                             options:NSJSONReadingFragmentsAllowed
                                               error:&internalError];
    if (outError && internalError) {
        *outError = internalError;
    }
    return obj;
}

NSDictionary *GLTFConvertExtensions(cgltf_extension *extensions, size_t count, NSError **outError) {
    NSMutableDictionary *extensionsMap = [NSMutableDictionary dictionary];
    NSError *internalError = nil;
    for (int i = 0; i < count; ++i) {
        cgltf_extension *extension = extensions + i;
        if (extension->name == NULL || extension->data == NULL) {
            continue;
        }
        NSString *name = [NSString stringWithUTF8String:extension->name];
        NSData *jsonData = [NSData dataWithBytesNoCopy:extension->data length:strlen(extension->data) freeWhenDone:NO];
        id obj = [NSJSONSerialization JSONObjectWithData:jsonData
                                                 options:NSJSONReadingFragmentsAllowed
                                                   error:&internalError];
        if (obj) {
            extensionsMap[name] = obj;
        } else if (internalError != nil) {
            if (outError) {
                *outError = internalError;
            }
            break;
        }
    }
    if (outError && internalError) {
        *outError = internalError;
    }
    return extensionsMap;
}

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
        GLTFAssetReader *loader = [GLTFAssetReader new];
        [loader syncLoadAssetWithURL:url data:nil options:options handler:handler];
    });
}

+ (void)loadAssetWithData:(NSData *)data
                  options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                  handler:(nullable GLTFAssetLoadingHandler)handler
{
    dispatch_async(self.loaderQueue, ^{
        GLTFAssetReader *loader = [GLTFAssetReader new];
        [loader syncLoadAssetWithURL:nil data:data options:options handler:handler];
    });
}

- (instancetype)init {
    if (self = [super init]) {
        _nameGenerator = [GLTFUniqueNameGenerator new];
    }
    return self;
}

- (void)syncLoadAssetWithURL:(nullable NSURL *)assetURL
                        data:(nullable NSData *)data
                     options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                     handler:(nullable GLTFAssetLoadingHandler)handler
{
    self.assetURL = assetURL;
    self.assetDirectoryURL = options[GLTFAssetAssetDirectoryURLKey];

    if (assetURL) {
        self.lastAccessedPath = assetURL.path;
    }

    BOOL stop = NO;
    if (assetURL == nil && data == nil) {
        if (handler) {
            NSError *error = [NSError errorWithDomain:GLTFErrorDomain
                                                 code:GLTFErrorCodeNoDataToLoad
                                             userInfo:
                              @{ NSLocalizedDescriptionKey : @"URL and data cannot both be nil when loading asset" }];
            handler(1.0, GLTFAssetStatusError, nil, error, &stop);
        }
        return;
    }

    @try {
        NSData *internalData = data ?: [NSData dataWithContentsOfURL:assetURL];
        if (internalData == nil) {
            NSError *error = [NSError errorWithDomain:GLTFErrorDomain code:GLTFErrorCodeFailedToLoad userInfo:nil];
            handler(1.0, GLTFAssetStatusError, nil, error, &stop);
            return;
        }

        cgltf_options parseOptions = {0};
        parseOptions.file.read = self.assetDirectoryURL ? GLTFReadFileSecurityScoped : GLTFReadFile;
        parseOptions.file.user_data = (__bridge void *)self;
        cgltf_result result = cgltf_parse(&parseOptions, internalData.bytes, internalData.length, &gltf);

        if (result != cgltf_result_success) {
            NSError *error = GLTFErrorForCGLTFStatus(result, self.lastAccessedPath);
            handler(1.0, GLTFAssetStatusError, nil, error, &stop);
        } else {
            result = cgltf_load_buffers(&parseOptions, gltf, assetURL.fileSystemRepresentation);
            if (result != cgltf_result_success) {
                NSError *error = GLTFErrorForCGLTFStatus(result, self.lastAccessedPath);
                handler(1.0, GLTFAssetStatusError, nil, error, &stop);
            } else {
                NSError *error = nil;
                [self convertAsset:&error];
                if (error == nil) {
                    handler(1.0, GLTFAssetStatusComplete, self.asset, nil, &stop);
                } else {
                    handler(1.0, GLTFAssetStatusError, nil, error, &stop);
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSString *description = [NSString stringWithFormat:@"An exception occurred when loading (%@)", exception.reason];
        NSError *exceptionError = [NSError errorWithDomain:GLTFErrorDomain
                                                      code:GLTFErrorCodeFailedToLoad
                                                  userInfo:@{ NSLocalizedDescriptionKey : description }];
        handler(1.0, GLTFAssetStatusError, nil, exceptionError, &stop);
    }
    @finally {
        cgltf_free(gltf);
    }
}

- (NSArray *)convertBuffers {
    NSMutableArray *buffers = [NSMutableArray arrayWithCapacity:gltf->buffers_count];
    for (int i = 0; i < gltf->buffers_count; ++i) {
        cgltf_buffer *b = gltf->buffers + i;
        GLTFBuffer *buffer = nil;
        if (b->data) {
            buffer = [[GLTFBuffer alloc] initWithData:[NSData dataWithBytes:b->data length:b->size]];
        } else {
            buffer = [[GLTFBuffer alloc] initWithLength:b->size];
        }
        buffer.name = b->name ? GLTFUnescapeJSONString(b->name)
                              : [self.nameGenerator nextUniqueNameWithPrefix:@"Buffer"];
        buffer.extensions = GLTFConvertExtensions(b->extensions, b->extensions_count, nil);
        NSDictionary *meshoptExtension = buffer.extensions[GLTFExtensionEXTMeshoptCompression];
        if (meshoptExtension) {
            BOOL isFallback = [meshoptExtension[@"fallback"] boolValue];
            buffer.meshoptFallback = isFallback;
        }
        buffer.extras = GLTFObjectFromExtras(gltf->json, b->extras, nil);
        [buffers addObject:buffer];
    }
    return buffers;
}

- (NSArray *)convertBufferViews {
    NSMutableArray *bufferViews = [NSMutableArray arrayWithCapacity:gltf->buffer_views_count];

    // If we have meshopt-encoded buffer views, we need somewhere to write their decoded data.
    // If the buffer referenced by a buffer view is tagged as a fallback, it shouldn't have
    // a URI and we shouldn't have allocated any storage to it. Now that we are loading buffer
    // views, we allocate mutable storage for each fallback buffer so that we can write into
    // them during meshopt decompression. The extension spec requires that the buffer referenced
    // by a buffer view has a byte length large enough to hold any buffer views that reference it.
    // If a fallback buffer has pre-existing data (an unusual configuration), we ignore its contents
    // and create ad-hoc buffers for each meshopt-compressed buffer view.
    NSMutableDictionary *mutableDatasForBuffers = [NSMutableDictionary dictionary];
    for (GLTFBuffer *buffer in self.asset.buffers) {
        if (buffer.isMeshoptFallback && (buffer.data == nil)) {
            mutableDatasForBuffers[buffer.identifier] = [NSMutableData dataWithLength:buffer.length];
        }
    }

    for (int i = 0; i < gltf->buffer_views_count; ++i) {
        cgltf_buffer_view *bv = gltf->buffer_views + i;
        size_t bufferIndex = bv->buffer - gltf->buffers;
        GLTFBufferView *bufferView = [[GLTFBufferView alloc] initWithBuffer:self.asset.buffers[bufferIndex]
                                                                     length:bv->size
                                                                     offset:bv->offset
                                                                     stride:bv->stride];
        bufferView.name = bv->name ? GLTFUnescapeJSONString(bv->name)
                                   : [self.nameGenerator nextUniqueNameWithPrefix:@"BufferView"];
        bufferView.extensions = GLTFConvertExtensions(bv->extensions, bv->extensions_count, nil);
        bufferView.extras = GLTFObjectFromExtras(gltf->json, bv->extras, nil);

        if (bv->has_meshopt_compression) {
            cgltf_meshopt_compression *mo = &bv->meshopt_compression;
            size_t sourceBufferIndex = mo->buffer - gltf->buffers;
            GLTFBuffer *sourceBuffer = self.asset.buffers[sourceBufferIndex];
            GLTFMeshoptCompression *meshopt = [[GLTFMeshoptCompression alloc] initWithBuffer:sourceBuffer
                                                                                      length:mo->size
                                                                                      stride:mo->stride
                                                                                       count:mo->count
                                                                                        mode:(GLTFMeshoptCompressionMode)mo->mode];
            meshopt.offset = mo->offset;
            meshopt.filter = (GLTFMeshoptCompressionFilter)mo->filter;
            bufferView.meshoptCompression = meshopt;

            NSError *error = nil;
            NSMutableData *targetBufferData = mutableDatasForBuffers[bufferView.buffer.identifier];
            if (targetBufferData) {
                uint8_t *targetBufferViewPtr = targetBufferData.mutableBytes + bufferView.offset;
                GLTFMeshoptDecodeBufferView(bufferView, targetBufferViewPtr, &error);
            } else {
                // We don't have a fallback buffer, so we have nowhere to write our decoded data, so allocate some.
                targetBufferData = [NSMutableData dataWithLength:bufferView.length];
                GLTFMeshoptDecodeBufferView(bufferView, targetBufferData.mutableBytes, &error);

                // Create a new ad-hoc buffer to wrap the buffer view's decompressed storage and patch the buffer view
                GLTFBuffer *adhocBuffer = [[GLTFBuffer alloc] initWithData:targetBufferData];
                adhocBuffer.meshoptFallback = YES;
                bufferView.buffer = adhocBuffer;
                bufferView.offset = 0;

                self.asset.buffers = [self.asset.buffers arrayByAddingObject:adhocBuffer];
            }
        }

        [bufferViews addObject:bufferView];
    }

    // Write back any storage that was allocated to a fallback buffer now that it's
    // been populated by its referencing meshopt-compressed buffer views
    for (GLTFBuffer *buffer in self.asset.buffers) {
        if (buffer.isMeshoptFallback && buffer.data == nil) {
            buffer.data = mutableDatasForBuffers[buffer.identifier];
        }
    }

    return bufferViews;
}

- (NSArray *)convertAccessors
{
    NSMutableArray *accessors = [NSMutableArray arrayWithCapacity:gltf->accessors_count];
    for (int i = 0; i < gltf->accessors_count; ++i) {
        cgltf_accessor *a = gltf->accessors + i;
        GLTFBufferView *bufferView = nil;
        if (a->buffer_view) {
            size_t bufferViewIndex = a->buffer_view - gltf->buffer_views;
            bufferView = self.asset.bufferViews[bufferViewIndex];
        }
        GLTFAccessor *accessor = [[GLTFAccessor alloc] initWithBufferView:bufferView
                                                                   offset:a->offset
                                                            componentType:GLTFComponentTypeForType(a->component_type)
                                                                dimension:GLTFDimensionForAccessorType(a->type)
                                                                    count:a->count
                                                               normalized:a->normalized];

        size_t componentCount = GLTFComponentCountForDimension(accessor.dimension);
        if (a->has_min) {
            NSMutableArray *minArray = [NSMutableArray array];
            for (int j = 0; j < componentCount; ++j) {
                [minArray addObject:@(a->min[j])];
            }
            accessor.minValues = minArray;
        }
        if (a->has_max) {
            NSMutableArray *maxArray = [NSMutableArray array];
            for (int j = 0; j < componentCount; ++j) {
                [maxArray addObject:@(a->max[j])];
            }
            accessor.maxValues = maxArray;
        }
        if (a->is_sparse) {
            GLTFBufferView *valuesBufferView = nil;
            if (a->sparse.values_buffer_view) {
                size_t valuesBufferViewIndex = a->sparse.values_buffer_view - gltf->buffer_views;
                valuesBufferView = self.asset.bufferViews[valuesBufferViewIndex];
            }
            GLTFBufferView *indicesBufferView = nil;
            if (a->sparse.indices_buffer_view) {
                size_t indicesBufferViewIndex = a->sparse.indices_buffer_view - gltf->buffer_views;
                indicesBufferView = self.asset.bufferViews[indicesBufferViewIndex];
            }

            if (valuesBufferView) {
                GLTFSparseStorage *sparse = [[GLTFSparseStorage alloc] initWithValues:valuesBufferView
                                                                          valueOffset:a->sparse.values_byte_offset
                                                                              indices:indicesBufferView
                                                                          indexOffset:a->sparse.indices_byte_offset
                                                                   indexComponentType:GLTFComponentTypeForType(a->sparse.indices_component_type)
                                                                                count:a->sparse.count];
                accessor.sparse = sparse;
            }
        }

        accessor.name = a->name ? GLTFUnescapeJSONString(a->name)
                                : [self.nameGenerator nextUniqueNameWithPrefix:@"Accessor"];
        accessor.extensions = GLTFConvertExtensions(a->extensions, a->extensions_count, nil);
        accessor.extras = GLTFObjectFromExtras(gltf->json, a->extras, nil);
        [accessors addObject:accessor];
    }
    return accessors;
}

- (NSArray *)convertTextureSamplers
{
    NSMutableArray *textureSamplers = [NSMutableArray arrayWithCapacity:gltf->samplers_count];
    for (int i = 0; i < gltf->samplers_count; ++i) {
        cgltf_sampler *s = gltf->samplers + i;
        GLTFTextureSampler *sampler = [GLTFTextureSampler new];
        sampler.magFilter = s->mag_filter;
        sampler.minMipFilter = s->min_filter;
        sampler.wrapS = s->wrap_s;
        sampler.wrapT = s->wrap_t;
        sampler.name = s->name ? GLTFUnescapeJSONString(s->name)
                               : [self.nameGenerator nextUniqueNameWithPrefix:@"Sampler"];
        sampler.extensions = GLTFConvertExtensions(s->extensions, s->extensions_count, nil);
        sampler.extras = GLTFObjectFromExtras(gltf->json, s->extras, nil);
        [textureSamplers addObject:sampler];
    }
    return textureSamplers;
}

- (NSArray *)convertImages
{
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:gltf->images_count];
    for (int i = 0; i < gltf->images_count; ++i) {
        cgltf_image *img = gltf->images + i;
        GLTFImage *image = nil;
        if (img->buffer_view) {
            size_t bufferViewIndex = img->buffer_view - gltf->buffer_views;
            GLTFBufferView *bufferView = self.asset.bufferViews[bufferViewIndex];
            NSString *mime = [NSString stringWithUTF8String:img->mime_type ? img->mime_type : "image/image"];
            image = [[GLTFImage alloc] initWithBufferView:bufferView mimeType:mime];
        } else {
            assert(img->uri);
            if (strncmp(img->uri, "data:", 5) == 0) {
                image = [[GLTFImage alloc] initWithURI:[NSURL URLWithString:[NSString stringWithUTF8String:img->uri]]];
            } else {
                NSURL *baseURI = [self.asset.url URLByDeletingLastPathComponent];
                NSURL *imageURI = [baseURI URLByAppendingPathComponent:GLTFUnescapeJSONString(img->uri)];
                image = [[GLTFImage alloc] initWithURI:imageURI];
            }
        }
        image.name = img->name ? GLTFUnescapeJSONString(img->name)
                               : [self.nameGenerator nextUniqueNameWithPrefix:@"Image"];
        image.extensions = GLTFConvertExtensions(img->extensions, img->extensions_count, nil);
        image.extras = GLTFObjectFromExtras(gltf->json, img->extras, nil);

        // Setting this allows us to perform security-scoped access later on when lazily loading textures.
        image.assetDirectoryURL = self.assetDirectoryURL;

        [images addObject:image];
    }
    return images;
}

- (NSArray *)convertTextures
{
    NSMutableArray *textures = [NSMutableArray arrayWithCapacity:gltf->textures_count];
    for (int i = 0; i < gltf->textures_count; ++i) {
        cgltf_texture *t = gltf->textures + i;
        GLTFImage *image = nil, *basisUImage = nil;
        GLTFTextureSampler *sampler = nil;
        if (t->image) {
            size_t imageIndex = t->image - gltf->images;
            image = self.asset.images[imageIndex];
        }
        if (t->has_basisu) {
            size_t imageIndex = t->basisu_image - gltf->images;
            basisUImage = self.asset.images[imageIndex];
        }
        if (t->sampler) {
            size_t samplerIndex = t->sampler - gltf->samplers;
            sampler = self.asset.samplers[samplerIndex];
        }
        GLTFTexture *texture = [[GLTFTexture alloc] initWithSource:image basisUSource:basisUImage];
        texture.sampler = sampler;
        texture.name = t->name ? GLTFUnescapeJSONString(t->name)
                               : [self.nameGenerator nextUniqueNameWithPrefix:@"Texture"];
        texture.extensions = GLTFConvertExtensions(t->extensions, t->extensions_count, nil);
        texture.extras = GLTFObjectFromExtras(gltf->json, t->extras, nil);
        [textures addObject:texture];
    }
    return textures;
}

- (GLTFTextureParams *)textureParamsFromTextureView:(cgltf_texture_view *)tv {
    size_t textureIndex = tv->texture - gltf->textures;
    GLTFTextureParams *params = [GLTFTextureParams new];
    params.texture = self.asset.textures[textureIndex];
    params.scale = tv->scale;
    params.texCoord = tv->texcoord;
    if (tv->has_transform) {
        GLTFTextureTransform *transform = [GLTFTextureTransform new];
        transform.offset = (simd_float2){ tv->transform.offset[0], tv->transform.offset[1] };
        transform.rotation = tv->transform.rotation;
        transform.scale = (simd_float2){ tv->transform.scale[0], tv->transform.scale[1] };
        if (tv->transform.has_texcoord) {
            transform.hasTexCoord = YES;
            transform.texCoord = tv->transform.texcoord;
        }
        params.transform = transform;
    }
    return params;
}

- (NSArray *)convertMaterials
{
    NSMutableArray *materials = [NSMutableArray arrayWithCapacity:gltf->materials_count];
    for (int i = 0; i < gltf->materials_count; ++i) {
        cgltf_material *m = gltf->materials + i;
        GLTFMaterial *material = [GLTFMaterial new];
        if (m->normal_texture.texture) {
            material.normalTexture = [self textureParamsFromTextureView:&m->normal_texture];
        }
        if (m->occlusion_texture.texture) {
            material.occlusionTexture = [self textureParamsFromTextureView:&m->occlusion_texture];
        }
        material.emissive = [GLTFEmissiveParams new];
        float *emissive = m->emissive_factor;
        material.emissive.emissiveFactor = (simd_float3){ emissive[0], emissive[1], emissive[2] };
        if (m->emissive_texture.texture) {
            material.emissive.emissiveTexture = [self textureParamsFromTextureView:&m->emissive_texture];
        }
        if (m->has_emissive_strength) {
            material.emissive.emissiveStrength = m->emissive_strength.emissive_strength;
        }
        material.alphaMode = GLTFAlphaModeFromMode(m->alpha_mode);
        material.alphaCutoff = m->alpha_cutoff;
        material.doubleSided = (BOOL)m->double_sided;
        if (m->has_ior) {
            material.indexOfRefraction = @(m->ior.ior);
        }
        if (m->has_pbr_metallic_roughness) {
            GLTFPBRMetallicRoughnessParams *pbr = [GLTFPBRMetallicRoughnessParams new];
            float *baseColor = m->pbr_metallic_roughness.base_color_factor;
            pbr.baseColorFactor = (simd_float4){ baseColor[0], baseColor[1], baseColor[2], baseColor[3] };
            if (m->pbr_metallic_roughness.base_color_texture.texture) {
                pbr.baseColorTexture = [self textureParamsFromTextureView:&m->pbr_metallic_roughness.base_color_texture];
            }
            pbr.metallicFactor = m->pbr_metallic_roughness.metallic_factor;
            pbr.roughnessFactor = m->pbr_metallic_roughness.roughness_factor;
            if (m->pbr_metallic_roughness.metallic_roughness_texture.texture) {
                pbr.metallicRoughnessTexture = [self textureParamsFromTextureView:&m->pbr_metallic_roughness.metallic_roughness_texture];
            }
            material.metallicRoughness = pbr;
        } else if (m->has_pbr_specular_glossiness) {
            GLTFPBRSpecularGlossinessParams *pbr = [GLTFPBRSpecularGlossinessParams new];
            float *diffuseFactor = m->pbr_specular_glossiness.diffuse_factor;
            pbr.diffuseFactor = (simd_float4){ diffuseFactor[0], diffuseFactor[1], diffuseFactor[2], diffuseFactor[3] };
            if (m->pbr_specular_glossiness.diffuse_texture.texture) {
                pbr.diffuseTexture = [self textureParamsFromTextureView:&m->pbr_specular_glossiness.diffuse_texture];
            }
            float *specularFactor = m->pbr_specular_glossiness.specular_factor;
            pbr.specularFactor = (simd_float3){ specularFactor[0], specularFactor[1], specularFactor[2] };
            pbr.glossinessFactor = m->pbr_specular_glossiness.glossiness_factor;
            if (m->pbr_specular_glossiness.specular_glossiness_texture.texture) {
                pbr.specularGlossinessTexture = [self textureParamsFromTextureView:&m->pbr_specular_glossiness.specular_glossiness_texture];
            }
            material.specularGlossiness = pbr;
        }
        if (m->has_specular) {
            GLTFSpecularParams *specular = [GLTFSpecularParams new];
            specular.specularFactor = m->specular.specular_factor;
            if (m->specular.specular_texture.texture) {
                specular.specularTexture = [self textureParamsFromTextureView:&m->specular.specular_texture];
            }
            const cgltf_float *specularColorFactor = m->specular.specular_color_factor;
            specular.specularColorFactor = (simd_float3){ specularColorFactor[0], specularColorFactor[1], specularColorFactor[2] };
            if (m->specular.specular_color_texture.texture) {
                specular.specularColorTexture = [self textureParamsFromTextureView:&m->specular.specular_color_texture];
            }
            material.specular = specular;
        }
        if (m->has_transmission) {
            GLTFTransmissionParams *transmission = [GLTFTransmissionParams new];
            transmission.transmissionFactor = m->transmission.transmission_factor;
            if (transmission.transmissionTexture.texture) {
                transmission.transmissionTexture = [self textureParamsFromTextureView:&m->transmission.transmission_texture];
            }
            material.transmission = transmission;
        }
        if (m->has_volume) {
            GLTFVolumeParams *volume = [GLTFVolumeParams new];
            volume.thicknessFactor = m->volume.thickness_factor;
            if (m->volume.thickness_texture.texture) {
                volume.thicknessTexture = [self textureParamsFromTextureView:&m->volume.thickness_texture];
            }
            volume.attenuationDistance = m->volume.attenuation_distance;
            const float *attenuationColor = m->volume.attenuation_color;
            volume.attenuationColor = (simd_float3){ attenuationColor[0], attenuationColor[1], attenuationColor[2] };
            material.volume = volume;
        }
        if (m->has_clearcoat) {
            GLTFClearcoatParams *clearcoat = [GLTFClearcoatParams new];
            clearcoat.clearcoatFactor = m->clearcoat.clearcoat_factor;
            if (m->clearcoat.clearcoat_texture.texture) {
                clearcoat.clearcoatTexture = [self textureParamsFromTextureView:&m->clearcoat.clearcoat_texture];
            }
            clearcoat.clearcoatRoughnessFactor = m->clearcoat.clearcoat_roughness_factor;
            if (m->clearcoat.clearcoat_roughness_texture.texture) {
                clearcoat.clearcoatRoughnessTexture = [self textureParamsFromTextureView:&m->clearcoat.clearcoat_roughness_texture];
            }
            if (m->clearcoat.clearcoat_normal_texture.texture) {
                clearcoat.clearcoatNormalTexture = [self textureParamsFromTextureView:&m->clearcoat.clearcoat_normal_texture];
            }
            material.clearcoat = clearcoat;
        }
        if (m->has_sheen) {
            GLTFSheenParams *sheen = [GLTFSheenParams new];
            const cgltf_float *sheenColorFactor = m->sheen.sheen_color_factor;
            sheen.sheenColorFactor = (simd_float3){ sheenColorFactor[0], sheenColorFactor[1], sheenColorFactor[2] };
            if (m->sheen.sheen_color_texture.texture) {
                sheen.sheenColorTexture = [self textureParamsFromTextureView:&m->sheen.sheen_color_texture];
            }
            sheen.sheenRoughnessFactor = m->sheen.sheen_roughness_factor;
            if (m->sheen.sheen_roughness_texture.texture) {
                sheen.sheenRoughnessTexture = [self textureParamsFromTextureView:&m->sheen.sheen_roughness_texture];
            }
            material.sheen = sheen;
        }
        if (m->has_iridescence) {
            GLTFIridescence *iridesence = [GLTFIridescence new];
            iridesence.iridescenceFactor = m->iridescence.iridescence_factor;
            if (m->iridescence.iridescence_texture.texture) {
                iridesence.iridescenceTexture = [self textureParamsFromTextureView:&m->iridescence.iridescence_texture];
            }
            iridesence.iridescenceIndexOfRefraction = m->iridescence.iridescence_ior;
            iridesence.iridescenceThicknessMinimum = m->iridescence.iridescence_thickness_min;
            iridesence.iridescenceThicknessMaximum = m->iridescence.iridescence_thickness_max;
            if (m->iridescence.iridescence_thickness_texture.texture) {
                iridesence.iridescenceThicknessTexture = [self textureParamsFromTextureView:&m->iridescence.iridescence_thickness_texture];
            }
            material.iridescence = iridesence;
        }
        if (m->unlit) {
            material.unlit = YES;
        }
        material.name = m->name ? GLTFUnescapeJSONString(m->name)
                                : [self.nameGenerator nextUniqueNameWithPrefix:@"Material"];
        material.extensions = GLTFConvertExtensions(m->extensions, m->extensions_count, nil);
        material.extras = GLTFObjectFromExtras(gltf->json, m->extras, nil);
        [materials addObject:material];
    }
    return materials;
}

- (NSArray *)convertMaterialVariants {
    if (gltf->variants_count > 0) {
        NSMutableArray *variants = [NSMutableArray arrayWithCapacity:gltf->variants_count];
        for (int i = 0; i < gltf->variants_count; ++i) {
            cgltf_material_variant *v = gltf->variants + i;
            NSString *name = [NSString stringWithUTF8String:v->name ?: "" ];
            GLTFMaterialVariant *variant = [[GLTFMaterialVariant alloc] initWithName:name];
            variant.extras = GLTFObjectFromExtras(gltf->json, v->extras, nil);
            [variants addObject:variant];
        }
        return variants;
    }
    return nil;
}

- (NSArray *)convertMeshes
{
    NSMutableArray *meshes = [NSMutableArray arrayWithCapacity:gltf->meshes_count];
    for (int i = 0; i < gltf->meshes_count; ++i) {
        cgltf_mesh *m = gltf->meshes + i;
        GLTFMesh *mesh = [GLTFMesh new];
        NSMutableArray *primitives = [NSMutableArray array];
        for (int j = 0; j < m->primitives_count; ++j) {
            cgltf_primitive *p = m->primitives + j;
            GLTFPrimitiveType type = GLTFPrimitiveTypeFromType(p->type);
            GLTFPrimitive *dracoPrimitive = nil;
            if (p->has_draco_mesh_compression && GLTFAsset.dracoDecompressorClassName != nil) {
                Class DecompressorClass = NSClassFromString(GLTFAsset.dracoDecompressorClassName);
                cgltf_draco_mesh_compression *draco = &p->draco_mesh_compression;
                size_t bufferViewIndex = draco->buffer_view - gltf->buffer_views;
                GLTFBufferView *bufferView = self.asset.bufferViews[bufferViewIndex];
                NSMutableDictionary *dracoAttributes = [NSMutableDictionary dictionary];
                for (int k = 0; k < draco->attributes_count; ++k) {
                    cgltf_attribute *a = draco->attributes + k;
                    NSString *attrName = [NSString stringWithUTF8String:a->name];
                    NSInteger attrIndex = a->data - gltf->accessors;
                    dracoAttributes[attrName] = @(attrIndex);
                }
                dracoPrimitive = [DecompressorClass newPrimitiveForCompressedBufferView:bufferView
                                                                           attributeMap:dracoAttributes];
            }
            NSMutableArray *attributes = [NSMutableArray array];
            for (int k = 0; k < p->attributes_count; ++k) {
                cgltf_attribute *a = p->attributes + k;
                NSString *attrName = [NSString stringWithUTF8String:a->name];
                size_t attrIndex = a->data - gltf->accessors;
                GLTFAccessor *attrAccessor = self.asset.accessors[attrIndex];
                GLTFAttribute *_Nullable attribute = [dracoPrimitive attributeForName:attrName];
                if (attribute == nil) {
                    attribute = [[GLTFAttribute alloc] initWithName:attrName accessor:attrAccessor];
                }
                [attributes addObject:attribute];
            }
            GLTFPrimitive *primitive = nil;
            if (p->indices) {
                size_t accessorIndex = p->indices - gltf->accessors;
                GLTFAccessor *indices = dracoPrimitive.indices ?: self.asset.accessors[accessorIndex];
                primitive = [[GLTFPrimitive alloc] initWithPrimitiveType:type attributes:attributes indices:indices];
            } else {
                primitive = [[GLTFPrimitive alloc] initWithPrimitiveType:type attributes:attributes];
            }
            if (p->material) {
                size_t materialIndex = p->material - gltf->materials;
                primitive.material = self.asset.materials[materialIndex];
            }
            NSMutableArray<NSArray<GLTFAttribute *> *> *targets = [NSMutableArray array];
            for (int k = 0; k < p->targets_count; ++k) {
                NSMutableArray<GLTFAttribute *> *target = [NSMutableArray array];
                cgltf_morph_target *mt = p->targets + k;
                for (int l = 0; l < mt->attributes_count; ++l) {
                    cgltf_attribute *a = mt->attributes + l;
                    NSString *attrName = [NSString stringWithUTF8String:a->name];
                    size_t attrIndex = a->data - gltf->accessors;
                    GLTFAccessor *attrAccessor = self.asset.accessors[attrIndex];
                    GLTFAttribute *attr = [[GLTFAttribute alloc] initWithName:attrName accessor:attrAccessor];
                    [target addObject:attr];
                }
                [targets addObject:[target copy]];
            }
            if (p->mappings_count > 0) {
                NSMutableArray *materialMappings = [NSMutableArray arrayWithCapacity:p->mappings_count];
                for (int k = 0; k < p->mappings_count; ++k) {
                    cgltf_material_mapping *mm = p->mappings + k;
                    size_t materialIndex = mm->material - gltf->materials;
                    GLTFMaterial *material = self.asset.materials[materialIndex];
                    GLTFMaterialVariant *variant = self.asset.materialVariants[mm->variant];
                    GLTFMaterialMapping *mapping = [[GLTFMaterialMapping alloc] initWithMaterial:material variant:variant];
                    mapping.extras = GLTFObjectFromExtras(gltf->json, mm->extras, nil);
                    [materialMappings addObject:mapping];
                }
                primitive.materialMappings = materialMappings;
            }
            primitive.targets = targets;
            primitive.extras = GLTFObjectFromExtras(gltf->json, p->extras, nil);
            [primitives addObject:primitive];
        }
        NSMutableArray *weights = [NSMutableArray array];
        for (int j = 0; j < m->weights_count; ++j) {
            cgltf_float *weight = m->weights + j;
            [weights addObject:@(weight[0])];
        }
        if (weights.count > 0) {
            mesh.weights = weights;
        }
        mesh.primitives = primitives;

        NSMutableArray * targetNames = [NSMutableArray array];
        for (int j = 0; j < m->target_names_count; j++)
        {
            [targetNames addObject: [NSString stringWithUTF8String:m->target_names[j]]];
        }
        mesh.targetNames = targetNames;

        mesh.name = m->name ? GLTFUnescapeJSONString(m->name)
                            : [self.nameGenerator nextUniqueNameWithPrefix:@"Mesh"];
        mesh.extensions = GLTFConvertExtensions(m->extensions, m->extensions_count, nil);
        mesh.extras = GLTFObjectFromExtras(gltf->json, m->extras, nil);
        [meshes addObject:mesh];
    }
    return meshes;
}

- (NSArray *)convertCameras
{
    NSMutableArray *cameras = [NSMutableArray array];
    for (int i = 0; i < gltf->cameras_count; ++i) {
        cgltf_camera *c = gltf->cameras + i;
        GLTFCamera *camera = nil;
        if (c->type == cgltf_camera_type_orthographic) {
            GLTFOrthographicProjectionParams *params = [GLTFOrthographicProjectionParams new];
            params.xMag = c->data.orthographic.xmag;
            params.yMag = c->data.orthographic.ymag;
            camera = [[GLTFCamera alloc] initWithOrthographicProjection:params];
            camera.zNear = c->data.orthographic.znear;
            camera.zFar = c->data.orthographic.zfar;
        } else if (c->type == cgltf_camera_type_perspective) {
            GLTFPerspectiveProjectionParams *params = [GLTFPerspectiveProjectionParams new];
            params.yFOV = c->data.perspective.yfov;
            params.aspectRatio = c->data.perspective.aspect_ratio;
            camera = [[GLTFCamera alloc] initWithPerspectiveProjection:params];
            camera.zNear = c->data.perspective.znear;
            camera.zFar = c->data.perspective.zfar;
        } else {
            camera = [GLTFCamera new]; // Got an invalid camera, so just make a dummy to occupy the slot
        }
        camera.name = c->name ? GLTFUnescapeJSONString(c->name)
                              : [self.nameGenerator nextUniqueNameWithPrefix:@"Camera"];
        camera.extensions = GLTFConvertExtensions(c->extensions, c->extensions_count, nil);
        camera.extras = GLTFObjectFromExtras(gltf->json, c->extras, nil);
        [cameras addObject:camera];
    }
    return cameras;
}

- (NSArray *)convertLights
{
    NSMutableArray *lights = [NSMutableArray array];
    for (int i = 0; i < gltf->lights_count; ++i) {
        cgltf_light *l = gltf->lights + i;
        GLTFLight *light = [[GLTFLight alloc] initWithType:GLTFLightTypeForType(l->type)];
        light.color = (simd_float3){ l->color[0], l->color[1], l->color[2] };
        light.intensity = l->intensity;
        light.range = l->range;
        if (l->type == cgltf_light_type_spot) {
            light.innerConeAngle = l->spot_inner_cone_angle;
            light.outerConeAngle = l->spot_outer_cone_angle;
        }
        [lights addObject:light];
    }
    return lights;
}

- (NSArray *)convertNodes
{
    NSMutableArray *nodes = [NSMutableArray array];
    for (int i = 0; i < gltf->nodes_count; ++i) {
        cgltf_node *n = gltf->nodes + i;
        GLTFNode *node = [GLTFNode new];
        if (n->camera) {
            size_t cameraIndex = n->camera - gltf->cameras;
            node.camera = self.asset.cameras[cameraIndex];
        }
        if (n->light) {
            size_t lightIndex = n->light - gltf->lights;
            node.light = self.asset.lights[lightIndex];
        }
        if (n->mesh) {
            size_t meshIndex = n->mesh - gltf->meshes;
            node.mesh = self.asset.meshes[meshIndex];
        }
        if (n->has_matrix) {
            simd_float4x4 transform;
            memcpy(&transform, n->matrix, sizeof(float) * 16);
            node.matrix = transform;
            float sx = simd_length(transform.columns[0].xyz);
            float sy = simd_length(transform.columns[1].xyz);
            float sz = simd_length(transform.columns[2].xyz);
            node.scale = simd_make_float3(sx, sy, sz);
            node.rotation = simd_quaternion(transform);
            node.translation = transform.columns[3].xyz;
        } else {
            if (n->has_translation) {
                node.translation = simd_make_float3(n->translation[0], n->translation[1], n->translation[2]);
            }
            if (n->has_scale) {
                node.scale = simd_make_float3(n->scale[0], n->scale[1], n->scale[2]);
            }
            if (n->has_rotation) {
                node.rotation = simd_quaternion(n->rotation[0], n->rotation[1], n->rotation[2], n->rotation[3]);
            }
            float m[16];
            cgltf_node_transform_local(n, &m[0]);
            simd_float4x4 transform;
            memcpy(&transform, m, sizeof(float) * 16);
            node.matrix = transform;
        }
        // TODO: morph target weights
        if (n->has_mesh_gpu_instancing) {
            cgltf_mesh_gpu_instancing *mi = &n->mesh_gpu_instancing;
            NSMutableArray *attributes = [NSMutableArray array];
            for (int j = 0; j < mi->attributes_count; ++j) {
                cgltf_attribute *a = mi->attributes + j;
                NSString *attrName = [NSString stringWithUTF8String:a->name];
                size_t attrIndex = a->data - gltf->accessors;
                GLTFAccessor *attrAccessor = self.asset.accessors[attrIndex];
                GLTFAttribute *attr = [[GLTFAttribute alloc] initWithName:attrName accessor:attrAccessor];
                [attributes addObject:attr];
            }
            GLTFMeshInstances *instances = [GLTFMeshInstances new];
            instances.attributes = [attributes copy];
            node.meshInstances = instances;
        }
        node.name = n->name ? GLTFUnescapeJSONString(n->name)
                            : [self.nameGenerator nextUniqueNameWithPrefix:@"Node"];
        node.extensions = GLTFConvertExtensions(n->extensions, n->extensions_count, nil);
        node.extras = GLTFObjectFromExtras(gltf->json, n->extras, nil);
        [nodes addObject:node];
    }
    for (int i = 0; i < gltf->nodes_count; ++i) {
        cgltf_node *n = gltf->nodes + i;
        GLTFNode *node = nodes[i];
        if (n->children_count > 0) {
            NSMutableArray *children = [NSMutableArray arrayWithCapacity:n->children_count];
            for (int j = 0; j < n->children_count; ++j) {
                size_t childIndex = n->children[j] - gltf->nodes;
                GLTFNode *child = nodes[childIndex];
                [children addObject:child];
            }
            node.childNodes = children; // Automatically creates inverse child->parent reference
        }
    }
    return nodes;
}

- (NSArray *)convertSkins
{
    NSMutableArray *skins = [NSMutableArray array];
    for (int i = 0; i < gltf->skins_count; ++i) {
        cgltf_skin *s = gltf->skins + i;
        NSMutableArray *joints = [NSMutableArray arrayWithCapacity:s->joints_count];
        for (int j = 0; j < s->joints_count; ++j) {
            size_t jointIndex = s->joints[j] - gltf->nodes;
            GLTFNode *joint = self.asset.nodes[jointIndex];
            [joints addObject:joint];
        }
        GLTFSkin *skin = [[GLTFSkin alloc] initWithJoints:joints];
        if (s->inverse_bind_matrices) {
            size_t ibmIndex = s->inverse_bind_matrices - gltf->accessors;
            GLTFAccessor *ibms = self.asset.accessors[ibmIndex];
            skin.inverseBindMatrices = ibms;
        }
        if (s->skeleton) {
            size_t skeletonIndex = s->skeleton - gltf->nodes;
            GLTFNode *skeletonRoot = self.asset.nodes[skeletonIndex];
            skin.skeleton = skeletonRoot;
        }
        skin.name = s->name ? GLTFUnescapeJSONString(s->name)
                            : [self.nameGenerator nextUniqueNameWithPrefix:@"Skin"];
        skin.extensions = GLTFConvertExtensions(s->extensions, s->extensions_count, nil);
        skin.extras = GLTFObjectFromExtras(gltf->json, s->extras, nil);
        [skins addObject:skin];
    }

    for (int i = 0; i < gltf->nodes_count; ++i) {
        cgltf_node *n = gltf->nodes + i;
        GLTFNode *node = self.asset.nodes[i];
        if (n->skin) {
            size_t skinIndex = n->skin - gltf->skins;
            node.skin = skins[skinIndex];
        }
    }

    return skins;
}

- (NSArray *)convertAnimations
{
    NSMutableArray *animations = [NSMutableArray array];
    for (int i = 0; i < gltf->animations_count; ++i) {
        cgltf_animation *a = gltf->animations + i;
        NSMutableArray<GLTFAnimationSampler *> *samplers = [NSMutableArray arrayWithCapacity:a->samplers_count];
        for (int j = 0; j < a->samplers_count; ++j) {
            cgltf_animation_sampler *s = a->samplers + j;
            size_t inputIndex = s->input - gltf->accessors;
            GLTFAccessor *input = self.asset.accessors[inputIndex];
            size_t outputIndex = s->output - gltf->accessors;
            GLTFAccessor *output = self.asset.accessors[outputIndex];
            GLTFAnimationSampler *sampler = [[GLTFAnimationSampler alloc] initWithInput:input output:output];
            sampler.interpolationMode = GLTFInterpolationModeForType(s->interpolation);
            [samplers addObject:sampler];
        }
        NSMutableArray<GLTFAnimationChannel *> *channels = [NSMutableArray arrayWithCapacity:a->channels_count];
        for (int j = 0; j < a->channels_count; ++j) {
            cgltf_animation_channel *c = a->channels + j;
            NSString *targetPath = GLTFTargetPathForPath(c->target_path);
            GLTFAnimationTarget *target = [[GLTFAnimationTarget alloc] initWithPath:targetPath];
            if (c->target_node) {
                size_t targetIndex = c->target_node - gltf->nodes;
                GLTFNode *targetNode = self.asset.nodes[targetIndex];
                target.node = targetNode;
            }
            size_t samplerIndex = c->sampler - a->samplers;
            GLTFAnimationSampler *sampler = samplers[samplerIndex];
            GLTFAnimationChannel *channel = [[GLTFAnimationChannel alloc] initWithTarget:target sampler:sampler];
            channel.extensions = GLTFConvertExtensions(c->extensions, c->extensions_count, nil);
            channel.extras = GLTFObjectFromExtras(gltf->json, c->extras, nil);
            [channels addObject:channel];
        }
        GLTFAnimation *animation = [[GLTFAnimation alloc] initWithChannels:channels samplers:samplers];
        animation.name = a->name ? GLTFUnescapeJSONString(a->name)
                                 : [self.nameGenerator nextUniqueNameWithPrefix:@"Animation"];
        animation.extras = GLTFObjectFromExtras(gltf->json, a->extras, nil);
        [animations addObject:animation];
    }
    return animations;
}

- (NSArray *)convertScenes
{
    NSMutableArray *scenes = [NSMutableArray array];
    for (int i = 0; i < gltf->scenes_count; ++i) {
        cgltf_scene *s = gltf->scenes + i;
        GLTFScene *scene = [GLTFScene new];
        NSMutableArray *rootNodes = [NSMutableArray arrayWithCapacity:s->nodes_count];
        for (int j = 0; j < s->nodes_count; ++j) {
            size_t nodeIndex = s->nodes[j] - gltf->nodes;
            GLTFNode *node = self.asset.nodes[nodeIndex];
            [rootNodes addObject:node];
        }
        scene.nodes = rootNodes;
        scene.name = s->name ? GLTFUnescapeJSONString(s->name)
                             : [self.nameGenerator nextUniqueNameWithPrefix:@"Scene"];
        scene.extensions = GLTFConvertExtensions(s->extensions, s->extensions_count, nil);
        scene.extras = GLTFObjectFromExtras(gltf->json, s->extras, nil);
        [scenes addObject:scene];
    }
    return scenes;
}

- (BOOL)validateRequiredExtensions:(NSError **)error {
    NSMutableArray *supportedExtensions = [NSMutableArray arrayWithObjects:
        GLTFExtensionEXTMeshoptCompression,
        @"KHR_emissive_strength",
        @"KHR_materials_ior",
        @"KHR_lights_punctual",
        @"KHR_materials_clearcoat",
        @"KHR_materials_specular",
        @"KHR_materials_transmission",
        @"KHR_materials_unlit",
        @"KHR_materials_variants",
        @"KHR_mesh_quantization",
        @"KHR_texture_transform",
        @"KHR_materials_pbrSpecularGlossiness", // deprecated
        nil
    ];
    if ([GLTFAsset dracoDecompressorClassName] != nil) {
        [supportedExtensions addObject:@"KHR_draco_mesh_compression"];
    }
#if defined(GLTF_BUILD_WITH_KTX2)
    [supportedExtensions addObject:@"KHR_texture_basisu"];
#endif
    NSMutableArray *unsupportedExtensions = [NSMutableArray array];
    for (NSString *requiredExtension in self.asset.extensionsRequired) {
        if (![supportedExtensions containsObject:requiredExtension]) {
            [unsupportedExtensions addObject:requiredExtension];
        }
    }
    if (unsupportedExtensions.count > 0) {
        if (error != nil) {
            NSString *description = [NSString stringWithFormat:@"Asset contains unsupported required extensions: %@",
                                     unsupportedExtensions];
            *error = [NSError errorWithDomain:GLTFErrorDomain code:GLTFErrorCodeUnsupportedExtension userInfo:@{
                NSLocalizedDescriptionKey : description
            }];
        }
    }
    return (unsupportedExtensions.count == 0);
}

- (BOOL)convertAsset:(NSError **)error {
    self.asset = [GLTFAsset new];
    self.asset.url = self.assetURL;
    cgltf_asset *meta = &gltf->asset;
    if (meta->copyright) {
        self.asset.copyright = GLTFUnescapeJSONString(meta->copyright);
    }
    if (meta->generator) {
        self.asset.generator = GLTFUnescapeJSONString(meta->generator);
    }
    if (meta->min_version) {
        self.asset.minVersion = GLTFUnescapeJSONString(meta->min_version);
    }
    if (meta->version) {
        self.asset.version = GLTFUnescapeJSONString(meta->version);
    }
    if (gltf->extensions_used_count > 0) {
        NSMutableArray *extensionsUsed = [NSMutableArray arrayWithCapacity:gltf->extensions_used_count];
        for (int i = 0; i < gltf->extensions_used_count; ++i) {
            NSString *extension = [NSString stringWithUTF8String:gltf->extensions_used[i]];
            [extensionsUsed addObject:extension];
        }
        self.asset.extensionsUsed = extensionsUsed;
    }
    if (gltf->extensions_required_count > 0) {
        NSMutableArray *extensionsRequired = [NSMutableArray arrayWithCapacity:gltf->extensions_required_count];
        for (int i = 0; i < gltf->extensions_required_count; ++i) {
            NSString *extension = [NSString stringWithUTF8String:gltf->extensions_required[i]];
            [extensionsRequired addObject:extension];
        }
        self.asset.extensionsRequired = extensionsRequired;
    }
    if(![self validateRequiredExtensions:error]) {
        return NO;
    }
    self.asset.extensions = GLTFConvertExtensions(meta->extensions, meta->extensions_count, nil);
    self.asset.extras = GLTFObjectFromExtras(gltf->json, meta->extras, nil);
    self.asset.buffers = [self convertBuffers];
    self.asset.bufferViews = [self convertBufferViews];
    self.asset.accessors = [self convertAccessors];
    self.asset.samplers = [self convertTextureSamplers];
    self.asset.images = [self convertImages];
    self.asset.textures = [self convertTextures];
    self.asset.materials = [self convertMaterials];
    self.asset.materialVariants = [self convertMaterialVariants];
    self.asset.meshes = [self convertMeshes];
    self.asset.cameras = [self convertCameras];
    self.asset.lights = [self convertLights];
    self.asset.nodes = [self convertNodes];
    self.asset.skins = [self convertSkins];
    self.asset.animations = [self convertAnimations];
    self.asset.scenes = [self convertScenes];
    if (gltf->scene) {
        size_t sceneIndex = gltf->scene - gltf->scenes;
        GLTFScene *scene = self.asset.scenes[sceneIndex];
        self.asset.defaultScene = scene;
    } else {
        self.asset.defaultScene = self.asset.scenes.firstObject;
    }
    return YES;
}

@end
