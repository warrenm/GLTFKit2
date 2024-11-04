
#import "GLTFAsset.h"
#import "GLTFAssetReader.h"
#import "GLTFAssetWriter.h"
#import "GLTFLogging.h"
#import "GLTFKTX2Support.h"

#import <ImageIO/ImageIO.h>

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
    #import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

const float LumensPerCandela = 1.0 / (4.0 * M_PI);

static NSString *g_dracoDecompressorClassName = nil;

GLTFAssetLoadingOption const GLTFAssetCreateNormalsIfAbsentKey = @"GLTFAssetCreateNormalsIfAbsentKey";
GLTFAssetLoadingOption const GLTFAssetAssetDirectoryURLKey = @"GLTFAssetAssetDirectoryURLKey";

NSString *const GLTFErrorDomain = @"com.metalbyexample.gltfkit2";

GLTFAttributeSemantic GLTFAttributeSemanticPosition = @"POSITION";
GLTFAttributeSemantic GLTFAttributeSemanticNormal = @"NORMAL";
GLTFAttributeSemantic GLTFAttributeSemanticTangent = @"TANGENT";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord0 = @"TEXCOORD_0";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord1 = @"TEXCOORD_1";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord2 = @"TEXCOORD_2";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord3 = @"TEXCOORD_3";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord4 = @"TEXCOORD_4";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord5 = @"TEXCOORD_5";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord6 = @"TEXCOORD_6";
GLTFAttributeSemantic GLTFAttributeSemanticTexcoord7 = @"TEXCOORD_7";
GLTFAttributeSemantic GLTFAttributeSemanticColor0 = @"COLOR_0";
GLTFAttributeSemantic GLTFAttributeSemanticJoints0 = @"JOINTS_0";
GLTFAttributeSemantic GLTFAttributeSemanticJoints1 = @"JOINTS_1";
GLTFAttributeSemantic GLTFAttributeSemanticWeights0 = @"WEIGHTS_0";
GLTFAttributeSemantic GLTFAttributeSemanticWeights1 = @"WEIGHTS_1";

GLTFAnimationPath GLTFAnimationPathTranslation = @"translation";
GLTFAnimationPath GLTFAnimationPathRotation = @"rotation";
GLTFAnimationPath GLTFAnimationPathScale = @"scale";
GLTFAnimationPath GLTFAnimationPathWeights = @"weights";

static NSString *const GLTFMediaTypeWebP = @"image/webp";

float GLTFDegFromRad(float rad) {
    return rad * (180.0 / M_PI);
}

int GLTFBytesPerComponentForComponentType(GLTFComponentType type) {
    switch (type) {
        case GLTFComponentTypeByte:
        case GLTFComponentTypeUnsignedByte:
            return sizeof(UInt8);
        case GLTFComponentTypeShort:
        case GLTFComponentTypeUnsignedShort:
            return sizeof(UInt16);
        case GLTFComponentTypeUnsignedInt:
        case GLTFComponentTypeFloat:
            return sizeof(UInt32);
        default:
            break;
    }
    return 0;
}

int GLTFComponentCountForDimension(GLTFValueDimension dim) {
    switch (dim) {
        case GLTFValueDimensionScalar:
            return 1;
        case GLTFValueDimensionVector2:
            return 2;
        case GLTFValueDimensionVector3:
            return 3;
        case GLTFValueDimensionVector4:
            return 4;
        case GLTFValueDimensionMatrix2:
            return 4;
        case GLTFValueDimensionMatrix3:
            return 9;
        case GLTFValueDimensionMatrix4:
            return 16;
        default: break;
    }
    return 0;
}

