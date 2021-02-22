
#import "GLTFSceneKit.h"

#if TARGET_OS_IOS
typedef UIImage NSUIImage;
#elif TARGET_OS_OSX
typedef NSImage NSUIImage;
#else
#error "Unsupported operating system. Cannot determine suitable image class"
#endif

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

static SCNGeometryPrimitiveType GLTFSCNPrimitiveTypeForPrimitiveType(GLTFPrimitiveType type) {
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
    property.intensity = textureParams.scale;
    property.magnificationFilter = GLTFSCNFilterModeForMagFilter(textureParams.texture.sampler.magFilter);
    SCNFilterMode minFilter, mipFilter;
    GLTFSCNGetFilterModeForMinMipFilter(textureParams.texture.sampler.minMipFilter, &minFilter, &mipFilter);
    property.minificationFilter = minFilter;
    property.mipFilter = mipFilter;
    //property.contentsTransform = SCNMatrix4();
    property.wrapS = GLTFSCNWrapModeForMode(textureParams.texture.sampler.wrapS);
    property.wrapT = GLTFSCNWrapModeForMode(textureParams.texture.sampler.wrapT);
    property.mappingChannel = textureParams.texCoord;
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
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    SCNMaterial *defaultMaterial = [SCNMaterial material];
    defaultMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    defaultMaterial.locksAmbientWithDiffuse = YES;
    CGFloat defaultBaseColorFactor[] = { 1.0, 1.0, 1.0, 1.0 };
    defaultMaterial.diffuse.contents = (__bridge id)CGColorCreate(colorSpace, &defaultBaseColorFactor[0]);
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
        } else {
            SCNMaterialProperty *baseColorProperty = scnMaterial.diffuse;
            simd_float4 rgba = material.metallicRoughness.baseColorFactor;
            CGFloat rgbad[] = { rgba[0], rgba[1], rgba[2], rgba[3] };
            baseColorProperty.contents = (__bridge id)CGColorCreate(colorSpace, &rgbad[0]);
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
            emissiveProperty.contents = (__bridge id)CGColorCreate(colorSpace, &rgbad[0]);
        }
        
        scnMaterial.doubleSided = material.isDoubleSided;
        scnMaterial.transparencyMode = SCNTransparencyModeDefault;
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
                GLTFBuffer *indexBuffer = indexBufferView.buffer;
                
                assert(primitive.indices.componentType == GLTFComponentTypeUnsignedShort ||
                       primitive.indices.componentType == GLTFComponentTypeUnsignedInt);
                indexSize = primitive.indices.componentType == GLTFComponentTypeUnsignedShort ? sizeof(UInt16) : sizeof(UInt32);
                assert(indexBufferView.stride == 0 || indexBufferView.stride == indexSize);
                indexCount = (int)primitive.indices.count;
                indexData = [NSData dataWithBytesNoCopy:(void *)indexBuffer.data.bytes + indexBufferView.offset + indexAccessor.offset
                                                         length:indexCount * indexSize
                                                   freeWhenDone:NO];
            }
            SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:indexData
                                                                        primitiveType:GLTFSCNPrimitiveTypeForPrimitiveType(primitive.primitiveType)
                                                                       primitiveCount:GLTFSCNPrimitiveCountForVertexCount(primitive.primitiveType, indexCount)
                                                                        bytesPerIndex:indexSize];
            
            //int attrIndex = 0;
            NSMutableArray *geometrySources = [NSMutableArray arrayWithCapacity:primitive.attributes.count];
            for (NSString *key in primitive.attributes.allKeys) {
                GLTFAccessor *attrAccessor = primitive.attributes[key];
                GLTFBufferView *attrBufferView = attrAccessor.bufferView;
                GLTFBuffer *attrBuffer = attrBufferView.buffer;
                //vertexCount = (int)attrAccessor.count;
                size_t bytesPerComponent = GLTFSCNBytesPerComponentForAccessor(attrAccessor);
                size_t componentCount = GLTFSCNComponentCountForAccessor(attrAccessor);
                size_t formatSize = bytesPerComponent * componentCount;
                NSData *attrData = [NSData dataWithBytesNoCopy:(void *)attrBuffer.data.bytes + attrBufferView.offset + attrAccessor.offset
                                                        length:attrAccessor.count * formatSize
                                                  freeWhenDone:NO];
                SCNGeometrySource *source = [SCNGeometrySource geometrySourceWithData:attrData
                                                                             semantic:GLTFSCNGeometrySourceSemanticForSemantic(key)
                                                                          vectorCount:vertexCount
                                                                      floatComponents:(attrAccessor.componentType == GLTFComponentTypeFloat)
                                                                  componentsPerVector:componentCount
                                                                    bytesPerComponent:bytesPerComponent
                                                                           dataOffset:0
                                                                           dataStride:formatSize];
                [geometrySources addObject:source];
                //++attrIndex;
            }
            
            SCNGeometry *geometry = [SCNGeometry geometryWithSources:geometrySources elements:@[element]];
            geometry.firstMaterial = material ?: defaultMaterial;
            [geometries addObject:geometry];
        }
        geometryArraysForIdentifiers[mesh.identifier] = geometries;
    }
    
    NSMutableDictionary<NSUUID *, SCNNode *> *nodesForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFNode *node in asset.nodes) {
        SCNNode *scnNode = [SCNNode node];
        if (node.mesh) {
            scnNode.geometry = geometryArraysForIdentifiers[node.mesh.identifier].firstObject;
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
