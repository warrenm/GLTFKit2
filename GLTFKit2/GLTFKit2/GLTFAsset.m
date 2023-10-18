
#import "GLTFAsset.h"
#import "GLTFAssetReader.h"
#import "GLTFLogging.h"
#import "GLTFKTX2Support.h"

#import <ImageIO/ImageIO.h>

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

NSString *const GLTFErrorDomain = @"com.metalbyexample.gltfkit2";

const float LumensPerCandela = 1.0 / (4.0 * M_PI);

static NSString *g_dracoDecompressorClassName = nil;

GLTFAssetLoadingOption const GLTFAssetCreateNormalsIfAbsentKey = @"GLTFAssetCreateNormalsIfAbsentKey";
GLTFAssetLoadingOption const GLTFAssetAssetDirectoryURLKey = @"GLTFAssetAssetDirectoryURLKey";

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

static NSString * _Nullable GLTFInferredMediaTypeForData(NSData *data) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;

    uint8_t pngIdentifier[] = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    if (data.length > 8 && (memcmp(bytes, pngIdentifier, 8) == 0)) {
        return @"image/png";
    }
    uint8_t jpegIdentifier[] = { 0xFF, 0xD8, 0xFF };
    if (data.length > 3 && (memcmp(bytes, jpegIdentifier, 8) == 0)) {
        return @"image/jpeg";
    }
    uint8_t ktx2Identifier[] = { 0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A };
    if (data.length > 12 && (memcmp(bytes, ktx2Identifier, 12) == 0)) {
        return GLTFMediaTypeKTX2;
    }

    return nil;
}

static NSString *_Nullable GLTFCreateUTIForMediaType(NSString *mediaType) {
    // Despite a UTI for KTX2 existing in the system, it's not possible to create it from a file extension
    // or MIME type as of macOS 14.0, even using the newer UTType APIs, so we hack around that here.
    if ([mediaType isEqualToString:GLTFMediaTypeKTX2]) {
        return @"org.khronos.ktx2";
    }
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)mediaType, NULL);
    return (__bridge_transfer NSString *)uti;
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
    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(1);
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
            NSArray *supportedUTIs = (__bridge NSArray *)CGImageSourceCopyTypeIdentifiers();
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