NSData *GLTFPackedDataForAccessor(GLTFAccessor *accessor) {
    GLTFBufferView *bufferView = accessor.bufferView;
    GLTFBuffer *buffer = bufferView.buffer;
    size_t bytesPerComponent = GLTFBytesPerComponentForComponentType(accessor.componentType);
    size_t componentCount = GLTFComponentCountForDimension(accessor.dimension);
    size_t elementSize = bytesPerComponent * componentCount;
    size_t bufferLength = elementSize * accessor.count;
    void *bytes = malloc(bufferLength);
    if (bufferView != nil) {
        void *bufferViewBaseAddr = (void *)buffer.data.bytes + bufferView.offset;
        if (bufferView.stride == 0 || bufferView.stride == elementSize) {
            // Fast path
            memcpy(bytes, bufferViewBaseAddr + accessor.offset, accessor.count * elementSize);
        } else {
            // Slow path, element by element
            size_t sourceStride = bufferView.stride ?: elementSize;
            for (int i = 0; i < accessor.count; ++i) {
                void *src = bufferViewBaseAddr + (i * sourceStride) + accessor.offset;
                void *dest = bytes + (i * elementSize);
                memcpy(dest, src, elementSize);
            }
        }
    } else {
        // 3.6.2.3. Sparse Accessors
        // When accessor.bufferView is undefined, the sparse accessor is initialized as
        // an array of zeros of size (size of the accessor element) * (accessor.count) bytes.
        // https://www.khronos.org/registry/glTF/specs/2.0/glTF-2.0.html#sparse-accessors
        memset(bytes, 0, bufferLength);
    }
    if (accessor.sparse) {
        const void *baseSparseIndexBufferViewPtr = accessor.sparse.indices.buffer.data.bytes +
                                                   accessor.sparse.indices.offset;
        const void *baseSparseIndexAccessorPtr = baseSparseIndexBufferViewPtr + accessor.sparse.indexOffset;

        const void *baseValueBufferViewPtr = accessor.sparse.values.buffer.data.bytes + accessor.sparse.values.offset;
        const void *baseSrcPtr = baseValueBufferViewPtr + accessor.sparse.valueOffset;
        const size_t srcValueStride = accessor.sparse.values.stride ?: elementSize;

        void *baseDestPtr = bytes;

        switch (accessor.sparse.indexComponentType) {
            case GLTFComponentTypeUnsignedByte: {
                const UInt8 *sparseIndices = (UInt8 *)baseSparseIndexAccessorPtr;
                for (int i = 0; i < accessor.sparse.count; ++i) {
                    UInt8 sparseIndex = sparseIndices[i];
                    memcpy(baseDestPtr + sparseIndex * elementSize, baseSrcPtr + (i * srcValueStride), elementSize);
                }
                break;
            }
            case GLTFComponentTypeUnsignedShort: {
                const UInt16 *sparseIndices = (UInt16 *)baseSparseIndexAccessorPtr;
                for (int i = 0; i < accessor.sparse.count; ++i) {
                    UInt16 sparseIndex = sparseIndices[i];
                    memcpy(baseDestPtr + sparseIndex * elementSize, baseSrcPtr + (i * srcValueStride), elementSize);
                }
                break;
            }
            case GLTFComponentTypeUnsignedInt: {
                const UInt32 *sparseIndices = (UInt32 *)baseSparseIndexAccessorPtr;
                for (int i = 0; i < accessor.sparse.count; ++i) {
                    UInt32 sparseIndex = sparseIndices[i];
                    memcpy(baseDestPtr + sparseIndex * elementSize, baseSrcPtr + (i * srcValueStride), elementSize);
                }
                break;
            }
            default:
                assert(!"Sparse accessor index type must be one of: unsigned byte, unsigned short, or unsigned int.");
                break;
        }
    }
    return [NSData dataWithBytesNoCopy:bytes length:bufferLength freeWhenDone:YES];
}

NSData *GLTFTransformPackedDataToFloat(NSData *sourceData, GLTFAccessor *sourceAccessor) {
    if (sourceAccessor.componentType == GLTFComponentTypeFloat) {
        return sourceData; // Nothing to do
    }

    if ((sourceAccessor.componentType != GLTFComponentTypeByte) &&
        (sourceAccessor.componentType != GLTFComponentTypeUnsignedByte) &&
        (sourceAccessor.componentType != GLTFComponentTypeShort) &&
        (sourceAccessor.componentType != GLTFComponentTypeUnsignedShort))
    {
        NSLog(@"[GLTFKit2] Warning: Failed to convert unsupported normalized data. Returning source data.");
        return sourceData;
    }

    size_t vectorCount = sourceAccessor.count;
    size_t componentCount = sourceAccessor.dimension;
    size_t elementCount = vectorCount * componentCount;

    size_t outBufferSize = vectorCount * componentCount * sizeof(float);
    float *dstBase = malloc(outBufferSize);
    NSData *outData = [NSData dataWithBytesNoCopy:dstBase length:outBufferSize freeWhenDone:YES];

    // "Implementations MUST use following equations to decode real floating-point value f from a normalized integer c"
    // https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#animations
    switch (sourceAccessor.componentType) {
        case GLTFComponentTypeByte: {
            const int8_t *srcBase = sourceData.bytes;
            if (sourceAccessor.isNormalized) {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = MAX(srcBase[i] / 127.0f, -1.0f); // max(c / 127.0, -1.0)
                }
            } else {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = srcBase[i];
                }
            }
            break;
        }
        case GLTFComponentTypeUnsignedByte: {
            const uint8_t *srcBase = sourceData.bytes;
            if (sourceAccessor.isNormalized) {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = srcBase[i] / 255.0f; // f = c / 255.0
                }
            } else {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = srcBase[i];
                }
            }
            break;
        }
        case GLTFComponentTypeShort: {
            const int16_t *srcBase = sourceData.bytes;
            if (sourceAccessor.isNormalized) {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = MAX(srcBase[i] / 32767.0f, -1.0f); // f = max(c / 32767.0, -1.0)
                }
            } else {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = srcBase[i];
                }
            }
            break;
        }
        case GLTFComponentTypeUnsignedShort: {
            const uint16_t *srcBase = sourceData.bytes;
            if (sourceAccessor.isNormalized) {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = srcBase[i] / 65535.0f; // f = c / 65535.0
                }
            } else {
                for (size_t i = 0; i < elementCount; ++i) {
                    dstBase[i] = srcBase[i];
                }
            }
            break;
        }
        default:
            break; // Impossible.
    }

    return outData;
}

