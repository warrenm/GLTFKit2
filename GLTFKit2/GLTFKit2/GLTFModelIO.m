
#import "GLTFModelIO.h"
#import "GLTFLogging.h"

@interface MDLTextureFilter (GLTFCopyingExtensions)
- (id)GLTF_copy;
@end

@implementation MDLTextureFilter (GLTFCopyingExtensions)
- (id)GLTF_copy {
    MDLTextureFilter *filter = [MDLTextureFilter new];
    filter.sWrapMode = self.sWrapMode;
    filter.tWrapMode = self.tWrapMode;
    filter.rWrapMode = self.rWrapMode;
    filter.minFilter = self.minFilter;
    filter.magFilter = self.magFilter;
    filter.mipFilter = self.mipFilter;
    return filter;
}
@end

typedef NS_OPTIONS(long long, GLTFMDLColorMask) {
    GLTFMDLColorMaskNone   = 0,
    GLTFMDLColorMaskRed    = 1 << 3,
    GLTFMDLColorMaskGreen  = 1 << 2,
    GLTFMDLColorMaskBlue   = 1 << 1,
    GLTFMDLColorMaskAlpha  = 1 << 0,
    GLTFMDLColorMaskAll    = (1 << 4) - 1
};

@interface MDLTextureSampler (GLTFMDLPrivateFields)
// These properties expose fields that have existed since iOS 12 but have never been published.
// Technically, the backing fields for these properties could go away at any time, and exposing
// them in this way breaks the App Store rules against using private API. However, since they
// are required for interoperating correctly with other frameworks (e.g. SceneKit), it's probably
// safe to assume they'll be around for a while.
@property (nonatomic, assign) UInt64 mappingChannel;
@property (nonatomic, assign) GLTFMDLColorMask textureComponents;
@end

@interface MDLTextureSampler (GLTFCopyingExtensions)
- (id)GLTF_copy;
@end

@implementation MDLTextureSampler (GLTFCopyingExtensions)
- (id)GLTF_copy {
    MDLTextureSampler *sampler = [MDLTextureSampler new];
    sampler.texture = self.texture;
    sampler.hardwareFilter = [self.hardwareFilter GLTF_copy];
    sampler.transform = [self.transform copy];
    sampler.mappingChannel = self.mappingChannel;
    sampler.textureComponents = self.textureComponents;
    return sampler;
}
@end

@interface MDLMesh (GLTFCopyingExtensions)
- (id)GLTF_copy;
@end

@implementation MDLMesh (GLTFCopyingExtensions)
- (id)GLTF_copy {
    // TODO: Should we recursively copy submeshes? Probably so if the underlying
    // implementation assumes it's the exclusive owner of the passed-in objects.
    MDLMesh *mesh = [[MDLMesh alloc] initWithVertexBuffers:self.vertexBuffers
                                               vertexCount:self.vertexCount
                                                descriptor:self.vertexDescriptor
                                                 submeshes:self.submeshes];
    mesh.name = self.name;
    mesh.transform = self.transform;
    // n.b. we explicitly don't copy child objects
    return mesh;
}
@end

static MDLMaterialTextureFilterMode GLTFMDLTextureFilterModeForMagFilter(GLTFMagFilter filter) {
    switch (filter) {
        case GLTFMagFilterNearest:
            return MDLMaterialTextureFilterModeNearest;
        default:
            return MDLMaterialTextureFilterModeLinear;
    }
}

static void GLTFMDLGetFilterModesForMinMipFilter(GLTFMinMipFilter filter,
                                                 MDLMaterialTextureFilterMode *outMinFilter,
                                                 MDLMaterialMipMapFilterMode *outMipFilter)
{
    if (outMinFilter) {
        switch (filter) {
            case GLTFMinMipFilterNearest:
            case GLTFMinMipFilterNearestNearest:
            case GLTFMinMipFilterNearestLinear:
                *outMinFilter = MDLMaterialTextureFilterModeNearest;
                break;
            case GLTFMinMipFilterLinear:
            case GLTFMinMipFilterLinearNearest:
            case GLTFMinMipFilterLinearLinear:
                *outMinFilter = MDLMaterialTextureFilterModeLinear;
                break;
        }
    }
    if (outMipFilter) {
        switch (filter) {
            case GLTFMinMipFilterNearest:
            case GLTFMinMipFilterLinear:
            case GLTFMinMipFilterNearestNearest:
            case GLTFMinMipFilterLinearNearest:
                *outMipFilter = MDLMaterialMipMapFilterModeNearest;
                break;
            case GLTFMinMipFilterNearestLinear:
            case GLTFMinMipFilterLinearLinear:
                *outMipFilter = MDLMaterialMipMapFilterModeLinear;
                break;
        }
    }
}

