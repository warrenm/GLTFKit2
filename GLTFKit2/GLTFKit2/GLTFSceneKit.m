
#import "GLTFSceneKit.h"

#if TARGET_OS_IOS
typedef UIImage NSUIImage;
#elif TARGET_OS_OSX
typedef NSImage NSUIImage;
#else
#error "Unsupported operating system. Cannot determine suitable image class"
#endif

static float GLTFDegFromRad(float rad) {
    return rad * (180.0 / M_PI);
}

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

static int GLTFSCNPrimitiveTypeForPrimitiveType(GLTFPrimitiveType type) {
    switch (type) {
        case GLTFPrimitiveTypePoints:
            return SCNGeometryPrimitiveTypePoint;
        case GLTFPrimitiveTypeLines:
            return SCNGeometryPrimitiveTypeLine;
        case GLTFPrimitiveTypeTriangles:
            return SCNGeometryPrimitiveTypeTriangles;
        case GLTFPrimitiveTypeTriangleStrip:
            return SCNGeometryPrimitiveTypeTriangleStrip;
        default:
            // No support for line loops, line strips, or triangle fans.
            // These should be retopologized before creating a geometry.
            return -1;
    }
}

static int GLTFSCNPrimitiveCountForVertexCount(GLTFPrimitiveType type, int vertexCount) {
    switch (type) {
        case GLTFPrimitiveTypePoints:
            return vertexCount;
        case GLTFPrimitiveTypeLines:
            return vertexCount / 2;
        case GLTFPrimitiveTypeTriangles:
            return vertexCount / 3;
        case GLTFPrimitiveTypeTriangleStrip:
            return vertexCount - 2; // TODO: Handle primitive restart?
        default:
            // No support for line loops, line strips, or triangle fans.
            // These should be retopologized before creating a geometry.
            return -1;
    }
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
        defaultSampler = [[GLTFTextureSampler alloc] init];
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
        // clgtf doesn't distinguish between texture transforms that override the mapping
        // channel to 0 and texture transforms that don't override, so we have to assume
        // that if the mapping channel looks like an override to channel 0, it isn't.
        if (textureParams.transform.texCoord > 0) {
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

static NSArray<NSValue *> *GLTFFloat3ValueArrayForAccessor(GLTFAccessor *accessor) {
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

static NSArray<NSValue *> *GLTFFloat4ValueArrayForAccessor(GLTFAccessor *accessor) {
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

static NSArray<NSValue *> *GLTFMatrixValueArrayFromAccessor(GLTFAccessor *accessor) {
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

@implementation GLTFSCNAnimationChannel
@end

@implementation GLTFSCNAnimation
@end

@implementation SCNScene (GLTFSceneKit)

+ (instancetype)sceneWithGLTFAsset:(GLTFAsset *)asset
{
    NSMutableDictionary<NSUUID *, NSUIImage *> *imagesForIdentfiers = [NSMutableDictionary dictionary];
    for (GLTFImage *image in asset.images) {
        NSUIImage *uiImage = nil;
        if (image.uri) {
            uiImage = [[NSUIImage alloc] initWithContentsOfURL:image.uri];
        } else {
            CGImageRef cgImage = [image createCGImage];
            uiImage = [[NSUIImage alloc] initWithCGImage:cgImage size:NSZeroSize];
        }
        imagesForIdentfiers[image.identifier] = uiImage;
    }
    
    CGColorSpaceRef colorSpaceLinearSRGB = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    
    SCNMaterial *defaultMaterial = [SCNMaterial material];
    defaultMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    defaultMaterial.locksAmbientWithDiffuse = YES;
    CGFloat defaultBaseColorFactor[] = { 1.0, 1.0, 1.0, 1.0 };
    defaultMaterial.diffuse.contents = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, &defaultBaseColorFactor[0]);
    defaultMaterial.metalness.contents = @(1.0);
    defaultMaterial.roughness.contents = @(1.0);

    NSMutableDictionary <NSUUID *, SCNMaterial *> *materialsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMaterial *material in asset.materials) {
        SCNMaterial *scnMaterial = [SCNMaterial new];
        scnMaterial.locksAmbientWithDiffuse = YES;
        if (material.metallicRoughness) {
            scnMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
        }
        //TODO: How to represent base color/emissive factor, etc., when textures are present?
        if (material.metallicRoughness.baseColorTexture) {
            GLTFTextureParams *baseColorTexture = material.metallicRoughness.baseColorTexture;
            SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
            baseColorProperty.contents = imagesForIdentfiers[baseColorTexture.texture.source.identifier];
            GLTFConfigureSCNMaterialProperty(baseColorProperty, baseColorTexture);
            // This is pretty awful, but we have no other straightforward way of supporting
            // base color textures and factors simultaneously
            simd_float4 rgba = material.metallicRoughness.baseColorFactor;
            CGFloat rgbad[] = { rgba[0], rgba[1], rgba[2], rgba[3] };
            scnMaterial.multiply.contents = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, rgbad);
        } else {
            SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
            simd_float4 rgba = material.metallicRoughness.baseColorFactor;
            CGFloat rgbad[] = { rgba[0], rgba[1], rgba[2], rgba[3] };
            baseColorProperty.contents = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, rgbad);
        }
        if (material.metallicRoughness.metallicRoughnessTexture) {
            GLTFTextureParams *metallicRoughnessTexture = material.metallicRoughness.metallicRoughnessTexture;
            id metallicRoughnessImage = imagesForIdentfiers[metallicRoughnessTexture.texture.source.identifier];
            
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
            metallicProperty.contents = @(material.metallicRoughness.metallicFactor);
            SCNMaterialProperty *roughnessProperty = scnMaterial.roughness;
            roughnessProperty.contents = @(material.metallicRoughness.roughnessFactor);
        }
        if (material.normalTexture) {
            GLTFTextureParams *normalTexture = material.normalTexture;
            SCNMaterialProperty *normalProperty = scnMaterial.normal;
            normalProperty.contents = imagesForIdentfiers[normalTexture.texture.source.identifier];
            GLTFConfigureSCNMaterialProperty(normalProperty, normalTexture);
        }
        if (material.emissiveTexture) {
            GLTFTextureParams *emissiveTexture = material.emissiveTexture;
            SCNMaterialProperty *emissiveProperty = scnMaterial.emission;
            emissiveProperty.contents = imagesForIdentfiers[emissiveTexture.texture.source.identifier];
            GLTFConfigureSCNMaterialProperty(emissiveProperty, emissiveTexture);
        } else {
            SCNMaterialProperty *emissiveProperty = scnMaterial.emission;
            simd_float3 rgb = material.emissiveFactor;
            CGFloat rgbad[] = { rgb[0], rgb[1], rgb[2], 1.0 };
            emissiveProperty.contents = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, &rgbad[0]);
        }
        if (material.occlusionTexture) {
            GLTFTextureParams *occlusionTexture = material.occlusionTexture;
            SCNMaterialProperty *occlusionProperty = scnMaterial.ambientOcclusion;
            occlusionProperty.contents = imagesForIdentfiers[occlusionTexture.texture.source.identifier];
            GLTFConfigureSCNMaterialProperty(occlusionProperty, occlusionTexture);
        }
        if (material.clearcoat) {
            if (@available(macOS 10.15, *)) {
                if (material.clearcoat.clearcoatTexture) {
                    GLTFTextureParams *clearcoatTexture = material.clearcoat.clearcoatTexture;
                    SCNMaterialProperty *clearcoatProperty = scnMaterial.clearCoat;
                    clearcoatProperty.contents = imagesForIdentfiers[clearcoatTexture.texture.source.identifier];
                    GLTFConfigureSCNMaterialProperty(clearcoatProperty, material.clearcoat.clearcoatTexture);
                } else {
                    scnMaterial.clearCoat.contents = @(material.clearcoat.clearcoatFactor);
                }
                if (material.clearcoat.clearcoatRoughnessTexture) {
                    GLTFTextureParams *clearcoatRoughnessTexture = material.clearcoat.clearcoatRoughnessTexture;
                    SCNMaterialProperty *clearcoatRoughnessProperty = scnMaterial.clearCoatRoughness;
                    clearcoatRoughnessProperty.contents = imagesForIdentfiers[clearcoatRoughnessTexture.texture.source.identifier];
                    GLTFConfigureSCNMaterialProperty(clearcoatRoughnessProperty, material.clearcoat.clearcoatRoughnessTexture);
                } else {
                    scnMaterial.clearCoatRoughness.contents = @(material.clearcoat.clearcoatRoughnessFactor);
                }
                if (material.clearcoat.clearcoatNormalTexture) {
                    GLTFTextureParams *clearcoatNormalTexture = material.clearcoat.clearcoatNormalTexture;
                    SCNMaterialProperty *clearcoatNormalProperty = scnMaterial.clearCoatNormal;
                    clearcoatNormalProperty.contents = imagesForIdentfiers[clearcoatNormalTexture.texture.source.identifier];
                    GLTFConfigureSCNMaterialProperty(clearcoatNormalProperty, material.clearcoat.clearcoatNormalTexture);
                }
            }
        }
        scnMaterial.doubleSided = material.isDoubleSided;
        scnMaterial.blendMode = (material.alphaMode == GLTFAlphaModeBlend) ? SCNBlendModeAlpha : SCNBlendModeReplace;
        scnMaterial.transparencyMode = SCNTransparencyModeDefault;
        // TODO: Use shader modifiers to implement more precise alpha test cutoff?
        materialsForIdentifiers[material.identifier] = scnMaterial;
    }
    
    NSMutableDictionary <NSUUID *, NSArray<SCNGeometry *> *> *geometryArraysForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMesh *mesh in asset.meshes) {
        NSMutableArray<SCNGeometry *> *geometries = [NSMutableArray array];
        for (GLTFPrimitive *primitive in mesh.primitives) {
            int vertexCount = 0;
            GLTFAccessor *positionAccessor = primitive.attributes[GLTFAttributeSemanticPosition];
            if (positionAccessor != nil) {
                vertexCount = (int)positionAccessor.count;
            }
            SCNMaterial *material = materialsForIdentifiers[primitive.material.identifier];
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
            SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:indexData
                                                                        primitiveType:GLTFSCNPrimitiveTypeForPrimitiveType(primitive.primitiveType)
                                                                       primitiveCount:GLTFSCNPrimitiveCountForVertexCount(primitive.primitiveType, indexCount)
                                                                        bytesPerIndex:indexSize];
            
            NSMutableArray *geometrySources = [NSMutableArray arrayWithCapacity:primitive.attributes.count];
            for (NSString *key in primitive.attributes.allKeys) {
                GLTFAccessor *attrAccessor = primitive.attributes[key];
                GLTFBufferView *attrBufferView = attrAccessor.bufferView;
                GLTFBuffer *attrBuffer = attrBufferView.buffer;
                size_t bytesPerComponent = GLTFBytesPerComponentForComponentType(attrAccessor.componentType);
                size_t componentCount = GLTFComponentCountForDimension(attrAccessor.dimension);
                size_t elementSize = bytesPerComponent * componentCount;
                // TODO: This is very wasteful when we have interleaved attributes; we duplicate all data for every attribute.
                NSData *attrData = [NSData dataWithBytesNoCopy:(void *)attrBuffer.data.bytes + attrBufferView.offset + attrAccessor.offset
                                                        length:attrAccessor.count * MAX(attrBufferView.stride, elementSize)
                                                  freeWhenDone:NO];
                SCNGeometrySource *source = [SCNGeometrySource geometrySourceWithData:attrData
                                                                             semantic:GLTFSCNGeometrySourceSemanticForSemantic(key)
                                                                          vectorCount:vertexCount
                                                                      floatComponents:(attrAccessor.componentType == GLTFComponentTypeFloat)
                                                                  componentsPerVector:componentCount
                                                                    bytesPerComponent:bytesPerComponent
                                                                           dataOffset:0
                                                                           dataStride:MAX(attrBufferView.stride, elementSize)];
                [geometrySources addObject:source];
            }
            
            SCNGeometry *geometry = [SCNGeometry geometryWithSources:geometrySources elements:@[element]];
            geometry.firstMaterial = material ?: defaultMaterial;
            [geometries addObject:geometry];
        }
        geometryArraysForIdentifiers[mesh.identifier] = geometries;
    }
    
    NSMutableDictionary<NSUUID *, SCNCamera *> *camerasForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFCamera *camera in asset.cameras) {
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
    for (GLTFLight *light in asset.lights) {
        SCNLight *scnLight = [SCNLight light];
        scnLight.name = light.name;
        CGFloat rgba[] = { light.color[0], light.color[1], light.color[2], 1.0 };
        scnLight.color = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, rgba);
        const float LumensPerCandela = 1.0 / (4.0 * M_PI);
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
        scnLight.castsShadow = YES;
        lightsForIdentifiers[light.identifier] = scnLight;
    }
    
    NSMutableDictionary<NSUUID *, SCNNode *> *nodesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFNode *node in asset.nodes) {
        SCNNode *scnNode = [SCNNode node];
        scnNode.name = node.name;
        if (node.mesh) {
            NSArray *geometries = geometryArraysForIdentifiers[node.mesh.identifier];
            if (geometries.count == 1) {
                scnNode.geometry = geometryArraysForIdentifiers[node.mesh.identifier].firstObject;
            } else if (geometries.count > 1) {
                for (SCNGeometry *geometry in geometries) {
                    SCNNode *geometryHolder = [SCNNode nodeWithGeometry:geometry];
                    [scnNode addChildNode:geometryHolder];
                }
            }
        }
        if (node.camera) {
            scnNode.camera = camerasForIdentifiers[node.camera.identifier];
        }
        if (node.light) {
            scnNode.light = lightsForIdentifiers[node.light.identifier];
        }
        scnNode.simdTransform = node.matrix;
        nodesForIdentifiers[node.identifier] = scnNode;
    }

    for (GLTFNode *node in asset.nodes) {
        SCNNode *scnNode = nodesForIdentifiers[node.identifier];
        for (GLTFNode *childNode in node.childNodes) {
            SCNNode *scnChildNode = nodesForIdentifiers[childNode.identifier];
            [scnNode addChildNode:scnChildNode];
        }
    }
    
    // SceneKit so inextricably connects skins to the node graphs they skin that it's pretty
    // hopeless to create a mapping from GLTF skins to SCN skinners. So, we just brute-force
    // iterate looking for skinned nodes and create a skinner per skinned node.
    for (GLTFNode *node in asset.nodes) {
        GLTFSkin *skin = node.skin;
        if (skin == nil) { continue; }

        NSMutableArray *bones = [NSMutableArray array];
        for (GLTFNode *jointNode in skin.joints) {
            SCNNode *bone = nodesForIdentifiers[jointNode.identifier];
            [bones addObject:bone];
        }
        NSArray *ibmValues = GLTFMatrixValueArrayFromAccessor(skin.inverseBindMatrices);
        SCNNode *scnNode = nodesForIdentifiers[node.identifier];
        SCNGeometrySource *weights = [scnNode.geometry geometrySourcesForSemantic:SCNGeometrySourceSemanticBoneWeights].firstObject;
        SCNGeometrySource *indices = [scnNode.geometry geometrySourcesForSemantic:SCNGeometrySourceSemanticBoneIndices].firstObject;
        SCNSkinner *skinner = [SCNSkinner skinnerWithBaseGeometry:scnNode.geometry
                                                            bones:bones
                                        boneInverseBindTransforms:ibmValues
                                                      boneWeights:weights
                                                      boneIndices:indices];
        if (skin.skeleton) {
            skinner.skeleton = nodesForIdentifiers[skin.skeleton.identifier];
        }
        scnNode.skinner = skinner;
    }

    NSMutableDictionary<NSUUID *, GLTFSCNAnimation *> *animationsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFAnimation *animation in asset.animations) {
        NSMutableArray *scnChannels = [NSMutableArray array];
        NSTimeInterval maxChannelKeyTime = 0.0;
        for (GLTFAnimationChannel *channel in animation.channels) {
            if (channel.sampler.input.maxValues.count > 0) {
                NSTimeInterval channelMaxTime = channel.sampler.input.maxValues.firstObject.doubleValue;
                if (channelMaxTime > maxChannelKeyTime) {
                    maxChannelKeyTime = channelMaxTime;
                }
            }
        }
        for (GLTFAnimationChannel *channel in animation.channels) {
            CAKeyframeAnimation *caAnimation = nil;
            if ([channel.target.path isEqualToString:GLTFAnimationPathTranslation]) {
                caAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
                caAnimation.values = GLTFFloat3ValueArrayForAccessor(channel.sampler.output);
            } else if ([channel.target.path isEqualToString:GLTFAnimationPathRotation]) {
                caAnimation = [CAKeyframeAnimation animationWithKeyPath:@"orientation"];
                caAnimation.values = GLTFFloat4ValueArrayForAccessor(channel.sampler.output);
            } else if ([channel.target.path isEqualToString:GLTFAnimationPathScale]) {
                caAnimation = [CAKeyframeAnimation animationWithKeyPath:@"scale"];
                caAnimation.values = GLTFFloat3ValueArrayForAccessor(channel.sampler.output);
            } else {
                // TODO: This shouldn't be a hard failure, but not sure what to do here yet
                assert(false);
            }
            NSArray<NSNumber *> *baseKeyTimes = GLTFKeyTimeArrayForAccessor(channel.sampler.input, maxChannelKeyTime);
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
                    break;
            }
            // TODO: Animated weights
            caAnimation.beginTime = baseKeyTimes.firstObject.doubleValue;
            caAnimation.duration = maxChannelKeyTime;
            caAnimation.repeatDuration = FLT_MAX;
            GLTFSCNAnimationChannel *clipChannel = [GLTFSCNAnimationChannel new];
            clipChannel.target = nodesForIdentifiers[channel.target.node.identifier];
            SCNAnimation *scnAnimation = [SCNAnimation animationWithCAAnimation:caAnimation];
            clipChannel.animation = scnAnimation;
            [scnChannels addObject:clipChannel];
            
            //[clipChannel.target addAnimation:scnAnimation forKey:channel.target.path]; // HACK for testing
        }
        GLTFSCNAnimation *animationClip = [GLTFSCNAnimation new];
        animationClip.name = animation.name;
        animationClip.channels = scnChannels;
        animationsForIdentifiers[animation.identifier] = animationClip;
    }

    NSMutableDictionary *scenesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFScene *scene in asset.scenes) {
        SCNScene *scnScene = [SCNScene scene];
        for (GLTFNode *rootNode in scene.nodes) {
            SCNNode *scnChildNode = nodesForIdentifiers[rootNode.identifier];
            [scnScene.rootNode addChildNode:scnChildNode];
        }
        scenesForIdentifiers[scene.identifier] = scnScene;
    }
    
    if (asset.defaultScene) {
        return scenesForIdentifiers[asset.defaultScene.identifier];
    } else if (asset.scenes.count > 0) {
        return scenesForIdentifiers[asset.scenes.firstObject];
    } else {
        // Last resort. The asset doesn't contain any scenes but we're contractually obligated to return something.
        return [SCNScene scene];
    }
}

@end