static NSString * _Nullable GLTFInferredMediaTypeForData(NSData *data) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;

    uint8_t pngIdentifier[] = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    if (data.length > 8 && (memcmp(bytes, pngIdentifier, 8) == 0)) {
        return @"image/png";
    }
    uint8_t jpegIdentifier[] = { 0xFF, 0xD8, 0xFF };
    if (data.length > 3 && (memcmp(bytes, jpegIdentifier, 3) == 0)) {
        return @"image/jpeg";
    }
    uint8_t ktx2Identifier[] = { 0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A };
    if (data.length > 12 && (memcmp(bytes, ktx2Identifier, 12) == 0)) {
        return GLTFMediaTypeKTX2;
    }
    uint8_t riffIdentifier[] = { 0x52, 0x49, 0x46, 0x46 };
    uint8_t webpIdentifier[] = { 0x57, 0x45, 0x42, 0x50 };
    if (data.length > 12 && (memcmp(bytes, riffIdentifier, 4) == 0) && (memcmp(bytes + 8, webpIdentifier, 4) == 0)) {
        return GLTFMediaTypeWebP;
    }

    return nil;
}

static NSString *_Nullable GLTFCreateUTIForMediaType(NSString *mediaType) {
    // Despite a UTI for KTX2 existing in the system, it's not possible to create it from a file extension
    // or MIME type as of macOS 14.0, even using the newer UTType APIs, so we hack around that here.
    if ([mediaType isEqualToString:GLTFMediaTypeKTX2]) {
        return @"org.khronos.ktx2";
    }
#if defined(TARGET_OS_VISION) && TARGET_OS_VISION
    UTType *_Nullable type = [UTType typeWithMIMEType:mediaType];
    return type.identifier;
#else
    if (@available(macos 11.0, iOS 14.0, tvOS 14.0, *)) {
        UTType *_Nullable type = [UTType typeWithMIMEType:mediaType];
        return type.identifier;
    } else {
        CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)mediaType, NULL);
        return (__bridge_transfer NSString *)uti;
    }
#endif
}

