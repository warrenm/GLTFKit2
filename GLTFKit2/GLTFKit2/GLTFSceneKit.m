
#import "GLTFSceneKit.h"
#import "GLTFLogging.h"
#import "GLTFWorkflowHelper.h"

#import <SceneKit/ModelIO.h>
#import <simd/simd.h>

NSString *const GLTFAssetPropertyKeyCopyright = @"GLTFAssetPropertyKeyCopyright";
NSString *const GLTFAssetPropertyKeyGenerator = @"GLTFAssetPropertyKeyGenerator";
NSString *const GLTFAssetPropertyKeyVersion = @"GLTFAssetPropertyKeyVersion";
NSString *const GLTFAssetPropertyKeyMinVersion = @"GLTFAssetPropertyKeyMinVersion";
NSString *const GLTFAssetPropertyKeyExtensionsUsed = @"GLTFAssetPropertyKeyExtensionsUsed";
NSString *const GLTFAssetPropertyKeyExtensionsRequired = @"GLTFAssetPropertyKeyExtensionsRequired";

static SCNFilterMode GLTFSCNFilterModeForMagFilter(GLTFMagFilter filter) {
    switch (filter) {
        case GLTFMagFilterNearest:
            return SCNFilterModeNearest;
        default:
            return SCNFilterModeLinear;
    }
}

static void GLTFSCNGetFilterModeForMinMipFilter(GLTFMinMipFilter filter,
                                                SCNFilterMode *outMinFilter,
                                                SCNFilterMode *outMipFilter)
{
    if (outMinFilter) {
        switch (filter) {
            case GLTFMinMipFilterNearest:
            case GLTFMinMipFilterNearestNearest:
            case GLTFMinMipFilterNearestLinear:
                *outMinFilter = SCNFilterModeNearest;
                break;
            case GLTFMinMipFilterLinear:
            case GLTFMinMipFilterLinearNearest:
            case GLTFMinMipFilterLinearLinear:
            default:
                *outMinFilter = SCNFilterModeLinear;
                break;
        }
    }
    if (outMipFilter) {
        switch (filter) {
            case GLTFMinMipFilterNearest:
            case GLTFMinMipFilterLinear:
            case GLTFMinMipFilterNearestNearest:
            case GLTFMinMipFilterLinearNearest:
                *outMipFilter = SCNFilterModeNearest;
                break;
            case GLTFMinMipFilterNearestLinear:
            case GLTFMinMipFilterLinearLinear:
            default:
                *outMipFilter = SCNFilterModeLinear;
                break;
        }
    }
}

static SCNWrapMode GLTFSCNWrapModeForMode(GLTFAddressMode mode) {
    switch (mode) {
        case GLTFAddressModeClampToEdge:
            return SCNWrapModeClamp;
        case GLTFAddressModeRepeat:
            return SCNWrapModeRepeat;
        case GLTFAddressModeMirroredRepeat:
            return SCNWrapModeMirror;
    }
}

static NSData *GLTFLineIndexDataForLineLoopIndexData(NSData *_Nonnull lineLoopIndexData,
                                                     int lineLoopIndexCount,
                                                     int bytesPerIndex) {
    if (lineLoopIndexCount < 2) {
        return nil;
    }

    int lineIndexCount = 2 * lineLoopIndexCount;
    size_t bufferSize = lineIndexCount * bytesPerIndex;
    unsigned char *lineIndices = malloc(bufferSize);
    unsigned char *lineIndicesCursor = lineIndices;
    unsigned char *lineLoopIndices = (unsigned char *)lineLoopIndexData.bytes;

    // Create a line from the last index element to the first index element.
    int lastLineIndexOffset = (lineIndexCount - 1) * bytesPerIndex;
    memcpy(lineIndicesCursor, lineLoopIndices, bytesPerIndex);
    memcpy(lineIndicesCursor + lastLineIndexOffset, lineLoopIndices, bytesPerIndex);
    lineIndicesCursor += bytesPerIndex;

    // Duplicate indices in-between to fill in the loop.
    for (int i = 1; i < lineLoopIndexCount; ++i) {
        memcpy(lineIndicesCursor, lineLoopIndices + (i * bytesPerIndex), bytesPerIndex);
        lineIndicesCursor += bytesPerIndex;
        memcpy(lineIndicesCursor, lineLoopIndices + (i * bytesPerIndex), bytesPerIndex);
        lineIndicesCursor += bytesPerIndex;
    }

    return [NSData dataWithBytesNoCopy:lineIndices
                                length:bufferSize
                          freeWhenDone:YES];
}

static NSData *GLTFLineIndexDataForLineStripIndexData(NSData *_Nonnull lineStripIndexData,
                                                      int lineStripIndexCount,
                                                      int bytesPerIndex) {
    if (lineStripIndexCount < 2) {
        return nil;
    }

    int lineIndexCount = 2 * (lineStripIndexCount - 1);
    size_t bufferSize = lineIndexCount * bytesPerIndex;
    unsigned char *lineIndices = malloc(bufferSize);
    unsigned char *lineIndicesCursor = lineIndices;
    unsigned char *lineStripIndices = (unsigned char *)lineStripIndexData.bytes;

    // Place the first and last indices.
    int lastLineIndexOffset = (lineIndexCount - 1) * bytesPerIndex;
    int lastLineStripIndexOffset = (lineStripIndexCount - 1) * bytesPerIndex;
    memcpy(lineIndicesCursor, lineStripIndices, bytesPerIndex);
    memcpy(lineIndicesCursor + lastLineIndexOffset,
           lineStripIndices + lastLineStripIndexOffset,
           bytesPerIndex);
    lineIndicesCursor += bytesPerIndex;

    // Duplicate all indices in-between.
    for (int i = 1; i < lineStripIndexCount; ++i) {
        memcpy(lineIndicesCursor, lineStripIndices + (i * bytesPerIndex), bytesPerIndex);
        lineIndicesCursor += bytesPerIndex;
        memcpy(lineIndicesCursor, lineStripIndices + (i * bytesPerIndex), bytesPerIndex);
        lineIndicesCursor += bytesPerIndex;
    }

    return [NSData dataWithBytesNoCopy:lineIndices
                                length:bufferSize
                          freeWhenDone:YES];
}

static NSData *GLTFTrianglesIndexDataForTriangleFanIndexData(NSData *_Nonnull triangleFanIndexData,
                                                             int triangleFanIndexCount,
                                                             int bytesPerIndex) {
    if (triangleFanIndexCount < 3) {
        return nil;
    }

    int trianglesIndexCount = 3 * (triangleFanIndexCount - 2);
    size_t bufferSize = trianglesIndexCount * bytesPerIndex;
    unsigned char *trianglesIndices = malloc(bufferSize);
    unsigned char *trianglesIndicesCursor = trianglesIndices;
    unsigned char *triangleFanIndices = (unsigned char *)triangleFanIndexData.bytes;

    for (int i = 1; i < triangleFanIndexCount; ++i) {
        memcpy(trianglesIndicesCursor, triangleFanIndices, bytesPerIndex);
        trianglesIndicesCursor += bytesPerIndex;
        memcpy(trianglesIndicesCursor, triangleFanIndices + (i * bytesPerIndex), 2 * bytesPerIndex);
        trianglesIndicesCursor += 2 * bytesPerIndex;
    }

    return [NSData dataWithBytesNoCopy:trianglesIndices
                                length:bufferSize
                          freeWhenDone:YES];
}

