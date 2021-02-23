
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

static int GLTFSCNBytesPerComponentForAccessor(GLTFAccessor *accessor) {
    switch (accessor.componentType) {
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

static int GLTFSCNComponentCountForAccessor(GLTFAccessor *accessor) {
    switch (accessor.dimension) {
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
    //property.contentsTransform = SCNMatrix4();
    property.wrapS = GLTFSCNWrapModeForMode(sampler.wrapS);
    property.wrapT = GLTFSCNWrapModeForMode(sampler.wrapT);
    property.mappingChannel = textureParams.texCoord;
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
    
    //CGColorSpaceRef colorSpaceSRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB); //
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
        scnMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
        scnMaterial.locksAmbientWithDiffuse = YES;
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
            scnMaterial.multiply.contents = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, &rgbad[0]);
        } else {
            SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
            simd_float4 rgba = material.metallicRoughness.baseColorFactor;
            CGFloat rgbad[] = { rgba[0], rgba[1], rgba[2], rgba[3] };
            baseColorProperty.contents = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, &rgbad[0]);
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
                    // We directly support this kind of index, so we can memcpy it over
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
                    indexData = GLTFPackedUInt16DataFromPackedUInt8((void *)indexBuffer.data.bytes + indexBufferView.offset + indexAccessor.offset, indexCount);
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
                size_t bytesPerComponent = GLTFSCNBytesPerComponentForAccessor(attrAccessor);
                size_t componentCount = GLTFSCNComponentCountForAccessor(attrAccessor);
                size_t formatSize = bytesPerComponent * componentCount;
                // FIXME: This is very wasteful when we have interleaved attributes; we duplicate all data for every attribute.
                NSData *attrData = [NSData dataWithBytesNoCopy:(void *)attrBuffer.data.bytes + attrBufferView.offset + attrAccessor.offset
                                                        length:attrAccessor.count * MAX(formatSize, attrBufferView.stride)
                                                  freeWhenDone:NO];
                SCNGeometrySource *source = [SCNGeometrySource geometrySourceWithData:attrData
                                                                             semantic:GLTFSCNGeometrySourceSemanticForSemantic(key)
                                                                          vectorCount:vertexCount
                                                                      floatComponents:(attrAccessor.componentType == GLTFComponentTypeFloat)
                                                                  componentsPerVector:componentCount
                                                                    bytesPerComponent:bytesPerComponent
                                                                           dataOffset:0
                                                                           dataStride:MAX(formatSize, attrBufferView.stride)];
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
        CGFloat rgbad[] = { light.color[0], light.color[1], light.color[2], 1.0 };
        scnLight.color = (__bridge id)CGColorCreate(colorSpaceLinearSRGB, rgbad);
        // TODO: SCN intensity is always lumens. Need to convert from candela (point and spot lights) and lux (directional) here.
        scnLight.intensity = light.intensity;
        switch (light.type) {
            case GLTFLightTypeDirectional:
                break;
            case GLTFLightTypePoint:
                break;
            case GLTFLightTypeSpot:
                scnLight.spotInnerAngle = GLTFDegFromRad(light.innerConeAngle);
                scnLight.spotOuterAngle = GLTFDegFromRad(light.outerConeAngle);
                break;
        }
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

    NSMutableArray *rootNodes = [NSMutableArray array];
    for (GLTFNode *node in asset.nodes) {
        SCNNode *scnNode = nodesForIdentifiers[node.identifier];
        if (node.parentNode == nil) {
            [rootNodes addObject:node];
        }
        for (GLTFNode *childNode in node.childNodes) {
            SCNNode *scnChildNode = nodesForIdentifiers[childNode.identifier];
            [scnNode addChildNode:scnChildNode];
        }
    }
    
    // TODO: Actually map GLTF scene(s)
    
    SCNScene *scene = [SCNScene scene];
    for (GLTFNode *rootNode in rootNodes) {
        SCNNode *scnChildNode = nodesForIdentifiers[rootNode.identifier];
        [scene.rootNode addChildNode:scnChildNode];
    }
    return scene;
}

@end