static MDLMaterialTextureWrapMode GLTFMDLTextureWrapModeForMode(GLTFAddressMode mode) {
    switch (mode) {
        case GLTFAddressModeClampToEdge:
            return MDLMaterialTextureWrapModeClamp;
        case GLTFAddressModeRepeat:
            return MDLMaterialTextureWrapModeRepeat;
        case GLTFAddressModeMirroredRepeat:
            return MDLMaterialTextureWrapModeRepeat;
    }
}

static MDLIndexBitDepth GLTFMDLIndexBitDepthForComponentType(GLTFComponentType type) {
    switch (type) {
        case GLTFComponentTypeUnsignedByte:
            return MDLIndexBitDepthUInt8;
        case GLTFComponentTypeUnsignedShort:
            return MDLIndexBitDepthUInt16;
        case GLTFComponentTypeUnsignedInt:
            return MDLIndexBitDepthUInt32;
        default:
            return MDLIndexBitDepthInvalid;
    }
}

static NSInteger GLTFMDLGeometryTypeForPrimitiveType(GLTFPrimitiveType type) {
    switch (type) {
        case GLTFPrimitiveTypePoints:
            return MDLGeometryTypePoints;
        case GLTFPrimitiveTypeLines:
            return MDLGeometryTypeLines;
        case GLTFPrimitiveTypeTriangles:
            return MDLGeometryTypeTriangles;
        case GLTFPrimitiveTypeTriangleStrip:
            return MDLGeometryTypeTriangleStrips;
        default:
            // No support for line loops, line strips, or triangle fans.
            // These should be retopologized before creating an MDLMesh/Submesh.
            return -1;
    }
}

static MDLVertexFormat GLTFMDLVertexFormatForAccessor(GLTFAccessor *accessor) {
    switch (accessor.componentType) {
        case GLTFComponentTypeByte:
            switch (accessor.dimension) {
                case GLTFValueDimensionScalar:
                    return accessor.isNormalized ? MDLVertexFormatCharNormalized : MDLVertexFormatChar;
                case GLTFValueDimensionVector2:
                    return accessor.isNormalized ? MDLVertexFormatChar2Normalized : MDLVertexFormatChar2;
                case GLTFValueDimensionVector3:
                    return accessor.isNormalized ? MDLVertexFormatChar3Normalized : MDLVertexFormatChar3;
                case GLTFValueDimensionVector4:
                    return accessor.isNormalized ? MDLVertexFormatChar4Normalized : MDLVertexFormatChar4;
                default: break;
            }
            break;
        case GLTFComponentTypeUnsignedByte:
            switch (accessor.dimension) {
                case GLTFValueDimensionScalar:
                    return accessor.isNormalized ? MDLVertexFormatUCharNormalized : MDLVertexFormatUChar;
                case GLTFValueDimensionVector2:
                    return accessor.isNormalized ? MDLVertexFormatUChar2Normalized : MDLVertexFormatUChar2;
                case GLTFValueDimensionVector3:
                    return accessor.isNormalized ? MDLVertexFormatUChar3Normalized : MDLVertexFormatUChar3;
                case GLTFValueDimensionVector4:
                    return accessor.isNormalized ? MDLVertexFormatUChar4Normalized : MDLVertexFormatUChar4;
                default: break;
            }
            break;
        case GLTFComponentTypeShort:
            switch (accessor.dimension) {
                case GLTFValueDimensionScalar:
                    return accessor.isNormalized ? MDLVertexFormatShortNormalized : MDLVertexFormatShort;
                case GLTFValueDimensionVector2:
                    return accessor.isNormalized ? MDLVertexFormatShort2Normalized : MDLVertexFormatShort2;
                case GLTFValueDimensionVector3:
                    return accessor.isNormalized ? MDLVertexFormatShort3Normalized : MDLVertexFormatShort3;
                case GLTFValueDimensionVector4:
                    return accessor.isNormalized ? MDLVertexFormatShort4Normalized : MDLVertexFormatShort4;
                default: break;
            }
            break;
        case GLTFComponentTypeUnsignedShort:
            switch (accessor.dimension) {
                case GLTFValueDimensionScalar:
                    return accessor.isNormalized ? MDLVertexFormatUShortNormalized : MDLVertexFormatUShort;
                case GLTFValueDimensionVector2:
                    return accessor.isNormalized ? MDLVertexFormatUShort2Normalized : MDLVertexFormatUShort2;
                case GLTFValueDimensionVector3:
                    return accessor.isNormalized ? MDLVertexFormatUShort3Normalized : MDLVertexFormatUShort3;
                case GLTFValueDimensionVector4:
                    return accessor.isNormalized ? MDLVertexFormatUShort4Normalized : MDLVertexFormatUShort4;
                default: break;
            }
            break;
        case GLTFComponentTypeUnsignedInt:
            switch (accessor.dimension) {
                case GLTFValueDimensionScalar:
                    return MDLVertexFormatUInt;
                case GLTFValueDimensionVector2:
                    return MDLVertexFormatUInt2;
                case GLTFValueDimensionVector3:
                    return MDLVertexFormatUInt3;
                case GLTFValueDimensionVector4:
                    return MDLVertexFormatUInt4;
                default: break;
            }
            break;
        case GLTFComponentTypeFloat:
            switch (accessor.dimension) {
                case GLTFValueDimensionScalar:
                    return MDLVertexFormatFloat;
                case GLTFValueDimensionVector2:
                    return MDLVertexFormatFloat2;
                case GLTFValueDimensionVector3:
                    return MDLVertexFormatFloat3;
                case GLTFValueDimensionVector4:
                    return MDLVertexFormatFloat4;
                default: break;
            }
            break;
        default:
            break;
    }
    return MDLVertexFormatInvalid;
}