NSData *GLTFCreateImageDataFromDataURI(NSString *uriData, NSString **outMediaType) {
    NSString *prefix = @"data:";
    if ([uriData hasPrefix:prefix]) {
        NSInteger prefixEnd = prefix.length;
        NSInteger firstComma = [uriData rangeOfString:@","].location;
        if (firstComma != NSNotFound) {
            NSString *mediaTypeAndTokenString = [uriData substringWithRange:NSMakeRange(prefixEnd, firstComma - prefixEnd)];
            NSArray *mediaTypeAndToken = [mediaTypeAndTokenString componentsSeparatedByString:@";"];
            if (mediaTypeAndToken.count > 0) {
                if (outMediaType) {
                    *outMediaType = mediaTypeAndToken[0];
                }
                NSString *encodedImageData = [uriData substringFromIndex:firstComma + 1];
                NSData *imageData = [[NSData alloc] initWithBase64EncodedString:encodedImageData
                                                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
                return imageData;
            }
        }
    }
    return nil;
}

@implementation GLTFObject

- (instancetype)init {
    if (self = [super init]) {
        _name = @"";
        _identifier = [NSUUID UUID];
        _extensions = @{};
    }
    return self;
}

@end

@implementation GLTFAsset

+ (nullable instancetype)assetWithURL:(NSURL *)url
                              options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                                error:(NSError **)error
{
    __block NSError *internalError = nil;
    __block GLTFAsset *maybeAsset = nil;
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(0);
    [self loadAssetWithURL:url options:options handler:^(float progress,
                                                         GLTFAssetStatus status,
                                                         GLTFAsset *asset,
                                                         NSError *loadingError,
                                                         BOOL *stop)
    {
        if (status == GLTFAssetStatusError || status == GLTFAssetStatusComplete) {
            internalError = loadingError;
            maybeAsset = asset;
            dispatch_semaphore_signal(loadSemaphore);
        }
    }];
    dispatch_semaphore_wait(loadSemaphore, DISPATCH_TIME_FOREVER);
    if (error) {
        *error = internalError;
    }
    return maybeAsset;
}

+ (nullable instancetype)assetWithData:(NSData *)data
                               options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                                 error:(NSError **)error
{
    __block NSError *internalError = nil;
    __block GLTFAsset *maybeAsset = nil;
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(0);
    [self loadAssetWithData:data options:options handler:^(float progress,
                                                         GLTFAssetStatus status,
                                                         GLTFAsset *asset,
                                                         NSError *loadError,
                                                         BOOL *stop)
    {
        if (status == GLTFAssetStatusError || status == GLTFAssetStatusComplete) {
            internalError = loadError;
            maybeAsset = asset;
            dispatch_semaphore_signal(loadSemaphore);
        }
    }];
    dispatch_semaphore_wait(loadSemaphore, DISPATCH_TIME_FOREVER);
    if (error) {
        *error = internalError;
    }
    return maybeAsset;
}

+ (void)loadAssetWithURL:(NSURL *)url
                 options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                 handler:(nullable GLTFAssetLoadingHandler)handler
{
    [GLTFAssetReader loadAssetWithURL:url options:options handler:handler];
}

+ (void)loadAssetWithData:(NSData *)data
                  options:(NSDictionary<GLTFAssetLoadingOption, id> *)options
                  handler:(nullable GLTFAssetLoadingHandler)handler
{
    [GLTFAssetReader loadAssetWithData:data options:options handler:handler];
}

- (void)writeToURL:(NSURL *)url
           options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
   progressHandler:(nullable GLTFAssetURLExportProgressHandler)progressHandler
{
    [GLTFAssetWriter writeAsset:self toURL:url options:options progressHandler:progressHandler];
}

- (void)serializeWithOptions:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
             progressHandler:(nullable GLTFAssetDataExportProgressHandler)progressHandler
{
    [GLTFAssetWriter serializeAsset:self options:options progressHandler:progressHandler];
}

- (BOOL)writeToURL:(NSURL *)url
           options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
             error:(NSError **)error
{
    __block NSError *internalError = nil;
    __block BOOL wroteSuccessfully = NO;
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(0);
    [GLTFAssetWriter writeAsset:self toURL:url options:options progressHandler:^(float progress, 
                                                                                 GLTFAssetStatus status,
                                                                                 NSError * _Nullable writeError,
                                                                                 BOOL * _Nonnull stop)
     {
        if (status == GLTFAssetStatusError || status == GLTFAssetStatusComplete) {
            internalError = writeError;
            wroteSuccessfully = (status == GLTFAssetStatusComplete);
            dispatch_semaphore_signal(loadSemaphore);
        }
    }];
    dispatch_semaphore_wait(loadSemaphore, DISPATCH_TIME_FOREVER);
    if (error) {
        *error = internalError;
    }
    return wroteSuccessfully;
}

- (nullable NSData *)serializeWithOptions:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
                                    error:(NSError **)error
{
    __block NSError *internalError = nil;
    __block NSData *maybeData = nil;
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(0);
    [GLTFAssetWriter serializeAsset:self options:options progressHandler:^(float progress,
                                                                           GLTFAssetStatus status,
                                                                           NSData * _Nullable data,
                                                                           NSError * _Nullable serializationError,
                                                                           BOOL * _Nonnull stop)
     {
        if (status == GLTFAssetStatusError || status == GLTFAssetStatusComplete) {
            internalError = serializationError;
            maybeData = data;
            dispatch_semaphore_signal(loadSemaphore);
        }
    }];
    dispatch_semaphore_wait(loadSemaphore, DISPATCH_TIME_FOREVER);
    if (error) {
        *error = internalError;
    }
    return maybeData;
}

+ (NSString *)dracoDecompressorClassName {
    return g_dracoDecompressorClassName;
}

+ (void)setDracoDecompressorClassName:(NSString *)dracoDecompressorClassName {
    g_dracoDecompressorClassName = dracoDecompressorClassName;
}

- (instancetype)init {
    if (self = [super init]) {
        _version = @"2.0";
        _extensionsUsed = @[];
        _extensionsRequired = @[];
        _accessors = @[];
        _animations = @[];
        _buffers = @[];
        _bufferViews = @[];
        _cameras = @[];
        _images = @[];
        _materials = @[];
        _meshes = @[];
        _nodes = @[];
        _samplers = @[];
        _scenes = @[];
        _skins = @[];
        _textures = @[];
    }
    return self;
}

@end

@implementation GLTFAccessor

- (instancetype)initWithBufferView:(nullable GLTFBufferView *)bufferView
                            offset:(NSInteger)offset
                     componentType:(GLTFComponentType)componentType
                         dimension:(GLTFValueDimension)dimension
                             count:(NSInteger)count
                        normalized:(BOOL)normalized
{
    if (self = [super init]) {
        _bufferView = bufferView;
        _offset = offset;
        _componentType = componentType;
        _dimension = dimension;
        _count = count;
        _normalized = normalized;
        _minValues = @[];
        _maxValues = @[];
    }
    return self;
}

@end

@implementation GLTFAnimation

- (instancetype)initWithChannels:(NSArray<GLTFAnimationChannel *> *)channels
                        samplers:(NSArray<GLTFAnimationSampler *> *)samplers
{
    if (self = [super init]) {
        _channels = [channels copy];
        _samplers = [samplers copy];
    }
    return self;
}

@end

@implementation GLTFAnimationTarget : GLTFObject

- (instancetype)initWithPath:(NSString *)path {
    if (self = [super init]) {
        _path = [path copy];
    }
    return self;
}

@end

@implementation GLTFAnimationChannel

- (instancetype)initWithTarget:(GLTFAnimationTarget *)target
                       sampler:(GLTFAnimationSampler *)sampler
{
    if (self = [super init]) {
        _target = target;
        _sampler = sampler;
    }
    return self;
}

@end

@implementation GLTFAnimationSampler

- (instancetype)initWithInput:(GLTFAccessor *)input output:(GLTFAccessor *)output {
    if (self = [super init]) {
        _input = input;
        _output = output;
        _interpolationMode = GLTFInterpolationModeLinear;
    }
    return self;
}

@end

@implementation GLTFBuffer

- (instancetype)initWithLength:(NSInteger)length {
    if (self = [super init]) {
        _length = length;
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data {
    if (self = [super init]) {
        _length = data.length;
        _data = data;
    }
    return self;
}

@end

@implementation GLTFMeshoptCompression

- (instancetype)initWithBuffer:(GLTFBuffer *)buffer
                        length:(NSUInteger)length
                        stride:(NSUInteger)stride
                         count:(NSUInteger)count
                          mode:(GLTFMeshoptCompressionMode)mode
{
    if (self = [super init]) {
        _buffer = buffer;
        _length = length;
        _stride = stride;
        _count = count;
        _mode = mode;
    }
    return self;
}

@end

@implementation GLTFBufferView

- (instancetype)initWithBuffer:(GLTFBuffer *)buffer
                        length:(NSInteger)length
                        offset:(NSInteger)offset
                        stride:(NSInteger)stride
{
    if (self = [super init]) {
        _buffer = buffer;
        _length = length;
        _offset = offset;
        _stride = stride;
    }
    return self;
}

@end

@implementation GLTFOrthographicProjectionParams

- (instancetype)init {
    if (self = [super init]) {
        _xMag = 1.0;
        _yMag = 1.0;
    }
    return self;
}

@end

@implementation GLTFPerspectiveProjectionParams

- (instancetype)init {
    if (self = [super init]) {
        _yFOV = M_PI_2;
        _aspectRatio = 0.0f;
    }
    return self;
}

@end

@implementation GLTFCamera

- (instancetype)initWithOrthographicProjection:(GLTFOrthographicProjectionParams *)orthographic {
    if (self = [super init]) {
        _orthographic = orthographic;
        _zNear = 1.0f;
        _zFar = 0.0f;
    }
    return self;
}

- (instancetype)initWithPerspectiveProjection:(GLTFPerspectiveProjectionParams *)perspective {
    if (self = [super init]) {
        _perspective = perspective;
        _zNear = 1.0f;
        _zFar = 0.0f; // Default to infinitely distant far plane
    }
    return self;
}

@end

@interface GLTFImage ()
@property (nonatomic, nullable) CGImageRef cachedImage;
@property (nonatomic, nullable) id<MTLTexture> cachedTexture;
@end

@implementation GLTFImage

- (instancetype)initWithURI:(NSURL *)uri {
    if (self = [super init]) {
        _uri = uri;
    }
    return self;
}

- (instancetype)initWithBufferView:(GLTFBufferView *)bufferView mimeType:(NSString *)mimeType {
    if (self = [super init]) {
        _bufferView = bufferView;
        _mimeType = mimeType;
    }
    return self;
}

- (instancetype)initWithCGImage:(CGImageRef)cgImage {
    if (self = [super init]) {
        _cachedImage = CGImageRetain(cgImage);
    }
    return self;
}

- (void)dealloc {
    CGImageRelease(_cachedImage);
}

- (nullable NSData *)newImageDataReturningInferredMediaType:(NSString **)outMediaType {
    BOOL isAccessingSecurityScoped = NO;
    __block NSData *data = nil;
    NSString *mediaType = nil;
    if (self.bufferView) {
        NSData *imageData = self.bufferView.buffer.data;
        const UInt8 *imageBytes = imageData.bytes + self.bufferView.offset;
        CFDataRef sourceData = CFDataCreate(NULL, imageBytes, self.bufferView.length);
        data = (__bridge_transfer NSData *)sourceData;
    } else if (self.uri) {
        if ([self.uri.scheme isEqual:@"data"]) {
            data = GLTFCreateImageDataFromDataURI(self.uri.absoluteString, &mediaType);
        } else {
            isAccessingSecurityScoped = [self.assetDirectoryURL startAccessingSecurityScopedResource];
            NSError *coordinationError = nil;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
            [coordinator coordinateReadingItemAtURL:_uri options:0 error:&coordinationError byAccessor:^(NSURL *newURL) {
                data = [NSData dataWithContentsOfURL:newURL];
            }];
        }
    }
    if (isAccessingSecurityScoped) {
        [self.assetDirectoryURL stopAccessingSecurityScopedResource];
    }
    if (data) {
        if (mediaType == nil) {
            mediaType = GLTFInferredMediaTypeForData(data);
        }
        if (outMediaType) {
            *outMediaType = mediaType;
        }
    }
    return data;
}

- (NSData *)representation {
    return [self newImageDataReturningInferredMediaType:nil];
}

- (nullable CGImageRef)newCGImage {
    if (self.cachedImage) {
        return CGImageRetain(_cachedImage);
    }

    NSString *maybeMediaType = nil;
    NSData *imageData = [self newImageDataReturningInferredMediaType:&maybeMediaType];
    CGImageRef image = NULL;
    if (imageData) {
        if (maybeMediaType) {
            NSString *uti = GLTFCreateUTIForMediaType(maybeMediaType);
            NSArray *supportedUTIs = (__bridge_transfer NSArray *)CGImageSourceCopyTypeIdentifiers();
            // Check for support for this image type. Note that image loading can still fail if, for example,
            // the image file is a KTX2 container with an unsupported supercompression scheme like BasisU.
            if (![supportedUTIs containsObject:uti]) {
                GLTFLogWarning(@"[GLTFKit2] Unrecognized type identifier for image media type %@", maybeMediaType);
            }
        }
        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
        if (imageSource) {
            image = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
            CFRelease(imageSource);
        }
    }
    return image;
}

- (nullable id<MTLTexture>)newTextureWithDevice:(id<MTLDevice>)device {
    if (self.cachedTexture) {
        return self.cachedTexture;
    }

#ifdef GLTF_BUILD_WITH_KTX2
    NSString *maybeMediaType = nil;
    NSData *imageData = [self newImageDataReturningInferredMediaType:&maybeMediaType];

    if (imageData && [maybeMediaType isEqualToString:GLTFMediaTypeKTX2]) {
        id<MTLTexture> texture = GLTFCreateTextureFromKTX2Data(imageData, device);
        return texture;
    }
#else
    GLTFLogError(@"[GLTFKit2] Texture was requested from a GLTFImage, but GLTFKit2 was compiled without KTX2 support");
#endif
    
    return nil;
}

@end

@implementation GLTFLight

- (instancetype)init {
    return [self initWithType:GLTFLightTypeDirectional];
}

- (instancetype)initWithType:(GLTFLightType)type {
    if (self = [super init]) {
        _type = type;
        _color = (simd_float3){ 1.0f, 1.0f, 1.0f };
        _intensity = 1.0f;
        _range = -1.0f;
        _innerConeAngle = 0.0f;
        _outerConeAngle = M_PI_4;
    }
    return self;
}

@end

@implementation GLTFPBRMetallicRoughnessParams

- (instancetype)init {
    if (self = [super init]) {
        _baseColorFactor = (simd_float4){ 1.0f, 1.0f, 1.0f, 1.0f };
        _metallicFactor = 1.0f;
        _roughnessFactor = 1.0;
    }
    return self;
}

@end

@implementation GLTFPBRSpecularGlossinessParams

- (instancetype)init {
    if (self = [super init]) {
        _diffuseFactor = (simd_float4){ 1.0f, 1.0f, 1.0f, 1.0f };
        _specularFactor = (simd_float3){ 1.0f, 1.0f, 1.0f };
        _glossinessFactor = 1.0;
    }
    return self;
}

@end

@implementation GLTFSpecularParams

- (instancetype)init {
    if (self = [super init]) {
        _specularFactor = 1.0f;
        _specularColorFactor = (simd_float3){ 1.0f, 1.0f, 1.0f };
    }
    return self;
}

@end

@implementation GLTFEmissiveParams

- (instancetype)init {
    if (self = [super init]) {
        _emissiveFactor = (simd_float3){ 0.0f, 0.0f, 0.0f };
        _emissiveStrength = 1.0f;
    }
    return self;
}

@end

@implementation GLTFTransmissionParams
@end

@implementation GLTFVolumeParams

- (instancetype)init {
    if (self = [super init]) {
        _thicknessFactor = 0.0f;
        _attenuationDistance = FLT_MAX;
        _attenuationColor = (simd_float3){ 1.0f, 1.0f, 1.0f };
    }
    return self;
}

@end

@implementation GLTFClearcoatParams
@end

@implementation GLTFSheenParams

- (instancetype)init {
    if (self = [super init]) {
        _sheenColorFactor = (simd_float3){ 0.0f, 0.0f, 0.0f };
        _sheenRoughnessFactor = 0.0f;
    }
    return self;
}

@end

@implementation GLTFIridescence

- (instancetype)init {
    if (self = [super init]) {
        _iridescenceFactor = 0.0f;
        _iridescenceIndexOfRefraction = 1.3f;
        _iridescenceThicknessMinimum = 100.0f;
        _iridescenceThicknessMaximum = 400.0f;
    }
    return self;
}

@end

@implementation GLTFAnisotropyParams : NSObject

- (instancetype)init {
    if (self = [super init]) {
        _strength = 0.0f;
        _rotation = 0.0f;
    }
    return self;
}

@end

@implementation GLTFMaterial

- (instancetype)init {
    if (self = [super init]) {
        _alphaMode = GLTFAlphaModeOpaque;
        _alphaCutoff = 0.5f;
        _doubleSided = NO;
    }
    return self;
}

@end

@implementation GLTFMesh

- (instancetype)init {
    return [self initWithPrimitives:@[]];
}

- (instancetype)initWithPrimitives:(NSArray<GLTFPrimitive *> *)primitives {
    if (self = [super init]) {
        _primitives = [primitives copy];
    }
    return self;
}

@end

@implementation GLTFAttribute

- (instancetype)initWithName:(NSString *)name accessor:(GLTFAccessor *)accessor {
    if (self = [super init]) {
        [super setName:name];
        _accessor = accessor;
    }
    return self;
}

@end

@interface GLTFMeshInstances ()
@property (nonatomic, nullable, strong) NSData *cachedTransforms;
@end

@implementation GLTFMeshInstances

- (NSInteger)instanceCount {
    return self.attributes.firstObject.accessor.count;
}

- (nullable GLTFAttribute *)attributeForName:(NSString *)name {
    for (GLTFAttribute *attrib in self.attributes) {
        if ([attrib.name isEqualToString:name]) {
            return attrib;
        }
    }
    return nil;
}

- (simd_float4x4)transformAtIndex:(NSInteger)index {
    if (_cachedTransforms == nil) {
        NSData *_Nullable translationData = nil;
        NSData *_Nullable rotationData = nil;
        NSData *_Nullable scaleData = nil;
        simd_float4x4 *transforms = NULL;
        size_t transformDataLength = sizeof(simd_float4x4) * self.instanceCount;
        posix_memalign((void **)&transforms, _Alignof(simd_float4x4), transformDataLength);
        GLTFAttribute *_Nullable translationAttr = [self attributeForName:@"TRANSLATION"];
        if (translationAttr && translationAttr.accessor) {
            GLTFAccessor *translationAccessor = translationAttr.accessor;
            if (translationAccessor.componentType == GLTFComponentTypeFloat && 
                translationAccessor.dimension == GLTFValueDimensionVector3)
            {
                translationData = GLTFPackedDataForAccessor(translationAccessor);
            } else {
                GLTFLogWarning(@"Translation attribute was present on mesh instancing object, but was not of float VEC3 type");
            }
        }
        GLTFAttribute *_Nullable rotationAttr = [self attributeForName:@"ROTATION"];
        if (rotationAttr && rotationAttr.accessor) {
            GLTFAccessor *rotationAccessor = rotationAttr.accessor;
            NSData *packedRotationData = GLTFPackedDataForAccessor(rotationAccessor);
            rotationData = GLTFTransformPackedDataToFloat(packedRotationData, rotationAccessor);
        }
        GLTFAttribute *_Nullable scaleAttr = [self attributeForName:@"SCALE"];
        if (scaleAttr && scaleAttr.accessor) {
            GLTFAccessor *scaleAccessor = scaleAttr.accessor;
            if (scaleAccessor.componentType == GLTFComponentTypeFloat && 
                scaleAccessor.dimension == GLTFValueDimensionVector3)
            {
                scaleData = GLTFPackedDataForAccessor(scaleAccessor);
            } else {
                GLTFLogWarning(@"Scale attribute was present on mesh instancing object, but was not of float VEC3 type");
            }
        }
        for (int i = 0; i < self.instanceCount; ++i) {
            simd_float4x4 M = matrix_identity_float4x4;
            if (scaleData) {
                float *scale = ((float *)scaleData.bytes) + (i * 3);
                M.columns[0][0] = scale[0];
                M.columns[1][1] = scale[1];
                M.columns[2][2] = scale[2];
            }
            if (rotationData) {
                simd_quatf rotation;
                memcpy(&rotation, ((float *)rotationData.bytes) + (i * 4), sizeof(float) * 4);
                M = simd_mul(simd_matrix4x4(rotation), M);
            }
            if (translationData) {
                float *trans = ((float *)translationData.bytes) + (i * 3);
                M.columns[3][0] = trans[0];
                M.columns[3][1] = trans[1];
                M.columns[3][2] = trans[2];
            }
            transforms[i] = M;
        }
        _cachedTransforms = [NSData dataWithBytesNoCopy:transforms length:transformDataLength freeWhenDone:YES];
    }
    NSAssert(index >= 0 && index < self.instanceCount, @"Could not access instance transform at index %d (of %d)",
             (int)index, (int)self.instanceCount);
    return ((simd_float4x4 *)self.cachedTransforms.bytes)[index];
}

@end

@interface GLTFPrimitive ()
@property (nonatomic, weak) GLTFMaterialMapping *cachedMapping;
@end

@implementation GLTFPrimitive

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSArray<GLTFAttribute *> *)attributes
{
    return [self initWithPrimitiveType:primitiveType attributes:attributes indices:nil];
}

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSArray<GLTFAttribute *> *)attributes
                              indices:(GLTFAccessor *)indices
{
    if (self = [super init]) {
        _primitiveType = primitiveType;
        _attributes = [attributes copy];
        _indices = indices;
    }
    return self;
}

- (nullable GLTFAttribute *)attributeForName:(NSString *)name {
    for (GLTFAttribute *attrib in self.attributes) {
        if ([attrib.name isEqualToString:name]) {
            return attrib;
        }
    }
    return nil;
}

- (GLTFMaterial *)effectiveMaterialForVariant:(GLTFMaterialVariant *)variant {
    if (variant == nil) {
        return nil;
    }
    // Avoid a full scan if we've previously found a match (likely)
    if ([self.cachedMapping.variant isEqual:variant]) {
        return self.cachedMapping.material;
    }
    for (GLTFMaterialMapping *mapping in self.materialMappings) {
        if ([mapping.variant isEqual:variant]) {
            self.cachedMapping = mapping;
            return mapping.material;
        }
    }
    return nil;
}

@end

@implementation GLTFNode

@synthesize childNodes=_childNodes;

- (instancetype)init {
    if (self = [super init]) {
        _matrix = matrix_identity_float4x4;
        _rotation = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);
        _scale = simd_make_float3(1.0f, 1.0f, 1.0f);
        _translation = simd_make_float3(0.0f, 0.0f, 0.0f);
        _childNodes = @[];
    }
    return self;
}

