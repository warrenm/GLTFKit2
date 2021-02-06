
#import "GLTFAsset.h"
#import "GLTFAssetReader.h"

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
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(1);
    [self loadAssetWithURL:url options:options handler:^(float progress,
                                                         GLTFAssetStatus status,
                                                         GLTFAsset *asset,
                                                         NSError *error,
                                                         BOOL *stop)
    {
        if (status == GLTFAssetStatusError || status == GLTFAssetStatusComplete) {
            internalError = error;
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
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(1);
    [self loadAssetWithData:data options:options handler:^(float progress,
                                                         GLTFAssetStatus status,
                                                         GLTFAsset *asset,
                                                         NSError *error,
                                                         BOOL *stop)
    {
        if (status == GLTFAssetStatusError || status == GLTFAssetStatusComplete) {
            internalError = error;
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

- (instancetype)initWithBufferView:(GLTFBufferView * _Nullable)bufferView
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
        _aspectRatio = 1.0f;
    }
    return self;
}

@end

@implementation GLTFCamera

- (instancetype)initWithOrthographicProjection:(GLTFOrthographicProjectionParams *)orthographic {
    if (self = [super init]) {
        _orthographic = orthographic;
        _zNear = 1.0f;
        _zFar = 100.0f;
    }
    return self;
}

- (instancetype)initWithPerspectiveProjection:(GLTFPerspectiveProjectionParams *)perspective {
    if (self = [super init]) {
        _perspective = perspective;
        _zNear = 1.0f;
        _zFar = 100.0f; //  TODO: Handle infinite far projection
    }
    return self;
}

@end

@interface GLTFImage ()
@property (nonatomic) CGImageRef cachedCGImage;
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

- (CGImageRef)cgImage {
    if (_cachedCGImage) {
        return _cachedCGImage;
    }    
    CGImageSourceRef imageSource = NULL;
    if (self.bufferView) {
        NSData *imageData = self.bufferView.buffer.data;
        const UInt8 *imageBytes = imageData.bytes + self.bufferView.offset;
        CFDataRef sourceData = CFDataCreateWithBytesNoCopy(NULL, imageBytes, self.bufferView.length, NULL);
        imageSource = CGImageSourceCreateWithData(sourceData, NULL);
    } else if (self.uri) {
        imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)_uri, NULL);
    }
    if (imageSource) {
        _cachedCGImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    }
    return _cachedCGImage;
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

@implementation GLTFMaterial

- (instancetype)init {
    if (self = [super init]) {
        _emissiveFactor = (simd_float3){ 0.0f, 0.0f, 0.0f };
        _alphaMode = GLTFAlphaModeOpaque;
        _alphaCutoff = 0.5f;
        _doubleSided = NO;
    }
    return self;
}

@end

@implementation GLTFMesh

- (instancetype)initWithPrimitives:(NSArray<GLTFPrimitive *> *)primitives {
    if (self = [super init]) {
        _primitives = [primitives copy];
    }
    return self;
}

@end

@implementation GLTFPrimitive

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSDictionary<NSString *, GLTFAccessor *> *)attributes
{
    return [self initWithPrimitiveType:primitiveType attributes:attributes indices:nil];
}

- (instancetype)initWithPrimitiveType:(GLTFPrimitiveType)primitiveType
                           attributes:(NSDictionary<NSString *, GLTFAccessor *> *)attributes
                              indices:(GLTFAccessor *)indices
{
    if (self = [super init]) {
        _primitiveType = primitiveType;
        _attributes = [attributes copy];
        _indices = indices;
    }
    return self;
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

@implementation GLTFTextureParams

- (instancetype)init {
    if (self = [super init]) {
        _scale = 1.0f;
    }
    return self;
}

@end

@implementation GLTFTexture

- (instancetype)initWithSource:(GLTFImage *)source {
    if (self = [super init]) {
        _source = source;
    }
    return self;
}

- (instancetype)init {
    return [self initWithSource:nil];
}

@end