static SCNGeometryElement *GLTFSCNGeometryElementForIndexData(NSData *indexData,
                                                              int indexCount,
                                                              int bytesPerIndex,
                                                              GLTFPrimitive *primitive) {
    NSData *finalIndexData = indexData;
    SCNGeometryPrimitiveType primitiveType;
    int primitiveCount;
    switch (primitive.primitiveType) {
        case GLTFPrimitiveTypePoints:
            primitiveType = SCNGeometryPrimitiveTypePoint;
            primitiveCount = indexCount;
            break;
        case GLTFPrimitiveTypeLines:
            primitiveCount = indexCount / 2;
            primitiveType = SCNGeometryPrimitiveTypeLine;
            break;
        case GLTFPrimitiveTypeLineLoop:
            primitiveCount = indexCount;
            primitiveType = SCNGeometryPrimitiveTypeLine;
            if (indexData) {
                finalIndexData = GLTFLineIndexDataForLineLoopIndexData(indexData, indexCount, bytesPerIndex);
            }
            break;
        case GLTFPrimitiveTypeLineStrip:
            primitiveCount = indexCount - 1;
            primitiveType = SCNGeometryPrimitiveTypeLine;
            if (indexData) {
                finalIndexData = GLTFLineIndexDataForLineStripIndexData(indexData, indexCount, bytesPerIndex);
            }
            break;
        case GLTFPrimitiveTypeTriangles:
            primitiveCount = indexCount / 3;
            primitiveType = SCNGeometryPrimitiveTypeTriangles;
            break;
        case GLTFPrimitiveTypeTriangleStrip:
            primitiveCount = indexCount - 2; // TODO: Handle primitive restart?
            primitiveType = SCNGeometryPrimitiveTypeTriangleStrip;
            break;
        case GLTFPrimitiveTypeTriangleFan:
            primitiveCount = indexCount - 2;
            primitiveType = SCNGeometryPrimitiveTypeTriangles;
            if (indexData) {
                finalIndexData = GLTFTrianglesIndexDataForTriangleFanIndexData(indexData, indexCount, bytesPerIndex);
            }
            break;
    }

    if (finalIndexData.bytes == NULL) {
        // Last resort. If we never had index data to begin with, fix up with an array of sequential indices
        bytesPerIndex = 4;
        size_t indexBufferLength = indexCount * bytesPerIndex;
        uint32_t *indexStorage = (uint32_t *)malloc(indexCount * bytesPerIndex);
        for (int i = 0; i < indexCount; ++i) {
            indexStorage[i] = i;
        }
        finalIndexData = [NSData dataWithBytesNoCopy:indexStorage length:indexBufferLength freeWhenDone:YES];
    }

    return [SCNGeometryElement geometryElementWithData:finalIndexData
                                         primitiveType:primitiveType
                                        primitiveCount:primitiveCount
                                         bytesPerIndex:bytesPerIndex];
}

static NSString *GLTFSCNGeometrySourceSemanticForSemantic(NSString *name) {
    if ([name isEqualToString:GLTFAttributeSemanticPosition]) {
        return SCNGeometrySourceSemanticVertex;
    } else if ([name isEqualToString:GLTFAttributeSemanticNormal]) {
        return SCNGeometrySourceSemanticNormal;
    } else if ([name isEqualToString:GLTFAttributeSemanticTangent]) {
        return SCNGeometrySourceSemanticTangent;
    } else if ([name hasPrefix:@"TEXCOORD_"]) {
        return SCNGeometrySourceSemanticTexcoord;
    } else if ([name hasPrefix:@"COLOR_"]) {
        return SCNGeometrySourceSemanticColor;
    } else if ([name hasPrefix:@"JOINTS_"]) {
        return SCNGeometrySourceSemanticBoneIndices;
    } else if ([name hasPrefix:@"WEIGHTS_"]) {
        return SCNGeometrySourceSemanticBoneWeights;
    }
    return name;
}

static void GLTFConfigureSCNMaterialProperty(SCNMaterialProperty *property, GLTFTextureParams *textureParams) {
    static GLTFTextureSampler *defaultSampler = nil;
    if (defaultSampler == nil) {
        defaultSampler = [GLTFTextureSampler new];
        defaultSampler.magFilter = GLTFMagFilterLinear;
        defaultSampler.minMipFilter = GLTFMinMipFilterLinearLinear;
        defaultSampler.wrapS = GLTFAddressModeRepeat;
        defaultSampler.wrapT = GLTFAddressModeRepeat;
    }
    GLTFTextureSampler *sampler = textureParams.texture.sampler ?: defaultSampler;
    property.intensity = textureParams.scale;
    property.magnificationFilter = GLTFSCNFilterModeForMagFilter(sampler.magFilter);
    SCNFilterMode minFilter, mipFilter;
    GLTFSCNGetFilterModeForMinMipFilter(sampler.minMipFilter, &minFilter, &mipFilter);
    property.minificationFilter = minFilter;
    property.mipFilter = mipFilter;
    property.wrapS = GLTFSCNWrapModeForMode(sampler.wrapS);
    property.wrapT = GLTFSCNWrapModeForMode(sampler.wrapT);
    property.mappingChannel = textureParams.texCoord;
    if (textureParams.transform) {
        property.contentsTransform = SCNMatrix4FromMat4(textureParams.transform.matrix);
        if (textureParams.transform.hasTexCoord) {
            property.mappingChannel = textureParams.transform.texCoord;
        }
    }
}

static NSData *GLTFPackedUInt16DataFromPackedUInt8(UInt8 *bytes, size_t count) {
    size_t bufferSize = sizeof(UInt16) * count;
    UInt16 *shorts = malloc(bufferSize);
    // This is begging to be parallelized. Can this be done with Accelerate?
    for (int i = 0; i < count; ++i) {
        shorts[i] = (UInt16)bytes[i];
    }
    return [NSData dataWithBytesNoCopy:shorts length:bufferSize freeWhenDone:YES];
}

static NSData *GLTFSCNPackedDataForAccessor(GLTFAccessor *accessor) {
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
        assert(accessor.sparse.indexComponentType == GLTFComponentTypeUnsignedShort ||
               accessor.sparse.indexComponentType == GLTFComponentTypeUnsignedInt);
        const void *baseSparseIndexBufferViewPtr = accessor.sparse.indices.buffer.data.bytes +
                                                   accessor.sparse.indices.offset;
        const void *baseSparseIndexAccessorPtr = baseSparseIndexBufferViewPtr + accessor.sparse.indexOffset;

        const void *baseValueBufferViewPtr = accessor.sparse.values.buffer.data.bytes + accessor.sparse.values.offset;
        const void *baseSrcPtr = baseValueBufferViewPtr + accessor.sparse.valueOffset;
        const size_t srcValueStride = accessor.sparse.values.stride ?: elementSize;

        void *baseDestPtr = bytes;

        if (accessor.sparse.indexComponentType == GLTFComponentTypeUnsignedShort) {
            const UInt16 *sparseIndices = (UInt16 *)baseSparseIndexAccessorPtr;
            for (int i = 0; i < accessor.sparse.count; ++i) {
                UInt16 sparseIndex = sparseIndices[i];
                memcpy(baseDestPtr + sparseIndex * elementSize, baseSrcPtr + (i * srcValueStride), elementSize);
            }
        } else if (accessor.sparse.indexComponentType == GLTFComponentTypeUnsignedInt) {
            const UInt32 *sparseIndices = (UInt32 *)baseSparseIndexAccessorPtr;
            for (int i = 0; i < accessor.sparse.count; ++i) {
                UInt32 sparseIndex = sparseIndices[i];
                memcpy(baseDestPtr + sparseIndex * elementSize, baseSrcPtr + (i * srcValueStride), elementSize);
            }
        }
    }
    return [NSData dataWithBytesNoCopy:bytes length:bufferLength freeWhenDone:YES];
}