size_t GLTFMDLSizeForVertexFormat(MDLVertexFormat format) {
    static int ElementTypeMask = 0xf0000;
    static int ComponentCountMask = 0x1f;
    if (((format & ElementTypeMask) == MDLVertexFormatCharBits) ||
        ((format & ElementTypeMask) == MDLVertexFormatUCharBits) ||
        ((format & ElementTypeMask) == MDLVertexFormatCharNormalizedBits) ||
        ((format & ElementTypeMask) == MDLVertexFormatUCharNormalizedBits))
    {
        return sizeof(UInt8) * (format & ComponentCountMask);
    } else if (((format & ElementTypeMask) == MDLVertexFormatShortBits) ||
               ((format & ElementTypeMask) == MDLVertexFormatUShortBits) ||
               ((format & ElementTypeMask) == MDLVertexFormatShortNormalizedBits) ||
               ((format & ElementTypeMask) == MDLVertexFormatUShortNormalizedBits) ||
               ((format & ElementTypeMask) == MDLVertexFormatHalfBits))
    {
        return sizeof(UInt16) * (format & ComponentCountMask);
    } else if (((format & ElementTypeMask) == MDLVertexFormatIntBits) ||
               ((format & ElementTypeMask) == MDLVertexFormatUIntBits) ||
               ((format & ElementTypeMask) == MDLVertexFormatFloatBits))
    {
        return sizeof(UInt32) * (format & ComponentCountMask);
    }
    assert(false);
    return 0;
}

static NSString *GLTFMDLVertexAttributeNameForSemantic(NSString *name) {
    if ([name isEqualToString:GLTFAttributeSemanticPosition]) {
        return MDLVertexAttributePosition;
    } else if ([name isEqualToString:GLTFAttributeSemanticNormal]) {
        return MDLVertexAttributeNormal;
    } else if ([name isEqualToString:GLTFAttributeSemanticTangent]) {
        return MDLVertexAttributeTangent;
    } else if ([name hasPrefix:@"TEXCOORD_"]) {
        return MDLVertexAttributeTextureCoordinate;
    } else if ([name hasPrefix:@"COLOR_"]) {
        return MDLVertexAttributeColor;
    } else if ([name hasPrefix:@"JOINTS_"]) {
        return MDLVertexAttributeJointIndices;
    } else if ([name hasPrefix:@"WEIGHTS_"]) {
        return MDLVertexAttributeJointWeights;
    }
    return name;
}

