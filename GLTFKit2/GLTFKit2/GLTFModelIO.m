
#import "GLTFModelIO.h"

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
    static int ComponentCountMask = 0x1f;
    if (((format & MDLVertexFormatCharBits) == MDLVertexFormatCharBits) ||
        ((format & MDLVertexFormatUCharBits) == MDLVertexFormatUCharBits) ||
        ((format & MDLVertexFormatCharNormalizedBits) == MDLVertexFormatCharNormalizedBits) ||
        ((format & MDLVertexFormatUCharNormalizedBits) == MDLVertexFormatUCharNormalizedBits))
    {
        return sizeof(UInt8) * (format & ComponentCountMask);
    } else if (((format & MDLVertexFormatShortBits) == MDLVertexFormatShortBits) ||
               ((format & MDLVertexFormatUShortBits) == MDLVertexFormatUShortBits) ||
               ((format & MDLVertexFormatShortNormalizedBits) == MDLVertexFormatShortNormalizedBits) ||
               ((format & MDLVertexFormatUShortNormalizedBits) == MDLVertexFormatUShortNormalizedBits) ||
               ((format & MDLVertexFormatHalfBits) == MDLVertexFormatHalfBits))
    {
        return sizeof(UInt16) * (format & ComponentCountMask);
    } else if (((format & MDLVertexFormatIntBits) == MDLVertexFormatIntBits) ||
               ((format & MDLVertexFormatUIntBits) == MDLVertexFormatUIntBits) ||
               ((format & MDLVertexFormatFloatBits) == MDLVertexFormatFloatBits))
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

@implementation MDLAsset (GLTFKit2)

+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset {
    return [self assetWithGLTFAsset:asset bufferAllocator:nil];
}