static NSArray<NSNumber *> *GLTFKeyTimeArrayForAccessor(GLTFAccessor *accessor, NSTimeInterval maxKeyTime) {
    // TODO: This is actually not assured by the spec. We should convert from normalized int types when necessary
    assert(accessor.componentType == GLTFComponentTypeFloat);
    assert(accessor.dimension == GLTFValueDimensionScalar);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:accessor.count];
    const void *bufferViewBaseAddr = accessor.bufferView.buffer.data.bytes + accessor.bufferView.offset;
    float scale = (maxKeyTime > 0) ? (1.0f / maxKeyTime) : 1.0f;
    for (int i = 0; i < accessor.count; ++i) {
        const float *x = bufferViewBaseAddr + (i * (accessor.bufferView.stride ?: sizeof(float))) + accessor.offset;
        NSNumber *value = @(x[0] * scale);
        [values addObject:value];
    }
    return values;
}

static SCNGeometrySource *GLTFSCNGeometrySourceForAccessor(GLTFAccessor *accessor, NSString *semanticName) {
    size_t bytesPerComponent = GLTFBytesPerComponentForComponentType(accessor.componentType);
    size_t componentCount = GLTFComponentCountForDimension(accessor.dimension);
    size_t elementSize = bytesPerComponent * componentCount;
    NSData *attrData = GLTFSCNPackedDataForAccessor(accessor);

    // Ensure linear sum of weights is equal to 1; this is required by the spec,
    // and SceneKit relies on this invariant as of iOS 12 and macOS Mojave.
    // TODO: Support multiple sets of weights, assuring that sum of weights across
    // all weight sets is 1.
    if ([semanticName isEqualToString:@"WEIGHTS_0"]) {
        assert(accessor.componentType == GLTFComponentTypeFloat && accessor.dimension == GLTFValueDimensionVector4 &&
                 "Accessor for joint weights must be of float4 type; other data types are not currently supported");
        for (int i = 0; i < accessor.count; ++i) {
            float *weights = (float *)(attrData.bytes + i * elementSize);
            float sum = weights[0] + weights[1] + weights[2] + weights[3];
            if (sum != 1.0f) {
                weights[0] /= sum;
                weights[1] /= sum;
                weights[2] /= sum;
                weights[3] /= sum;
            }
        }
    }

    return [SCNGeometrySource geometrySourceWithData:attrData
                                            semantic:GLTFSCNGeometrySourceSemanticForSemantic(semanticName)
                                         vectorCount:accessor.count
                                     floatComponents:(accessor.componentType == GLTFComponentTypeFloat)
                                 componentsPerVector:componentCount
                                   bytesPerComponent:bytesPerComponent
                                          dataOffset:0
                                          dataStride:elementSize];
}

static NSArray<NSValue *> *GLTFSCNVector3ArrayForAccessor(GLTFAccessor *accessor) {
    // TODO: This is actually not assured by the spec. We should convert from normalized int types when necessary
    assert(accessor.componentType == GLTFComponentTypeFloat);
    assert(accessor.dimension == GLTFValueDimensionVector3);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:accessor.count];
    const void *bufferViewBaseAddr = accessor.bufferView.buffer.data.bytes + accessor.bufferView.offset;
    const size_t elementSize = sizeof(float) * 3;
    for (int i = 0; i < accessor.count; ++i) {
        const float *xyz = bufferViewBaseAddr + (i * (accessor.bufferView.stride ?: elementSize)) + accessor.offset;
        NSValue *value = [NSValue valueWithSCNVector3:SCNVector3Make(xyz[0], xyz[1], xyz[2])];
        [values addObject:value];
    }
    return values;
}

static NSArray<NSValue *> *GLTFSCNVector4ArrayForAccessor(GLTFAccessor *accessor) {
    // TODO: This is actually not assured by the spec. We should convert from normalized int types when necessary
    assert(accessor.componentType == GLTFComponentTypeFloat);
    assert(accessor.dimension == GLTFValueDimensionVector4);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:accessor.count];
    const void *bufferViewBaseAddr = accessor.bufferView.buffer.data.bytes + accessor.bufferView.offset;
    const size_t elementSize = sizeof(float) * 4;
    for (int i = 0; i < accessor.count; ++i) {
        const float *xyzw = bufferViewBaseAddr + (i * (accessor.bufferView.stride ?: elementSize)) + accessor.offset;
        NSValue *value = [NSValue valueWithSCNVector4:SCNVector4Make(xyzw[0], xyzw[1], xyzw[2], xyzw[3])];
        [values addObject:value];
    }
    return values;
}

static NSArray<NSArray<NSNumber *> *> *GLTFWeightsArraysForAccessor(GLTFAccessor *accessor, NSUInteger targetCount) {
    assert(accessor.componentType == GLTFComponentTypeFloat);
    assert(accessor.dimension == GLTFValueDimensionScalar);
    size_t keyframeCount = accessor.count / targetCount;
    NSMutableArray<NSMutableArray *> *weights = [NSMutableArray arrayWithCapacity:keyframeCount];
    for (int t = 0; t < targetCount; ++t) {
        [weights addObject:[NSMutableArray arrayWithCapacity:targetCount]];
    }
    const void *bufferViewBaseAddr = accessor.bufferView.buffer.data.bytes + accessor.bufferView.offset;
    const float *values = (float *)(bufferViewBaseAddr + accessor.offset);
    for (int k = 0; k < keyframeCount; ++k) {
        for (int t = 0; t < targetCount; ++t) {
            [weights[t] addObject:@(values[k * targetCount + t])];
        }
    }
    return weights;
}

static NSArray<NSValue *> *GLTFSCNMatrix4ArrayFromAccessor(GLTFAccessor *accessor) {
    assert(accessor.componentType == GLTFComponentTypeFloat);
    assert(accessor.dimension == GLTFValueDimensionMatrix4);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:accessor.count];
    const void *bufferViewBaseAddr = accessor.bufferView.buffer.data.bytes + accessor.bufferView.offset;
    const size_t elementSize = sizeof(float) * 16;
    for (int i = 0; i < accessor.count; ++i) {
        const float *M = bufferViewBaseAddr + (i * (accessor.bufferView.stride ?: elementSize)) + accessor.offset;
        SCNMatrix4 m;
        m.m11 = M[ 0]; m.m12 = M[ 1]; m.m13 = M[ 2]; m.m14 = M[ 3];
        m.m21 = M[ 4]; m.m22 = M[ 5]; m.m23 = M[ 6]; m.m24 = M[ 7];
        m.m31 = M[ 8]; m.m32 = M[ 9]; m.m33 = M[10]; m.m34 = M[11];
        m.m41 = M[12]; m.m42 = M[13]; m.m43 = M[14]; m.m44 = M[15];
        NSValue *value = [NSValue valueWithSCNMatrix4:m];
        [values addObject:value];
    }
    return values;
}