- (void)setChildNodes:(NSArray<GLTFNode *> *)childNodes {
    _childNodes = [childNodes copy];
    for (GLTFNode *child in _childNodes) {
        child.parentNode = self;
    }
}

@end

@implementation GLTFTextureSampler

- (instancetype)init {
    if (self = [super init]) {
        _magFilter = GLTFMagFilterLinear;
        _minMipFilter = GLTFMinMipFilterLinearNearest;
        _wrapS = GLTFAddressModeRepeat;
        _wrapT = GLTFAddressModeRepeat;
    }
    return self;
}

@end

@implementation GLTFScene
@end

@implementation GLTFSkin

- (instancetype)initWithJoints:(NSArray<GLTFNode *> *)joints {
    if (self = [super init]) {
        _joints = [joints copy];
    }
    return self;
}

@end

@implementation GLTFSparseStorage : GLTFObject

- (instancetype)initWithValues:(GLTFBufferView *)values
                   valueOffset:(NSInteger)valueOffset
                       indices:(GLTFBufferView *)indices
                   indexOffset:(NSInteger)indexOffset
            indexComponentType:(GLTFComponentType)indexComponentType
                         count:(NSInteger)count
{
    if (self = [super init]) {
        _values = values;
        _valueOffset = valueOffset;
        _indices = indices;
        _indexOffset = indexOffset;
        _indexComponentType = indexComponentType;
        _count = count;
    }
    return self;
}

