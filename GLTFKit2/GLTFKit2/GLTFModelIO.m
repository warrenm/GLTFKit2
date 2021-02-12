
#import "GLTFModelIO.h"

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

@implementation MDLAsset (GLTFKit2)

+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset {
    return [self assetWithGLTFAsset:asset bufferAllocator:nil];
}

+ (instancetype)assetWithGLTFAsset:(GLTFAsset *)asset bufferAllocator:(id <MDLMeshBufferAllocator>)bufferAllocator
{
    if (bufferAllocator == nil) {
        bufferAllocator = [MDLMeshBufferDataAllocator new];
    }
    
    NSMutableDictionary <NSUUID *, MDLTexture *> *texturesForImageIdenfiers = [NSMutableDictionary dictionary];
    for (GLTFImage *image in asset.images) {
        MDLTexture *mdlTexture = nil;
        if (image.uri) {
            mdlTexture = [[MDLURLTexture alloc] initWithURL:image.uri name:image.name];
        } else {
            CGImageRef cgImage = [image createCGImage];
            int width = (int)CGImageGetWidth(cgImage);
            int height = (int)CGImageGetHeight(cgImage);
            CGDataProviderRef dataProvider = CGImageGetDataProvider(cgImage);
            CFDataRef data = CGDataProviderCopyData(dataProvider); // hate
            mdlTexture = [[MDLTexture alloc] initWithData:(__bridge NSData *)data
                                            topLeftOrigin:YES
                                                     name:image.name
                                               dimensions:(vector_int2){ width, height }
                                                rowStride:width * 4
                                             channelCount:4
                                          channelEncoding:MDLTextureChannelEncodingUInt8
                                                   isCube:NO];
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
        //mdlSampler.transform = GLTFMDLTransformFromMatrix(texture.sampler.transform);
        textureSamplersForTextureIdentifiers[texture.identifier] = mdlSampler;
    }

    NSMutableDictionary <NSUUID *, MDLMaterial *> *materialsForIdentifiers = [NSMutableDictionary dictionary];
    for (GLTFMaterial *material in asset.materials) {
        MDLPhysicallyPlausibleScatteringFunction *func = [MDLPhysicallyPlausibleScatteringFunction new];
        if (material.metallicRoughness.baseColorTexture) {
            MDLTextureSampler *baseColorSampler = textureSamplersForTextureIdentifiers[material.metallicRoughness.baseColorTexture.texture.identifier];
            baseColorSampler.mappingChannel = material.metallicRoughness.baseColorTexture.texCoord;
            func.baseColor.textureSamplerValue = baseColorSampler;
        }
        if (material.metallicRoughness.metallicRoughnessTexture) {
            MDLTextureSampler *metallicRoughnessSampler = textureSamplersForTextureIdentifiers[material.metallicRoughness.metallicRoughnessTexture.texture.identifier];
            
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
            MDLTextureSampler *normalSampler = textureSamplersForTextureIdentifiers[material.normalTexture.texture.identifier];
            normalSampler.mappingChannel = material.normalTexture.texCoord;
            func.normal.textureSamplerValue = normalSampler;
        }
        if (material.emissiveTexture) {
            MDLTextureSampler *emissiveSampler = textureSamplersForTextureIdentifiers[material.emissiveTexture.texture.identifier];
            emissiveSampler.mappingChannel = material.emissiveTexture.texCoord;
            func.emission.textureSamplerValue = emissiveSampler;
        }
        // TODO: How to represent base color/emissive factor, normal/occlusion strength, etc.?

        MDLMaterial *mdlMaterial = [[MDLMaterial alloc] initWithName:material.name scatteringFunction:func];
        mdlMaterial.materialFace = material.isDoubleSided ? MDLMaterialFaceDoubleSided : MDLMaterialFaceFront;
        materialsForIdentifiers[material.identifier] = mdlMaterial;
    }
    
    // Node -> MDLNode
    // Mesh -> MDLMesh / Primitive -> MDLSubmesh
    // Camera -> MDLCamera
    // Light -> MDLLight
    // Scene -> MDLAsset
    // Animation, Skin ??

    MDLAsset *mdlAsset = [[MDLAsset alloc] initWithBufferAllocator:bufferAllocator];
    return mdlAsset;
}

@end