static float GLTFLuminanceFromRGBA(simd_float4 rgba) {
    return 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2];
}

@implementation GLTFSCNAnimation
@end

@implementation SCNScene (GLTFSceneKit)

+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset {
    GLTFSCNSceneSource *source = [[GLTFSCNSceneSource alloc] initWithAsset:asset];
    return source.defaultScene;
}

+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset applyingMaterialVariant:(GLTFMaterialVariant *)variant {
    GLTFSCNSceneSource *source = [[GLTFSCNSceneSource alloc] initWithAsset:asset applyingMaterialVariant:variant];
    return source.defaultScene;
}

@end

@interface GLTFSCNSceneSource () {
    NSMutableDictionary<NSUUID *, id> *_materialPropertyContentsCache;
}
@property (nonatomic, copy) NSDictionary *properties;
@property (nonatomic, copy) NSArray<SCNMaterial *> *materials;
@property (nonatomic, copy) NSArray<SCNLight *> *lights;
@property (nonatomic, copy) NSArray<SCNCamera *> *cameras;
@property (nonatomic, copy) NSArray<SCNNode *> *nodes;
@property (nonatomic, copy) NSArray<SCNGeometry *> *geometries;
@property (nonatomic, copy) NSArray<SCNSkinner *> *skinners;
@property (nonatomic, copy) NSArray<SCNMorpher *> *morphers;
@property (nonatomic, copy) NSArray<SCNScene *> *scenes;
@property (nonatomic, copy) NSArray<GLTFSCNAnimation *> *animations;
@property (nonatomic, strong) SCNScene *defaultScene;
@property (nonatomic, strong) GLTFAsset *asset;
@property (nonatomic, nullable, strong) GLTFMaterialVariant *activeMaterialVariant;
@end

@implementation GLTFSCNSceneSource

- (instancetype)initWithAsset:(GLTFAsset *)asset {
    if (self = [super init]) {
        _asset = asset;
        [self convertAsset];
    }
    return self;
}

- (instancetype)initWithAsset:(GLTFAsset *)asset applyingMaterialVariant:(GLTFMaterialVariant *)variant {
    if (self = [super init]) {
        _asset = asset;
        _activeMaterialVariant = variant;
        [self convertAsset];
    }
    return self;
}

- (nullable id)propertyForKey:(NSString *)key {
    return _properties[key];
}

- (nullable id)materialPropertyContentsForTexture:(GLTFTexture *)texture {
    if (_materialPropertyContentsCache[texture.identifier] != nil) {
        return _materialPropertyContentsCache[texture.identifier];
    }
#ifdef GLTF_BUILD_WITH_KTX2
    if (texture.basisUSource) {
        id<MTLTexture> metalTexture = [texture.basisUSource newTextureWithDevice:MTLCreateSystemDefaultDevice()];
        _materialPropertyContentsCache[texture.identifier] = metalTexture;
        return metalTexture;
    }
#endif
    CGImageRef cgImage = [texture.source newCGImage];
    _materialPropertyContentsCache[texture.identifier] = (__bridge_transfer id)cgImage;
    return (__bridge id)cgImage;
}