@end

@implementation GLTFTextureTransform

- (instancetype)init {
    if (self = [super init]) {
        _scale = (simd_float2){ 1.0f, 1.0f };
    }
    return self;
}

- (simd_float4x4)matrix {
    float c = cosf(_rotation);
    float s = sinf(_rotation);
    simd_float4x4 S = {{
        { _scale.x,     0.0f, 0.0f, 0.0f },
        {     0.0f, _scale.y, 0.0f, 0.0f },
        {     0.0f,     0.0f, 1.0f, 0.0f },
        {     0.0f,     0.0f, 0.0f, 1.0f }
    }};
    simd_float4x4 R = {{
        {    c,   -s, 0.0f, 0.0f },
        {    s,    c, 0.0f, 0.0f },
        { 0.0f, 0.0f, 1.0f, 0.0f },
        { 0.0f, 0.0f, 0.0f, 1.0f }
    }};
    simd_float4x4 T = {{
        {      1.0f,      0.0f, 0.0f, 0.0f },
        {      0.0f,      1.0f, 0.0f, 0.0f },
        {      0.0f,      0.0f, 1.0f, 0.0f },
        { _offset.x, _offset.y, 0.0f, 1.0f }
    }};
    return simd_mul(T, simd_mul(R, S));
}

@end

@implementation GLTFTextureParams

- (instancetype)init {
    if (self = [super init]) {
        _scale = 1.0f;
        _extensions = @{};
    }
    return self;
}

@end

@implementation GLTFTexture

- (instancetype)initWithSource:(nullable GLTFImage *)source basisUSource:(GLTFImage *)basisUSource {
    if (self = [super init]) {
        _source = source;
        _basisUSource = basisUSource;
    }
    return self;
}

- (instancetype)initWithSource:(nullable GLTFImage *)source {
    return [self initWithSource:source basisUSource:nil];
}

- (instancetype)init {
    return [self initWithSource:nil];
}

@end

@implementation GLTFMaterialVariant

- (instancetype)initWithName:(NSString *)name {
    if (self = [super init]) {
        [super setName:name];
    }
    return self;
}

@end

@implementation GLTFMaterialMapping

- (instancetype)initWithMaterial:(GLTFMaterial *)material variant:(GLTFMaterialVariant *)variant {
    if (self = [super init]) {
        _material = material;
        _variant = variant;
    }
    return self;
}

@end