+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset bufferAllocator:(id <MDLMeshBufferAllocator>)bufferAllocator
{
    if (bufferAllocator == nil) {
        bufferAllocator = [MDLMeshBufferDataAllocator new];
    }
    
    //NSMutableDictionary<NSUUID *, id<MDLMeshBuffer>> *buffersForIdentifiers = [NSMutableDictionary dictionary];
    //for (GLTFBuffer *buffer in asset.buffers) {
    //    if (buffer.data) {
    //        id<MDLMeshBuffer> mdlBuffer = [bufferAllocator newBufferWithData:buffer.data type:MDLMeshBufferTypeVertex];
    //        buffersForIdentifiers[buffer.identifier] = mdlBuffer;
    //    } else {
    //        id<MDLMeshBuffer> mdlBuffer = [bufferAllocator newBuffer:buffer.length type:MDLMeshBufferTypeVertex];
    //        buffersForIdentifiers[buffer.identifier] = mdlBuffer;
    //    }
    //}
    
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
        }
        if (material.normalTexture) {
            MDLTextureSampler *normalSampler = [textureSamplersForTextureIdentifiers[material.normalTexture.texture.identifier] GLTF_copy];
            if (material.normalTexture.transform) {
                normalSampler.transform = [[MDLTransform alloc] initWithMatrix:material.normalTexture.transform.matrix];
            }
            normalSampler.mappingChannel = material.normalTexture.texCoord;
            func.normal.textureSamplerValue = normalSampler;
        }
        if (material.emissiveTexture) {
            MDLTextureSampler *emissiveSampler = [textureSamplersForTextureIdentifiers[material.emissiveTexture.texture.identifier] GLTF_copy];
            if (material.emissiveTexture.transform) {
                emissiveSampler.transform = [[MDLTransform alloc] initWithMatrix:material.emissiveTexture.transform.matrix];
            }
            emissiveSampler.mappingChannel = material.emissiveTexture.texCoord;
            func.emission.textureSamplerValue = emissiveSampler;
        }
        // TODO: How to represent base color/emissive factor, normal/occlusion strength, etc.?

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
            GLTFBuffer *indexBuffer = indexBufferView.buffer;
            
            assert(primitive.indices.componentType == GLTFComponentTypeUnsignedShort ||
                   primitive.indices.componentType == GLTFComponentTypeUnsignedInt);
            size_t indexSize = primitive.indices.componentType == GLTFComponentTypeUnsignedShort ? sizeof(UInt16) : sizeof(UInt32);
            assert(indexBufferView.stride == 0 || indexBufferView.stride == indexSize);
            NSData *indexData = [NSData dataWithBytesNoCopy:(void *)indexBuffer.data.bytes + indexBufferView.offset + indexAccessor.offset
                                                     length:primitive.indices.count * indexSize
                                               freeWhenDone:NO];
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
            for (NSString *key in primitive.attributes.allKeys) {
                GLTFAccessor *attrAccessor = primitive.attributes[key];
                GLTFBufferView *attrBufferView = attrAccessor.bufferView;
                GLTFBuffer *attrBuffer = attrBufferView.buffer;
                MDLVertexFormat mdlFormat = GLTFMDLVertexFormatForAccessor(attrAccessor);
                size_t formatSize = GLTFMDLSizeForVertexFormat(mdlFormat);
                NSData *attrData = [NSData dataWithBytesNoCopy:(void *)attrBuffer.data.bytes + attrBufferView.offset + attrAccessor.offset
                                                         length:attrAccessor.count * formatSize
                                                   freeWhenDone:NO];
                id<MDLMeshBuffer> vertexBuffer = [bufferAllocator newBufferWithData:attrData type:MDLMeshBufferTypeVertex];
                [vertexBuffers addObject:vertexBuffer];
                vertexCount = (int)attrAccessor.count;
                vertexDescriptor.attributes[attrIndex].bufferIndex = attrIndex;
                vertexDescriptor.attributes[attrIndex].format = mdlFormat;
                vertexDescriptor.attributes[attrIndex].name = GLTFMDLVertexAttributeNameForSemantic(key);
                vertexDescriptor.attributes[attrIndex].offset = 0;
                vertexDescriptor.layouts[attrIndex].stride = attrBufferView.stride ? attrBufferView.stride : formatSize;
                ++attrIndex;
            }

            MDLMesh *mdlMesh = [[MDLMesh alloc] initWithVertexBuffers:vertexBuffers
                                                          vertexCount:vertexCount
                                                           descriptor:vertexDescriptor
                                                            submeshes:@[submesh]];
            [mdlMeshes addObject:mdlMesh];
        }
        meshArraysForIdentifiers[mesh.identifier] = mdlMeshes;
    }
    
    NSMutableDictionary<NSUUID *, MDLCamera *> *camerasForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFCamera *camera in asset.cameras) {
        MDLCamera *mdlCamera = [MDLCamera new];
        mdlCamera.name = camera.name;
        // TODO: Handle optional zfar and aspect ratio for perspective cameras.
        // Waiting on cgltf pull request #141.
        mdlCamera.nearVisibilityDistance = camera.zNear;
        mdlCamera.farVisibilityDistance = camera.zFar;
        if (camera.orthographic) {
            mdlCamera.projection = MDLCameraProjectionOrthographic;
            mdlCamera.sensorEnlargement = simd_make_float2(camera.orthographic.xMag, camera.orthographic.yMag);
        } else if (camera.perspective) {
            mdlCamera.projection = MDLCameraProjectionPerspective;
            mdlCamera.sensorAspect = camera.perspective.aspectRatio;
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
        mdlLight.color = CGColorCreate(colorSpaceLinearSRGB, rgba);
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
    
    // Node -> MDLNode
    NSMutableDictionary<NSUUID *, MDLObject *> *nodesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFNode *node in asset.nodes) {
        MDLObject *mdlNode = [MDLObject new];
        if (node.mesh) {
        }
        if (node.light) {
            MDLLight *light = lightsForIdentifiers[node.light.identifier];
            [mdlNode addChild:light];
        }
        if (node.camera) {
            MDLCamera *camera = camerasForIdentifiers[node.camera.identifier];
            [mdlNode addChild:camera];
        }
    }
    
    // Scene -> MDLAsset
    
    // Animation, Skin ??

    CFRelease(colorSpaceLinearSRGB);

    MDLAsset *mdlAsset = [[MDLAsset alloc] initWithBufferAllocator:bufferAllocator];
    return mdlAsset;
}

@end