- (void)convertAsset {
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    properties[GLTFAssetPropertyKeyCopyright] = self.asset.copyright;
    properties[GLTFAssetPropertyKeyGenerator] = self.asset.generator;
    properties[GLTFAssetPropertyKeyVersion] = self.asset.version;
    properties[GLTFAssetPropertyKeyMinVersion] = self.asset.minVersion;
    properties[GLTFAssetPropertyKeyExtensionsUsed] = self.asset.extensionsUsed;
    properties[GLTFAssetPropertyKeyExtensionsRequired] = self.asset.extensionsRequired;
    _properties = properties;

    _materialPropertyContentsCache = [NSMutableDictionary dictionary];

    CGColorSpaceRef colorSpaceLinearSRGB = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);

    SCNMaterial *defaultMaterial = [SCNMaterial material];
    defaultMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    defaultMaterial.locksAmbientWithDiffuse = YES;
    CGFloat defaultBaseColorFactor[] = { 1.0, 1.0, 1.0, 1.0 };
    defaultMaterial.diffuse.contents = (__bridge_transfer id)CGColorCreate(colorSpaceLinearSRGB, &defaultBaseColorFactor[0]);
    defaultMaterial.metalness.contents = @(1.0);
    defaultMaterial.roughness.contents = @(1.0);

    NSMutableDictionary <NSUUID *, SCNMaterial *> *materialsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMaterial *material in self.asset.materials) {
        SCNMaterial *scnMaterial = [SCNMaterial new];
        scnMaterial.locksAmbientWithDiffuse = YES;
        if (material.isUnlit) {
            scnMaterial.lightingModelName = SCNLightingModelConstant;
        } else if (material.metallicRoughness || material.specularGlossiness) {
            scnMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
        } else {
            scnMaterial.lightingModelName = SCNLightingModelBlinn;
        }
        if (material.metallicRoughness) {
            //TODO: How to represent base color/emissive factor, etc., when textures are present?
            if (material.metallicRoughness.baseColorTexture) {
                GLTFTextureParams *baseColorTexture = material.metallicRoughness.baseColorTexture;
                SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
                baseColorProperty.contents = [self materialPropertyContentsForTexture:baseColorTexture.texture];
                GLTFConfigureSCNMaterialProperty(baseColorProperty, baseColorTexture);
                simd_float4 rgba = material.metallicRoughness.baseColorFactor;
                // This is a lossy transformation because we only have a scalar intensity,
                // instead of proper support for color factors.
                baseColorProperty.intensity = GLTFLuminanceFromRGBA(rgba);
            } else {
                SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
                simd_float4 rgba = material.metallicRoughness.baseColorFactor;
                CGFloat rgbad[] = { rgba[0], rgba[1], rgba[2], rgba[3] };
                baseColorProperty.contents = (__bridge_transfer id)CGColorCreate(colorSpaceLinearSRGB, rgbad);
            }
            if (material.metallicRoughness.metallicRoughnessTexture) {
                GLTFTextureParams *metallicRoughnessTexture = material.metallicRoughness.metallicRoughnessTexture;
                id metallicRoughnessImage = [self materialPropertyContentsForTexture:metallicRoughnessTexture.texture];

                SCNMaterialProperty *metallicProperty = scnMaterial.metalness;
                metallicProperty.contents = metallicRoughnessImage;
                GLTFConfigureSCNMaterialProperty(metallicProperty, metallicRoughnessTexture);
                metallicProperty.textureComponents = SCNColorMaskBlue;
                metallicProperty.intensity = material.metallicRoughness.metallicFactor;

                SCNMaterialProperty *roughnessProperty = scnMaterial.roughness;
                roughnessProperty.contents = metallicRoughnessImage;
                GLTFConfigureSCNMaterialProperty(roughnessProperty, metallicRoughnessTexture);
                roughnessProperty.textureComponents = SCNColorMaskGreen;
                roughnessProperty.intensity = material.metallicRoughness.roughnessFactor;
            } else {
                SCNMaterialProperty *metallicProperty = scnMaterial.metalness;
                metallicProperty.contents = @(material.metallicRoughness.metallicFactor);
                SCNMaterialProperty *roughnessProperty = scnMaterial.roughness;
                roughnessProperty.contents = @(material.metallicRoughness.roughnessFactor);
            }
        } else if (material.specularGlossiness) {
            GLTFWorkflowHelper *workflowConverter = [[GLTFWorkflowHelper alloc] initWithSpecularGlossiness:material.specularGlossiness];
            if (workflowConverter.baseColorTexture) {
                GLTFTextureParams *baseColorTexture = workflowConverter.baseColorTexture;
                SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
                baseColorProperty.contents = (__bridge_transfer id)[workflowConverter.baseColorTexture.texture.source newCGImage];
                GLTFConfigureSCNMaterialProperty(baseColorProperty, baseColorTexture);
                baseColorProperty.intensity = GLTFLuminanceFromRGBA(workflowConverter.baseColorFactor);
            } else {
                SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
                simd_float4 rgba = workflowConverter.baseColorFactor;
                CGFloat rgbad[] = { rgba[0], rgba[1], rgba[2], rgba[3] };
                baseColorProperty.contents = (__bridge_transfer id)CGColorCreate(colorSpaceLinearSRGB, rgbad);
            }
            if (workflowConverter.metallicRoughnessTexture) {
                GLTFTextureParams *metallicRoughnessTexture = workflowConverter.metallicRoughnessTexture;
                id metallicRoughnessImage = (__bridge_transfer id)[workflowConverter.metallicRoughnessTexture.texture.source newCGImage];

                SCNMaterialProperty *metallicProperty = scnMaterial.metalness;
                metallicProperty.contents = metallicRoughnessImage;
                GLTFConfigureSCNMaterialProperty(metallicProperty, metallicRoughnessTexture);
                metallicProperty.textureComponents = SCNColorMaskBlue;

                SCNMaterialProperty *roughnessProperty = scnMaterial.roughness;
                roughnessProperty.contents = metallicRoughnessImage;
                GLTFConfigureSCNMaterialProperty(roughnessProperty, metallicRoughnessTexture);
                roughnessProperty.textureComponents = SCNColorMaskGreen;
            } else {
                SCNMaterialProperty *metallicProperty = scnMaterial.metalness;
                metallicProperty.contents = @(workflowConverter.metallicFactor);
                SCNMaterialProperty *roughnessProperty = scnMaterial.roughness;
                roughnessProperty.contents = @(workflowConverter.roughnessFactor);
            }
        }
        if (material.normalTexture) {
            GLTFTextureParams *normalTexture = material.normalTexture;
            SCNMaterialProperty *normalProperty = scnMaterial.normal;
            normalProperty.contents = [self materialPropertyContentsForTexture:normalTexture.texture];
            GLTFConfigureSCNMaterialProperty(normalProperty, normalTexture);
        }
        if (material.emissive.emissiveTexture) {
            GLTFTextureParams *emissiveTexture = material.emissive.emissiveTexture;
            SCNMaterialProperty *emissiveProperty = scnMaterial.emission;
            emissiveProperty.contents = [self materialPropertyContentsForTexture:emissiveTexture.texture];
            // TODO: How to support emissive.emissiveStrength?
            GLTFConfigureSCNMaterialProperty(emissiveProperty, emissiveTexture);
        } else {
            SCNMaterialProperty *emissiveProperty = scnMaterial.emission;
            simd_float3 rgb = material.emissive.emissiveFactor;
            // TODO: Multiply in emissive.emissiveStrength?
            CGFloat rgbad[] = { rgb[0], rgb[1], rgb[2], 1.0 };
            emissiveProperty.contents = (__bridge_transfer id)CGColorCreate(colorSpaceLinearSRGB, &rgbad[0]);
        }
        if (material.occlusionTexture) {
            GLTFTextureParams *occlusionTexture = material.occlusionTexture;
            SCNMaterialProperty *occlusionProperty = scnMaterial.ambientOcclusion;
            occlusionProperty.contents = [self materialPropertyContentsForTexture:occlusionTexture.texture];
            GLTFConfigureSCNMaterialProperty(occlusionProperty, occlusionTexture);
        }
        if (material.clearcoat) {
            if (@available(macOS 10.15, iOS 13.0, *)) {
                if (material.clearcoat.clearcoatTexture) {
                    GLTFTextureParams *clearcoatTexture = material.clearcoat.clearcoatTexture;
                    SCNMaterialProperty *clearcoatProperty = scnMaterial.clearCoat;
                    clearcoatProperty.contents = [self materialPropertyContentsForTexture:clearcoatTexture.texture];
                    GLTFConfigureSCNMaterialProperty(clearcoatProperty, material.clearcoat.clearcoatTexture);
                } else {
                    scnMaterial.clearCoat.contents = @(material.clearcoat.clearcoatFactor);
                }
                if (material.clearcoat.clearcoatRoughnessTexture) {
                    GLTFTextureParams *clearcoatRoughnessTexture = material.clearcoat.clearcoatRoughnessTexture;
                    SCNMaterialProperty *clearcoatRoughnessProperty = scnMaterial.clearCoatRoughness;
                    clearcoatRoughnessProperty.contents = [self materialPropertyContentsForTexture:clearcoatRoughnessTexture.texture];
                    GLTFConfigureSCNMaterialProperty(clearcoatRoughnessProperty, material.clearcoat.clearcoatRoughnessTexture);
                } else {
                    scnMaterial.clearCoatRoughness.contents = @(material.clearcoat.clearcoatRoughnessFactor);
                }
                if (material.clearcoat.clearcoatNormalTexture) {
                    GLTFTextureParams *clearcoatNormalTexture = material.clearcoat.clearcoatNormalTexture;
                    SCNMaterialProperty *clearcoatNormalProperty = scnMaterial.clearCoatNormal;
                    clearcoatNormalProperty.contents = [self materialPropertyContentsForTexture:clearcoatNormalTexture.texture];
                    GLTFConfigureSCNMaterialProperty(clearcoatNormalProperty, material.clearcoat.clearcoatNormalTexture);
                }
            }
        }
        scnMaterial.doubleSided = material.isDoubleSided;
        scnMaterial.blendMode = (material.alphaMode == GLTFAlphaModeBlend) ? SCNBlendModeAlpha : SCNBlendModeReplace;
        scnMaterial.transparencyMode = SCNTransparencyModeDefault;
        NSString *unpremulSurfaceDiffuse = [NSString stringWithFormat:@"if (_surface.diffuse.a > 0.0f) {\n\t_surface.diffuse.rgb /= _surface.diffuse.a;\n}"];
        if (material.alphaMode == GLTFAlphaModeMask) {
            NSString *alphaTestFragment = [NSString stringWithFormat:@"if (_output.color.a < %f) {\n\tdiscard_fragment();\n}", material.alphaCutoff];
            scnMaterial.shaderModifiers = @{ SCNShaderModifierEntryPointSurface : unpremulSurfaceDiffuse,
                                             SCNShaderModifierEntryPointFragment : alphaTestFragment };
        } else if (material.alphaMode == GLTFAlphaModeOpaque) {
            scnMaterial.shaderModifiers = @{ SCNShaderModifierEntryPointSurface : unpremulSurfaceDiffuse };
        }
        materialsForIdentifiers[material.identifier] = scnMaterial;
    }

    NSMutableDictionary <NSUUID *, SCNGeometry *> *geometryForIdentifiers = [NSMutableDictionary dictionary];
    NSMutableDictionary <NSUUID *, SCNGeometryElement *> *geometryElementForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMesh *mesh in self.asset.meshes) {
        for (GLTFPrimitive *primitive in mesh.primitives) {
            int vertexCount = 0;
            GLTFAccessor *positionAccessor = primitive.attributes[GLTFAttributeSemanticPosition];
            if (positionAccessor != nil) {
                vertexCount = (int)positionAccessor.count;
            }
            SCNMaterial *material = materialsForIdentifiers[primitive.material.identifier];
            if (self.activeMaterialVariant != nil) {
                GLTFMaterial *materialOverride = [primitive effectiveMaterialForVariant:self.activeMaterialVariant];
                if (materialOverride) {
                    material = materialsForIdentifiers[materialOverride.identifier];
                }
            }
            NSData *indexData = nil;
            int indexSize = 1;
            int indexCount = vertexCount; // If we're not indexed (determined below), our "index" count is our vertex count
            if (primitive.indices) {
                GLTFAccessor *indexAccessor = primitive.indices;
                GLTFBufferView *indexBufferView = indexAccessor.bufferView;
                assert(indexBufferView.stride == 0 || indexBufferView.stride == indexSize);
                GLTFBuffer *indexBuffer = indexBufferView.buffer;
                indexCount = (int)primitive.indices.count;
                if((indexAccessor.componentType == GLTFComponentTypeUnsignedShort) ||
                   (indexAccessor.componentType == GLTFComponentTypeUnsignedInt))
                {
                    indexSize = indexAccessor.componentType == GLTFComponentTypeUnsignedInt ? sizeof(UInt32) : sizeof(UInt16);
                    indexData = [NSData dataWithBytesNoCopy:(void *)indexBuffer.data.bytes + indexBufferView.offset + indexAccessor.offset
                                                     length:indexCount * indexSize
                                               freeWhenDone:NO];
                }
                else
                {
                    assert(indexAccessor.componentType == GLTFComponentTypeUnsignedByte);
                    // We don't directly support 8-bit indices, but converting them is simple enough
                    indexSize = sizeof(UInt16);
                    void *bufferViewBaseAddr = (void *)indexBuffer.data.bytes + indexBufferView.offset;
                    indexData = GLTFPackedUInt16DataFromPackedUInt8(bufferViewBaseAddr + indexAccessor.offset, indexCount);
                }
            }
            SCNGeometryElement *element = GLTFSCNGeometryElementForIndexData(indexData, indexCount, indexSize, primitive);
            geometryElementForIdentifiers[primitive.identifier] = element;

            NSMutableArray *geometrySources = [NSMutableArray arrayWithCapacity:primitive.attributes.count];
            for (NSString *key in primitive.attributes.allKeys) {
                GLTFAccessor *attrAccessor = primitive.attributes[key];
                // TODO: Retopologize geometry source if geometry element's data is `nil`.
                // For primitive types not supported by SceneKit (line loops, line strips, triangle
                // fans), we retopologize the primitive's indices. However, if they aren't present,
                // we need to adjust the vertex data.
                [geometrySources addObject:GLTFSCNGeometrySourceForAccessor(attrAccessor, key)];
            }

            SCNGeometry *geometry = [SCNGeometry geometryWithSources:geometrySources elements:@[element]];
            geometry.name = mesh.name;
            geometry.firstMaterial = material ?: defaultMaterial;
            geometryForIdentifiers[primitive.identifier] = geometry;
        }
    }

    NSMutableDictionary<NSUUID *, SCNCamera *> *camerasForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFCamera *camera in self.asset.cameras) {
        SCNCamera *scnCamera = [SCNCamera camera];
        scnCamera.name = camera.name;
        if (camera.orthographic) {
            scnCamera.usesOrthographicProjection = YES;
            // This is a lossy transformation.
            scnCamera.orthographicScale = MAX(camera.orthographic.xMag, camera.orthographic.yMag);
        } else {
            scnCamera.usesOrthographicProjection = NO;
            scnCamera.fieldOfView = GLTFDegFromRad(camera.perspective.yFOV);
            scnCamera.projectionDirection = SCNCameraProjectionDirectionVertical;
            // No property for aspect ratio, so we drop it here.
        }
        scnCamera.zNear = camera.zNear;
        scnCamera.zFar = camera.zFar;
        camerasForIdentifiers[camera.identifier] = scnCamera;
    }

    NSMutableDictionary<NSUUID *, SCNLight *> *lightsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFLight *light in self.asset.lights) {
        SCNLight *scnLight = [SCNLight light];
        scnLight.name = light.name;
        CGFloat rgba[] = { light.color[0], light.color[1], light.color[2], 1.0 };
        scnLight.color = (__bridge_transfer id)CGColorCreate(colorSpaceLinearSRGB, rgba);
        switch (light.type) {
            case GLTFLightTypeDirectional:
                scnLight.intensity = light.intensity; // TODO: Convert from lux to lumens? How?
                break;
            case GLTFLightTypePoint:
                scnLight.intensity = light.intensity * LumensPerCandela;
                break;
            case GLTFLightTypeSpot:
                scnLight.intensity = light.intensity * LumensPerCandela;
                scnLight.spotInnerAngle = GLTFDegFromRad(light.innerConeAngle);
                scnLight.spotOuterAngle = GLTFDegFromRad(light.outerConeAngle);
                break;
        }
        if (light.type != GLTFLightTypeDirectional) {
            if (light.range > 0.0) {
                scnLight.attenuationStartDistance = 1e-5;
                scnLight.attenuationEndDistance = light.range;
                scnLight.attenuationFalloffExponent = 2.0;
            }
        }
        scnLight.castsShadow = YES;
        lightsForIdentifiers[light.identifier] = scnLight;
    }

    NSMutableSet *legalizedNodeNames = [NSMutableSet set];
    // Legalize and unique GLTF node names. Node names should not contain periods in SceneKit because
    // Cocoa key paths are period-separated. Node names should also ideally be unique so that there
    // is no ambiguity in name-based animation key paths (e.g. "/Node.position")
    for (GLTFNode *node in self.asset.nodes) {
        NSString *legalizedName = [node.name stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        if ([legalizedNodeNames containsObject:legalizedName]) {
            NSInteger uniqueIndex = 1;
            NSString *uniquedName = legalizedName;
            do {
                uniquedName = [NSString stringWithFormat:@"%@_%d", legalizedName, (int)uniqueIndex];
                ++uniqueIndex;
            } while ([legalizedNodeNames containsObject:uniquedName]);
            legalizedName = uniquedName;
        }
        [legalizedNodeNames addObject:legalizedName];
        node.name = legalizedName;
    }

    NSMutableDictionary<NSUUID *, SCNNode *> *nodesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFNode *node in self.asset.nodes) {
        SCNNode *scnNode = [SCNNode node];
        scnNode.name = node.name;
        scnNode.simdTransform = node.matrix;
        nodesForIdentifiers[node.identifier] = scnNode;
    }

    for (GLTFNode *node in self.asset.nodes) {
        SCNNode *scnNode = nodesForIdentifiers[node.identifier];
        for (GLTFNode *childNode in node.childNodes) {
            SCNNode *scnChildNode = nodesForIdentifiers[childNode.identifier];
            [scnNode addChildNode:scnChildNode];
        }
    }

    for (GLTFNode *node in self.asset.nodes) {
        SCNNode *scnNode = nodesForIdentifiers[node.identifier];

        if (node.camera) {
            scnNode.camera = camerasForIdentifiers[node.camera.identifier];
        }
        if (node.light) {
            scnNode.light = lightsForIdentifiers[node.light.identifier];
        }

        // This collection holds the nodes to which any skin on this node should be applied,
        // since we don't have a one-to-one mapping from nodes to meshes. It's also used to
        // apply morph targets to the correct primitives.
        NSMutableArray<SCNNode *> *geometryNodes = [NSMutableArray array];

        if (node.mesh) {
            NSArray<GLTFPrimitive *> *primitives = node.mesh.primitives;
            if (primitives.count == 1) {
                [geometryNodes addObject:scnNode];
            } else {
                for (int i = 0; i < primitives.count; ++i) {
                    SCNNode *geometryNode = [SCNNode node];
                    geometryNode.name = [NSString stringWithFormat:@"%@_primitive%02d", node.name, i];
                    [scnNode addChildNode:geometryNode];
                    [geometryNodes addObject:geometryNode];
                }
            }

            for (int i = 0; i < primitives.count; ++i) {
                GLTFPrimitive *primitive = primitives[i];
                SCNNode *geometryNode = geometryNodes[i];
                geometryNode.geometry = geometryForIdentifiers[primitive.identifier];

                if (primitive.targets.count > 0) {
                    // If the base mesh doesn't contain normals, use Model I/O to generate them
                    if ([geometryNode.geometry geometrySourcesForSemantic:SCNGeometrySourceSemanticNormal].count == 0) {
                        MDLMesh *mdlMesh = [MDLMesh meshWithSCNGeometry:geometryNode.geometry];
                        [mdlMesh addNormalsWithAttributeNamed:MDLVertexAttributeNormal creaseThreshold:0.0];
                        geometryNode.geometry = [SCNGeometry geometryWithMDLMesh:mdlMesh];
                    }

                    SCNGeometryElement *element = geometryElementForIdentifiers[primitive.identifier];
                    NSMutableArray<SCNGeometry *> *morphGeometries = [NSMutableArray array];
                    int index = 0;
                    for (GLTFMorphTarget *target in primitive.targets) {
                        // We assemble the list of geometry sources for each morph target by first
                        // shallow-copying the sources of the base mesh, then replacing each source
                        // as we encounter a corresponding key in the target's key list. In this way
                        // we always have a 1:1 correspondence between base and target sources.
                        NSMutableArray<SCNGeometrySource *> *sources = [geometryNode.geometry.geometrySources mutableCopy];
                        for (NSString *key in target.allKeys) {
                            GLTFAccessor *targetAccessor = target[key];
                            __block NSInteger replacementIndex = NSNotFound;
                            [sources enumerateObjectsUsingBlock:^(SCNGeometrySource *source, NSUInteger idx, BOOL * stop) {
                                if ([source.semantic isEqualToString:GLTFSCNGeometrySourceSemanticForSemantic(key)]) {
                                    replacementIndex = idx;
                                    *stop = YES;
                                }
                            }];
                            if (replacementIndex != NSNotFound) {
                                [sources replaceObjectAtIndex:replacementIndex
                                                   withObject:GLTFSCNGeometrySourceForAccessor(targetAccessor, key)];
                            } else {
                                // Targeting a source that doesn't exist in the base mesh. This shouldn't happen.
                                [sources addObject:GLTFSCNGeometrySourceForAccessor(targetAccessor, key)];
                            }

                        }
                        SCNGeometry *geom = [SCNGeometry geometryWithSources:sources
                                                                    elements:@[element]];

                        // If after creating the target geometry we don't have normals, use Model I/O to generate them
                        if ([geom geometrySourcesForSemantic:SCNGeometrySourceSemanticNormal].count == 0) {
                            MDLMesh *mdlMesh = [MDLMesh meshWithSCNGeometry:geom];
                            [mdlMesh addNormalsWithAttributeNamed:MDLVertexAttributeNormal creaseThreshold:0.0];
                            geom = [SCNGeometry geometryWithMDLMesh:mdlMesh];
                        }

                        if (index < node.mesh.targetNames.count) {
                            geom.name = node.mesh.targetNames[index];
                        }
                        index++;
                        [morphGeometries addObject:geom];
                    }

                    SCNMorpher *scnMorpher = [SCNMorpher new];
                    scnMorpher.calculationMode = SCNMorpherCalculationModeAdditive;
                    scnMorpher.unifiesNormals = YES;
                    scnMorpher.targets = morphGeometries;
                    scnMorpher.weights = node.weights ?: node.mesh.weights;
                    geometryNode.morpher = scnMorpher;
                }
            }
        }

        if (node.skin) {
            NSMutableArray *bones = [NSMutableArray array];
            for (GLTFNode *jointNode in node.skin.joints) {
                SCNNode *bone = nodesForIdentifiers[jointNode.identifier];
                [bones addObject:bone];
            }
            NSArray *ibmValues = GLTFSCNMatrix4ArrayFromAccessor(node.skin.inverseBindMatrices);
            for (SCNNode *skinnedNode in geometryNodes) {
                SCNGeometrySource *boneWeights = [skinnedNode.geometry geometrySourcesForSemantic:SCNGeometrySourceSemanticBoneWeights].firstObject;
                SCNGeometrySource *boneIndices = [skinnedNode.geometry geometrySourcesForSemantic:SCNGeometrySourceSemanticBoneIndices].firstObject;
                if ((boneIndices.vectorCount != boneWeights.vectorCount) ||
                    ((boneIndices.data.length / boneIndices.vectorCount / boneIndices.bytesPerComponent) !=
                     (boneWeights.data.length / boneWeights.vectorCount / boneWeights.bytesPerComponent))) {
                    // If these conditions fail, we won't be able to create a skinner, so don't bother
                    continue;
                }
                SCNSkinner *skinner = [SCNSkinner skinnerWithBaseGeometry:skinnedNode.geometry
                                                                    bones:bones
                                                boneInverseBindTransforms:ibmValues
                                                              boneWeights:boneWeights
                                                              boneIndices:boneIndices];
                if (node.skin.skeleton) {
                    skinner.skeleton = nodesForIdentifiers[node.skin.skeleton.identifier];
                }
                skinnedNode.skinner = skinner;
            }
        }
    }

    NSMutableDictionary<NSUUID *, GLTFSCNAnimation *> *animationsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFAnimation *animation in self.asset.animations) {
        NSMutableArray *caChannels = [NSMutableArray array];
        NSTimeInterval maxChannelTime = 0.0;
        for (GLTFAnimationChannel *channel in animation.channels) {
            NSTimeInterval channelMaxKeyTime = 0.0;
            if (channel.sampler.input.maxValues.count > 0) {
                channelMaxKeyTime = channel.sampler.input.maxValues.firstObject.doubleValue;
            }
            maxChannelTime = MAX(maxChannelTime, channelMaxKeyTime);
            NSArray<NSNumber *> *baseKeyTimes = GLTFKeyTimeArrayForAccessor(channel.sampler.input, channelMaxKeyTime);
            if ([channel.target.path isEqualToString:GLTFAnimationPathWeights]) {
                NSUInteger targetCount = channel.target.node.mesh.primitives.firstObject.targets.count;
                assert(targetCount > 0);
                NSArray<NSArray<NSNumber *> *> *weightArrays = GLTFWeightsArraysForAccessor(channel.sampler.output, targetCount);

                SCNNode *targetRoot = nodesForIdentifiers[channel.target.node.identifier];
                NSMutableArray<SCNNode *> *geometryNodes = [NSMutableArray array];
                if (targetRoot.geometry != nil) {
                    [geometryNodes addObject:targetRoot];
                } else {
                    for (SCNNode *child in targetRoot.childNodes) {
                        if (child.geometry != nil) {
                            [geometryNodes addObject:child];
                        }
                    }
                }

                NSMutableArray *weightAnimations = [NSMutableArray array];
                for (int t = 0; t < targetCount; ++t) {
                    for (int n = 0; n < geometryNodes.count; ++n) {
                        NSString *propertyKeyPath = [NSString stringWithFormat:@"morpher.weights[%d]", t];
                        NSString *targetRootPath = [NSString stringWithFormat:@"/%@", geometryNodes[n].name];
                        NSString *keyPath = [@[targetRootPath, propertyKeyPath] componentsJoinedByString:@"."];
                        CAKeyframeAnimation *weightAnimation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
                        weightAnimation.keyTimes = baseKeyTimes;
                        weightAnimation.values = weightArrays[t];
                        // TODO: Support non-linear calculation modes?
                        weightAnimation.calculationMode = kCAAnimationLinear;
                        weightAnimation.duration = channelMaxKeyTime;
                        weightAnimation.repeatDuration = FLT_MAX;
                        [weightAnimations addObject:weightAnimation];
                    }
                }
                CAAnimationGroup *caAnimation = [CAAnimationGroup animation];
                caAnimation.animations = weightAnimations;
                caAnimation.duration = channelMaxKeyTime;
                [caChannels addObject:caAnimation];
            } else {
                CAKeyframeAnimation *caAnimation = nil;
                if ([channel.target.path isEqualToString:GLTFAnimationPathTranslation]) {
                    NSString *keyPath = [NSString stringWithFormat:@"/%@.position", channel.target.node.name];
                    caAnimation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
                    caAnimation.values = GLTFSCNVector3ArrayForAccessor(channel.sampler.output);
                } else if ([channel.target.path isEqualToString:GLTFAnimationPathRotation]) {
                    NSString *keyPath = [NSString stringWithFormat:@"/%@.orientation", channel.target.node.name];
                    caAnimation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
                    caAnimation.values = GLTFSCNVector4ArrayForAccessor(channel.sampler.output);
                } else if ([channel.target.path isEqualToString:GLTFAnimationPathScale]) {
                    NSString *keyPath = [NSString stringWithFormat:@"/%@.scale", channel.target.node.name];
                    caAnimation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
                    caAnimation.values = GLTFSCNVector3ArrayForAccessor(channel.sampler.output);
                } else {
                    GLTFLogError(@"Unknown animation channel path: %@.", channel.target.path);
                    continue;
                }
                caAnimation.keyTimes = baseKeyTimes;
                switch (channel.sampler.interpolationMode) {
                    case GLTFInterpolationModeLinear:
                        caAnimation.calculationMode = kCAAnimationLinear;
                        break;
                    case GLTFInterpolationModeStep:
                        caAnimation.calculationMode = kCAAnimationDiscrete;
                        caAnimation.keyTimes = [@[@(0.0)] arrayByAddingObjectsFromArray:caAnimation.keyTimes];
                        break;
                    case GLTFInterpolationModeCubic:
                        caAnimation.calculationMode = kCAAnimationCubic;
                        // CAKeyframeAnimation doesn't support explicit in- and out-tangents,
                        // so we assume them to be zero, resulting in Catmull-Rom interpolation.
                        // TODO: If possible, convert provided tangents into Kochanek–Bartels form.
                        __block NSMutableArray *knots = [NSMutableArray array];
                        [caAnimation.values enumerateObjectsUsingBlock:^(id value, NSUInteger i, BOOL *stop) {
                            if (((i - 1) % 3) == 0) {
                                [knots addObject:caAnimation.values[i]];
                            }
                        }];
                        caAnimation.values = knots;
                        break;
                }
                caAnimation.duration = channelMaxKeyTime;
                [caChannels addObject:caAnimation];
            }
        }
        CAAnimationGroup *channelGroup = [CAAnimationGroup animation];
        channelGroup.animations = caChannels;
        channelGroup.duration = maxChannelTime;
        channelGroup.repeatDuration = FLT_MAX;
        SCNAnimation *scnChannelGroup = [SCNAnimation animationWithCAAnimation:channelGroup];
        SCNAnimationPlayer *animationPlayer = [SCNAnimationPlayer animationPlayerWithAnimation:scnChannelGroup];
        GLTFSCNAnimation *gltfSCNAnimation = [GLTFSCNAnimation new];
        gltfSCNAnimation.name = animation.name;
        gltfSCNAnimation.animationPlayer = animationPlayer;
        animationsForIdentifiers[animation.identifier] = gltfSCNAnimation;
    }

    NSMutableDictionary *scenesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFScene *scene in self.asset.scenes) {
        SCNScene *scnScene = [SCNScene scene];
        for (GLTFNode *rootNode in scene.nodes) {
            SCNNode *scnChildNode = nodesForIdentifiers[rootNode.identifier];
            [scnScene.rootNode addChildNode:scnChildNode];
        }
        scenesForIdentifiers[scene.identifier] = scnScene;
    }

    CGColorSpaceRelease(colorSpaceLinearSRGB);

    _materials = [materialsForIdentifiers allValues];
    _lights = [lightsForIdentifiers allValues];
    _cameras = [camerasForIdentifiers allValues];
    _nodes = [nodesForIdentifiers allValues];
    _geometries = [geometryForIdentifiers allValues];
    _scenes = [scenesForIdentifiers allValues];
    _animations = [animationsForIdentifiers allValues];

    if (self.asset.defaultScene) {
        _defaultScene = scenesForIdentifiers[self.asset.defaultScene.identifier];
    } else if (self.asset.scenes.count > 0) {
        _defaultScene = scenesForIdentifiers[self.asset.scenes.firstObject.identifier];
    } else {
        // Last resort. The asset doesn't contain any scenes but we're contractually obligated to return something.
        _defaultScene = [SCNScene scene];
    }

    [_materialPropertyContentsCache removeAllObjects];
}

@end