static MDLLightType GLTFMDLLightTypeForLightType(GLTFLightType lightType) {
    switch (lightType) {
        case GLTFLightTypeDirectional:
            return MDLLightTypeDirectional;
        case GLTFLightTypePoint:
            return MDLLightTypePoint;
        case GLTFLightTypeSpot:
            return MDLLightTypeSpot;
    }
}

static NSData *GLTFPackedFloat2DataFlipVertical(NSData *data) {
    const float *uvs = data.bytes;
    float *flippedUVs = malloc(data.length);
    if (flippedUVs == NULL) {
        GLTFLogError(@"[GLTFKit2] Failed to allocate %ld bytes for storing flipped uv coordinates. Returning empty data object.",
                     (long)data.length);
        return [NSData data];
    }
    NSUInteger elementCount = data.length / sizeof(float);
    for (int i = 0; i < elementCount; i += 2) {
        flippedUVs[i + 0] = uvs[i + 0];
        flippedUVs[i + 1] = 1.0f - uvs[i + 1];
    }
    return [NSData dataWithBytesNoCopy:flippedUVs length:data.length freeWhenDone:YES];
}

@implementation MDLAsset (GLTFKit2)

+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset {
    return [self assetWithGLTFAsset:asset bufferAllocator:nil];
}

+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset bufferAllocator:(id <MDLMeshBufferAllocator>)bufferAllocator
{
    if (bufferAllocator == nil) {
        bufferAllocator = [MDLMeshBufferDataAllocator new];
    }

    NSMutableDictionary<NSUUID *, MDLTexture *> *texturesForImageIdenfiers = [NSMutableDictionary dictionary];
    for (GLTFImage *image in asset.images) {
        MDLTexture *mdlTexture = nil;
        if (image.uri) {
            mdlTexture = [[MDLURLTexture alloc] initWithURL:image.uri name:image.name];
        } else {
            CGImageRef cgImage = [image newCGImage];
            int width = (int)CGImageGetWidth(cgImage);
            int height = (int)CGImageGetHeight(cgImage);
            CGDataProviderRef dataProvider = CGImageGetDataProvider(cgImage);
            CFDataRef data = CGDataProviderCopyData(dataProvider); // hate
            mdlTexture = [[MDLTexture alloc] initWithData:(__bridge_transfer NSData *)data
                                            topLeftOrigin:YES
                                                     name:image.name
                                               dimensions:(vector_int2){ width, height }
                                                rowStride:width * 4
                                             channelCount:4
                                          channelEncoding:MDLTextureChannelEncodingUInt8
                                                   isCube:NO];
            CFRelease(cgImage);
        }
        texturesForImageIdenfiers[image.identifier] = mdlTexture;
    }
    
    NSMutableDictionary <NSUUID *, MDLTextureFilter *> *filtersForSamplerIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFTextureSampler *sampler in asset.samplers) {
        MDLTextureFilter *filter = [MDLTextureFilter new];
        filter.magFilter = GLTFMDLTextureFilterModeForMagFilter(sampler.magFilter);

        MDLMaterialTextureFilterMode minFilter;
        MDLMaterialMipMapFilterMode mipFilter;
        GLTFMDLGetFilterModesForMinMipFilter(sampler.minMipFilter, &minFilter, &mipFilter);
        filter.minFilter = minFilter;
        filter.mipFilter = mipFilter;
        
        filter.sWrapMode = GLTFMDLTextureWrapModeForMode(sampler.wrapS);
        filter.tWrapMode = GLTFMDLTextureWrapModeForMode(sampler.wrapT);
        
        filtersForSamplerIdentifiers[sampler.identifier] = filter;
    }

    NSMutableDictionary <NSUUID *, MDLTextureSampler *> *textureSamplersForTextureIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFTexture *texture in asset.textures) {
        MDLTextureSampler *mdlSampler = [MDLTextureSampler new];
        mdlSampler.texture = texturesForImageIdenfiers[texture.source.identifier];
        mdlSampler.hardwareFilter = filtersForSamplerIdentifiers[texture.sampler.identifier];
        textureSamplersForTextureIdentifiers[texture.identifier] = mdlSampler;
    }

    NSMutableDictionary <NSUUID *, MDLMaterial *> *materialsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMaterial *material in asset.materials) {
        MDLPhysicallyPlausibleScatteringFunction *func = [MDLPhysicallyPlausibleScatteringFunction new];
        if (material.metallicRoughness.baseColorTexture) {
            MDLTextureSampler *baseColorSampler = [textureSamplersForTextureIdentifiers[material.metallicRoughness.baseColorTexture.texture.identifier] GLTF_copy];
            if (material.metallicRoughness.baseColorTexture.transform) {
                baseColorSampler.transform = [[MDLTransform alloc] initWithMatrix:material.metallicRoughness.baseColorTexture.transform.matrix];
            }
            baseColorSampler.mappingChannel = material.metallicRoughness.baseColorTexture.texCoord;
            func.baseColor.textureSamplerValue = baseColorSampler;
        } else {
            func.baseColor.float4Value = material.metallicRoughness.baseColorFactor;
        }
        if (material.metallicRoughness.metallicRoughnessTexture) {
            MDLTextureSampler *metallicRoughnessSampler = [textureSamplersForTextureIdentifiers[material.metallicRoughness.metallicRoughnessTexture.texture.identifier] GLTF_copy];
            if (material.metallicRoughness.metallicRoughnessTexture.transform) {
                metallicRoughnessSampler.transform = [[MDLTransform alloc] initWithMatrix:material.metallicRoughness.metallicRoughnessTexture.transform.matrix];
            }

            MDLTextureSampler *metallicSampler = [MDLTextureSampler new];
            metallicSampler.texture = metallicRoughnessSampler.texture;
            metallicSampler.hardwareFilter = metallicRoughnessSampler.hardwareFilter;
            metallicSampler.mappingChannel = material.metallicRoughness.metallicRoughnessTexture.texCoord;
            metallicSampler.textureComponents = GLTFMDLColorMaskBlue;
            func.metallic.textureSamplerValue = metallicSampler;
            
            MDLTextureSampler *roughnessSampler = [MDLTextureSampler new];
            roughnessSampler.texture = metallicRoughnessSampler.texture;
            roughnessSampler.hardwareFilter = metallicRoughnessSampler.hardwareFilter;
            roughnessSampler.mappingChannel = material.metallicRoughness.metallicRoughnessTexture.texCoord;
            roughnessSampler.textureComponents = GLTFMDLColorMaskGreen;
            func.roughness.textureSamplerValue = roughnessSampler;
        } else {
            func.metallic.floatValue = material.metallicRoughness.metallicFactor;
            func.roughness.floatValue = material.metallicRoughness.roughnessFactor;
        }
        if (material.normalTexture) {
            MDLTextureSampler *normalSampler = [textureSamplersForTextureIdentifiers[material.normalTexture.texture.identifier] GLTF_copy];
            if (material.normalTexture.transform) {
                normalSampler.transform = [[MDLTransform alloc] initWithMatrix:material.normalTexture.transform.matrix];
            }
            normalSampler.mappingChannel = material.normalTexture.texCoord;
            func.normal.textureSamplerValue = normalSampler;
        }
        if (material.emissive.emissiveTexture) {
            MDLTextureSampler *emissiveSampler = [textureSamplersForTextureIdentifiers[material.emissive.emissiveTexture.texture.identifier] GLTF_copy];
            if (material.emissive.emissiveTexture.transform) {
                emissiveSampler.transform = [[MDLTransform alloc] initWithMatrix:material.emissive.emissiveTexture.transform.matrix];
            }
            emissiveSampler.mappingChannel = material.emissive.emissiveTexture.texCoord;
            func.emission.textureSamplerValue = emissiveSampler;
        } else {
            func.emission.float3Value = material.emissive.emissiveFactor;
        }
        if (material.indexOfRefraction != nil) {
            func.interfaceIndexOfRefraction.floatValue = material.indexOfRefraction.floatValue;
        }

        MDLMaterial *mdlMaterial = [[MDLMaterial alloc] initWithName:material.name scatteringFunction:func];
        mdlMaterial.materialFace = material.isDoubleSided ? MDLMaterialFaceDoubleSided : MDLMaterialFaceFront;
        materialsForIdentifiers[material.identifier] = mdlMaterial;
    }

    NSMutableDictionary <NSUUID *, NSArray<MDLMesh *> *> *meshArraysForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMesh *mesh in asset.meshes) {
        NSMutableArray<MDLMesh *> *mdlMeshes = [NSMutableArray array];
        for (GLTFPrimitive *primitive in mesh.primitives) {
            GLTFAccessor *indexAccessor = primitive.indices;
            GLTFBufferView *indexBufferView = indexAccessor.bufferView;

            assert(primitive.indices.componentType == GLTFComponentTypeUnsignedShort ||
                   primitive.indices.componentType == GLTFComponentTypeUnsignedInt);
            size_t indexSize = primitive.indices.componentType == GLTFComponentTypeUnsignedShort ? sizeof(UInt16) : sizeof(UInt32);
            assert(indexBufferView.stride == 0 || indexBufferView.stride == indexSize);
            NSData *indexData = GLTFPackedDataForAccessor(indexAccessor);
            id<MDLMeshBuffer> mdlIndexBuffer = [bufferAllocator newBufferWithData:indexData type:MDLMeshBufferTypeIndex];
            MDLMaterial *material = materialsForIdentifiers[primitive.material.identifier];
            MDLSubmesh *submesh = [[MDLSubmesh alloc] initWithName:primitive.name
                                                       indexBuffer:mdlIndexBuffer
                                                        indexCount:primitive.indices.count
                                                         indexType:GLTFMDLIndexBitDepthForComponentType(primitive.indices.componentType)
                                                      geometryType:GLTFMDLGeometryTypeForPrimitiveType(primitive.primitiveType)
                                                          material:material];
            
            MDLVertexDescriptor *vertexDescriptor = [MDLVertexDescriptor new];
            int attrIndex = 0;
            int vertexCount = 0;
            NSMutableArray *vertexBuffers = [NSMutableArray arrayWithCapacity:primitive.attributes.count];
            for (GLTFAttribute *attribute in primitive.attributes) {
                GLTFAccessor *attrAccessor = attribute.accessor;
                MDLVertexFormat mdlFormat = GLTFMDLVertexFormatForAccessor(attrAccessor);
                size_t formatSize = GLTFMDLSizeForVertexFormat(mdlFormat);
                NSData *attrData = GLTFPackedDataForAccessor(attrAccessor);
                if ([attribute.name hasPrefix:@"TEXCOORD_"]) {
                    // Model I/O expects UV coordinates to have a bottom-left origin
                    attrData = GLTFPackedFloat2DataFlipVertical(attrData);
                }
                id<MDLMeshBuffer> vertexBuffer = [bufferAllocator newBufferWithData:attrData type:MDLMeshBufferTypeVertex];
                [vertexBuffers addObject:vertexBuffer];
                vertexCount = (int)attrAccessor.count;
                vertexDescriptor.attributes[attrIndex].bufferIndex = attrIndex;
                vertexDescriptor.attributes[attrIndex].format = mdlFormat;
                vertexDescriptor.attributes[attrIndex].name = GLTFMDLVertexAttributeNameForSemantic(attribute.name);
                vertexDescriptor.attributes[attrIndex].offset = 0;
                vertexDescriptor.layouts[attrIndex].stride = formatSize;
                ++attrIndex;
            }

            MDLMesh *mdlMesh = [[MDLMesh alloc] initWithVertexBuffers:vertexBuffers
                                                          vertexCount:vertexCount
                                                           descriptor:vertexDescriptor
                                                            submeshes:@[submesh]];
            mdlMesh.name = mesh.name;
            [mdlMeshes addObject:mdlMesh];
        }
        meshArraysForIdentifiers[mesh.identifier] = mdlMeshes;
    }
    
    NSMutableDictionary<NSUUID *, MDLCamera *> *camerasForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFCamera *camera in asset.cameras) {
        MDLCamera *mdlCamera = [MDLCamera new];
        mdlCamera.name = camera.name;
        mdlCamera.nearVisibilityDistance = camera.zNear;
        mdlCamera.farVisibilityDistance = camera.zFar;
        if (camera.orthographic) {
            mdlCamera.projection = MDLCameraProjectionOrthographic;
            mdlCamera.sensorEnlargement = simd_make_float2(camera.orthographic.xMag, camera.orthographic.yMag);
        } else if (camera.perspective) {
            mdlCamera.projection = MDLCameraProjectionPerspective;
            if (camera.perspective.aspectRatio != 0.0) {
                mdlCamera.sensorAspect = camera.perspective.aspectRatio;
            }
            mdlCamera.fieldOfView = camera.perspective.yFOV;
        }
        camerasForIdentifiers[camera.identifier] = mdlCamera;
    }
    
    // Light -> MDLLight
    CGColorSpaceRef colorSpaceLinearSRGB = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);

    NSMutableDictionary<NSUUID *, MDLPhysicallyPlausibleLight *> *lightsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFLight *light in asset.lights) {
        MDLPhysicallyPlausibleLight *mdlLight = [MDLPhysicallyPlausibleLight new];
        mdlLight.name = light.name;
        mdlLight.lightType = GLTFMDLLightTypeForLightType(light.type);
        CGFloat rgba[] = { light.color[0], light.color[1], light.color[2], 1.0 };
        CGColorRef lightColor = CGColorCreate(colorSpaceLinearSRGB, rgba);
        mdlLight.color = lightColor;
        CGColorRelease(lightColor);
        switch (light.type) {
            case GLTFLightTypeDirectional:
                mdlLight.lumens = light.intensity; // TODO: Convert from lux to lumens? How?
                break;
            case GLTFLightTypePoint:
                mdlLight.lumens = light.intensity * LumensPerCandela;
                break;
            case GLTFLightTypeSpot:
                mdlLight.lumens = light.intensity * LumensPerCandela;
                mdlLight.innerConeAngle = GLTFDegFromRad(light.innerConeAngle);
                mdlLight.outerConeAngle = GLTFDegFromRad(light.outerConeAngle);
                break;
        }
        // TODO: Range and attenuation.
        lightsForIdentifiers[light.identifier] = mdlLight;
    }
    
    // Node -> MDLObject
    NSMutableDictionary<NSUUID *, MDLObject *> *nodesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFNode *node in asset.nodes) {
        // We'd prefer to use MDLObject rather than MDLMesh for container nodes, but
        // Model I/O's USD exporter currently exports MDLObject as a Scope instead of
        // an Xform, which loses spatial hierarchy information (FB16254600). Using
        // MDLMesh forces the exporter to emit a transform object instead of a scope.
        MDLObject *mdlNode = [MDLMesh new];
        mdlNode.name = node.name;
        mdlNode.transform = [[MDLTransform alloc] initWithMatrix:node.matrix];
        if (node.mesh) {
            NSArray<MDLMesh *> *meshes = meshArraysForIdentifiers[node.mesh.identifier];
            for (MDLMesh *mdlMesh in meshes) {
                // We would prefer not to copy here, but since each MDLObject can only have
                // one parent, we have to do this to ensure every mesh instance is represented
                [mdlNode addChild:[mdlMesh GLTF_copy]];
            }
        }
        if (node.light) {
            MDLLight *light = lightsForIdentifiers[node.light.identifier];
            [mdlNode addChild:light];
        }
        if (node.camera) {
            MDLCamera *camera = camerasForIdentifiers[node.camera.identifier];
            [mdlNode addChild:camera];
        }
        nodesForIdentifiers[node.identifier] = mdlNode;
    }

    for (GLTFNode *node in asset.nodes) {
        if (node.childNodes.count > 0) {
            MDLObject *mdlParent = nodesForIdentifiers[node.identifier];
            for (GLTFNode *child in node.childNodes) {
                MDLObject *mdlChild = nodesForIdentifiers[child.identifier];
                [mdlParent addChild:mdlChild];
            }
        }
    }

    // TODO: Convert skins and animations

    CFRelease(colorSpaceLinearSRGB);

    MDLAsset *mdlAsset = [[MDLAsset alloc] initWithBufferAllocator:bufferAllocator];

    GLTFScene *defaultScene = asset.defaultScene ?: asset.scenes.firstObject;

    for (GLTFNode *node in defaultScene.nodes) {
        MDLObject *mdlNode = nodesForIdentifiers[node.identifier];
        [mdlAsset addObject:mdlNode];
    }

    return mdlAsset;
}

@end
