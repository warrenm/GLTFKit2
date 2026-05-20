#import "GLTFWorkflowHelper.h"
#import "GLTFLogging.h"

#import <Metal/Metal.h>

static NSString *const GLTFWorkflowConversionShaderSource = @""
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"static constant float3 dielectricF0 { 0.04, 0.04, 0.04 };\n"
"struct sg_to_rm_params {\n"
"    float4 diffuseColorFactor;\n"
"    float3 specularFactor;\n"
"    float glossinessFactor;\n"
"    uint unpremultiplyDiffuse;\n"
"    uint unpremultiplySpecular;\n"
"};\n"
"static float max_component(float3 v) {\n"
"    return max(max(v.x, v.y), v.z);\n"
"}\n"
"static float y_from_rgb(float3 rgb) {\n"
"    return dot(rgb, float3(0.2126, 0.7152, 0.0722));\n"
"}\n"
"static float solve_metallic(float diffuse, float specular, float oneMinusSpecularStrength) {\n"
"    if (specular < dielectricF0.r) {\n"
"        return 0;\n"
"    }\n"
"    float a = dielectricF0.r;\n"
"    float b = diffuse * oneMinusSpecularStrength / (1 - dielectricF0.r) + specular - 2 * dielectricF0.r;\n"
"    float c = dielectricF0.r - specular;\n"
"    float D = b * b - 4 * a * c;\n"
"    return saturate((-b + sqrt(D)) / (2 * a));\n"
"}\n"
"static void get_rm_from_sg(float3 diffuse, float3 specular, float glossiness,\n"
"                           thread float3 *outBaseColor, thread float *outMetallic, thread float *outRoughness)\n"
"{\n"
"    const float epsilon = 1e-6;\n"
"    float oneMinusSpecularStrength = 1 - max_component(specular);\n"
"    float metallic = solve_metallic(y_from_rgb(diffuse), y_from_rgb(specular), oneMinusSpecularStrength);\n"
"    float3 baseColorFromDiffuse = diffuse * (oneMinusSpecularStrength / (1 - dielectricF0.r) / max(1 - metallic, epsilon));\n"
"    float3 baseColorFromSpecular = specular - (dielectricF0 * (1 - metallic)) * (1 / max(metallic, epsilon));\n"
"    float3 baseColor = mix(baseColorFromDiffuse, baseColorFromSpecular, metallic * metallic);\n"
"    *outBaseColor = baseColor;\n"
"    *outMetallic = metallic;\n"
"    *outRoughness = 1 - glossiness;\n"
"}\n"
"kernel void sg_to_mr(texture2d<float, access::sample> diffuseTexture            [[texture(0)]],\n"
"                     texture2d<float, access::sample> specularGlossinessTexture [[texture(1)]],\n"
"                     texture2d<float, access::write> baseColorTexture           [[texture(2)]],\n"
"                     texture2d<float, access::write> roughnessMetallicTexture   [[texture(3)]],\n"
"                     constant sg_to_rm_params &params [[buffer(0)]],\n"
"                     uint2 index [[thread_position_in_grid]])\n"
"{\n"
"    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);\n"
"    uint outputWidth = baseColorTexture.get_width();\n"
"    uint outputHeight = baseColorTexture.get_height();\n"
"    if (index.x >= outputWidth || index.y >= outputHeight) { return; }\n"
"    float2 uv { float(index.x) / outputWidth, float(index.y) / outputHeight };\n"
"    float3 diffuseColor = {0};\n"
"    float opacity = 1;\n"
"    if (!is_null_texture(diffuseTexture)) {\n"
"        float4 sampledDiffuse = diffuseTexture.sample(linearSampler, uv);\n"
"        if (params.unpremultiplyDiffuse) {\n"
"            sampledDiffuse.rgb /= sampledDiffuse.a;\n"
"        }\n"
"        diffuseColor.rgb = sampledDiffuse.rgb;\n"
"        opacity = sampledDiffuse.a;\n"
"    }\n"
"    float3 specularColor = params.specularFactor;\n"
"    float glossiness = params.glossinessFactor;\n"
"    if (!is_null_texture(specularGlossinessTexture)) {\n"
"        float4 sampledSpecGloss = specularGlossinessTexture.sample(linearSampler, uv);\n"
"        if (params.unpremultiplySpecular) {\n"
"            specularColor *= (sampledSpecGloss.rgb / sampledSpecGloss.a);\n"
"        } else {\n"
"            specularColor *= sampledSpecGloss.rgb;\n"
"        }\n"
"        glossiness *= sampledSpecGloss.a;\n"
"    }\n"
"    float3 baseColor;\n"
"    float metallic, roughness;\n"
"    get_rm_from_sg(diffuseColor.rgb, specularColor, glossiness, &baseColor, &metallic, &roughness);\n"
"    baseColorTexture.write(float4(baseColor, opacity), ushort2(index));\n"
"    roughnessMetallicTexture.write(float4(0.0, roughness, metallic, 1.0), ushort2(index));\n"
"}\n";

typedef struct {
    simd_float4 diffuseColorFactor;
    simd_float3 specularFactor;
    float glossinessFactor;
    uint32_t unpremultiplyDiffuse;
    uint32_t unpremultiplySpecular;
} GLTFWorkflowHelperParams;

static float GLTFMaxVectorComponent(simd_float3 v) {
    return MAX(MAX(v.x, v.y), v.z);
}

static float GLTFLuminanceFromRGB(simd_float3 rgba) {
    return 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2];
}

static simd_float3 GLTFLerpFloat3(simd_float3 a, simd_float3 b, float t) {
    return a + (b - a) * t;
}

static const simd_float3 GLTFDielectricSpecular = (simd_float3){ 0.04, 0.04, 0.04 };

static float GLTFSolveForMetallicFactor(float diffuse, float specular, float oneMinusSpecularStrength) {
    if (specular < GLTFDielectricSpecular.r) {
        return 0;
    }

    float a = GLTFDielectricSpecular.r;
    float b = diffuse * oneMinusSpecularStrength / (1 - GLTFDielectricSpecular.r) + specular - 2 * GLTFDielectricSpecular.r;
    float c = GLTFDielectricSpecular.r - specular;
    float D = b * b - 4 * a * c;

    return simd_clamp((-b + sqrtf(D)) / (2 * a), 0, 1);
}

static void GLTFGetMetallicRoughnessFromSpecularGlossiness(simd_float3 diffuse, simd_float3 specular, float glossiness,
                                                           simd_float3 *outBaseColor, float *outMetallic, float *outRoughness)
{
    const float epsilon = 1e-6;
    float oneMinusSpecularStrength = 1 - GLTFMaxVectorComponent(specular);
    float metallic = GLTFSolveForMetallicFactor(GLTFLuminanceFromRGB(diffuse),
                                                GLTFLuminanceFromRGB(specular),
                                                oneMinusSpecularStrength);

    simd_float3 baseColorFromDiffuse = diffuse * (oneMinusSpecularStrength / (1 - GLTFDielectricSpecular.r) / MAX(1 - metallic, epsilon));
    simd_float3 baseColorFromSpecular = specular - (GLTFDielectricSpecular * (1 - metallic)) * (1 / MAX(metallic, epsilon));
    simd_float3 baseColor = GLTFLerpFloat3(baseColorFromDiffuse, baseColorFromSpecular, metallic * metallic); // TODO: clamp?

    *outBaseColor = baseColor;
    *outMetallic = metallic;
    *outRoughness = 1 - glossiness;
}

static BOOL GLTFMetalDeviceHasWritableSRGBFormats(id<MTLDevice> device) {
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        if (@available(macOS 13.0, iOS 16.0, tvOS 16.0, *)) {
            if([device supportsFamily:MTLGPUFamilyMetal3]) {
                return YES;
            }
        }
        return [device supportsFamily:MTLGPUFamilyApple2];
    } else {
        return NO;
    }
}

@interface GLTFWorkflowHelper ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) GLTFPBRSpecularGlossinessParams *specularGlossiness;
@property (nonatomic, assign) simd_float4 baseColorFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *baseColorTexture;
@property (nonatomic, assign) float metallicFactor;
@property (nonatomic, assign) float roughnessFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *metallicRoughnessTexture;
@end

@implementation GLTFWorkflowHelper

- (instancetype)initWithSpecularGlossiness:(GLTFPBRSpecularGlossinessParams *)specularGlossiness
                                    device:(nonnull id<MTLDevice>)device
{
    if (self = [super init]) {
        _device = device;

        _specularGlossiness = specularGlossiness;

        _baseColorFactor = (simd_float4){ 1, 1, 1, 1 };
        _metallicFactor = 0.0;
        _roughnessFactor = 0.0;

        [self convert];
    }
    return self;
}

- (void)convert {
    // If we have either a diffuse texture or a specular-glossiness texture, we have
    // a per-texel base color and metallic-roughness dependency, so we will generate
    // textures for both.
    BOOL hasTextures = (self.specularGlossiness.diffuseTexture != nil) ||
    (self.specularGlossiness.specularGlossinessTexture != nil);

    simd_float3 diffuseFactor = self.specularGlossiness.diffuseFactor.xyz;
    float opacityFactor = self.specularGlossiness.diffuseFactor.w;
    simd_float3 specularFactor = self.specularGlossiness.specularFactor;
    float glossinessFactor = self.specularGlossiness.glossinessFactor;
    simd_float3 albedo;
    float metallicFactor, roughnessFactor;
    GLTFGetMetallicRoughnessFromSpecularGlossiness(diffuseFactor, specularFactor, glossinessFactor,
                                                   &albedo, &metallicFactor, &roughnessFactor);

    if (!hasTextures) {
        self.baseColorFactor = simd_make_float4(albedo, opacityFactor);
        self.metallicFactor = metallicFactor;
        self.roughnessFactor = roughnessFactor;
    } else {
        MTLPixelFormat baseColorFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        if (!GLTFMetalDeviceHasWritableSRGBFormats(_device)) {
            static dispatch_once_t warnOnce;
            dispatch_once(&warnOnce, ^{
                GLTFLogWarning(@"[GLTFKit2] WARNING: This device does not support writable sRGB pixel formats. "
                               "Specular-glossiness conversion workflows may produce incorrect colors. "
                               "This will only be logged once per session.");
            });
            baseColorFormat = MTLPixelFormatBGRA8Unorm;
        }
        
        BOOL shouldUnpremultiplyDiffuse = NO;
        id<MTLTexture> _Nullable diffuseTexture = [self newTextureForGLTFTexture: self.specularGlossiness.diffuseTexture.texture
                                                                            sRGB:YES
                                                          outShouldUnpremultiply:&shouldUnpremultiplyDiffuse];
        BOOL shouldUnpremultiplySpecular = NO;
        id<MTLTexture> _Nullable specularGlossinessTexture = [self newTextureForGLTFTexture:self.specularGlossiness.specularGlossinessTexture.texture
                                                                                       sRGB:YES
                                                                     outShouldUnpremultiply:&shouldUnpremultiplySpecular];

        GLTFWorkflowHelperParams params;
        params.diffuseColorFactor = self.specularGlossiness.diffuseFactor;
        params.specularFactor = self.specularGlossiness.specularFactor;
        params.glossinessFactor = self.specularGlossiness.glossinessFactor;
        params.unpremultiplyDiffuse = (uint32_t)shouldUnpremultiplyDiffuse;
        params.unpremultiplySpecular = (uint32_t)shouldUnpremultiplySpecular;

        NSUInteger outputWidth = MAX(MAX(diffuseTexture.width, specularGlossinessTexture.width), 1);
        NSUInteger outputHeight = MAX(MAX(diffuseTexture.height, specularGlossinessTexture.height), 1);

        MTLTextureDescriptor *baseColorDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:baseColorFormat
                                                                                                 width:outputWidth
                                                                                                height:outputHeight
                                                                                             mipmapped:YES];
        baseColorDesc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        id<MTLTexture> baseColorTexture = [self.device newTextureWithDescriptor:baseColorDesc];

        MTLTextureDescriptor *metallicDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                width:outputWidth
                                                                                               height:outputHeight
                                                                                            mipmapped:YES];
        metallicDesc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        id<MTLTexture> metallicRoughnessTexture = [self.device newTextureWithDescriptor:metallicDesc];

        NSError *error = nil;
        id<MTLLibrary> library = [self.device newLibraryWithSource:GLTFWorkflowConversionShaderSource options:nil error:&error];

        id<MTLFunction> kernelFunction = [library newFunctionWithName:@"sg_to_mr"];
        id<MTLComputePipelineState> computePipelineState = [self.device newComputePipelineStateWithFunction:kernelFunction error:&error];

        id<MTLCommandQueue> commandQueue = [self.device newCommandQueue];

        MTLSize tileSize = MTLSizeMake(8, 4, 1);
        MTLSize threadgroupCount = MTLSizeMake(((outputWidth + tileSize.width - 1) / tileSize.width),
                                               ((outputHeight + tileSize.height - 1) / tileSize.height),
                                               1);

        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
        [computeEncoder setComputePipelineState:computePipelineState];
        [computeEncoder setTexture:diffuseTexture atIndex:0];
        [computeEncoder setTexture:specularGlossinessTexture atIndex:1];
        [computeEncoder setTexture:baseColorTexture atIndex:2];
        [computeEncoder setTexture:metallicRoughnessTexture atIndex:3];
        [computeEncoder setBytes:&params length:sizeof(GLTFWorkflowHelperParams) atIndex:0];
        [computeEncoder dispatchThreadgroups:threadgroupCount threadsPerThreadgroup:tileSize];
        [computeEncoder endEncoding];

        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder generateMipmapsForTexture:baseColorTexture];
        [blitEncoder generateMipmapsForTexture:metallicRoughnessTexture];
        [blitEncoder endEncoding];

        [commandBuffer commit];

        self.baseColorTexture = [[GLTFTextureParams alloc] init];
        self.baseColorTexture.texCoord = self.specularGlossiness.diffuseTexture.texCoord;
        self.baseColorTexture.transform = self.specularGlossiness.diffuseTexture.transform;
        self.baseColorTexture.texture = [[GLTFTexture alloc] init];
        self.baseColorTexture.texture.sampler = self.specularGlossiness.diffuseTexture.texture.sampler;
        self.baseColorTexture.texture.source = [[GLTFImage alloc] initWithTexture:baseColorTexture];

        self.baseColorFactor = self.specularGlossiness.diffuseFactor;

        // Although both diffuse and specular color influence base color, metallic and roughness
        // are derived entirely from specular/glossiness, so if we didn't have a specular-glossiness
        // map, we can infer that metallic/roughness are actually constants. If we *did* have a specular-glossiness
        // map, the metallic and roughness factors are baked into the metallic-roughness texture and should
        // not be separately applied by the renderer.
        if (specularGlossinessTexture) {
            self.metallicRoughnessTexture = [[GLTFTextureParams alloc] init];
            self.metallicRoughnessTexture.texCoord = self.specularGlossiness.specularGlossinessTexture.texCoord;
            self.metallicRoughnessTexture.transform = self.specularGlossiness.specularGlossinessTexture.transform;
            self.metallicRoughnessTexture.texture = [[GLTFTexture alloc] init];
            self.metallicRoughnessTexture.texture.sampler = self.specularGlossiness.specularGlossinessTexture.texture.sampler;
            self.metallicRoughnessTexture.texture.source = [[GLTFImage alloc] initWithTexture:metallicRoughnessTexture];
            self.metallicFactor = 1.0;
            self.roughnessFactor = 1.0;
        } else {
            self.metallicFactor = metallicFactor;
            self.roughnessFactor = roughnessFactor;
        }
    }
}

- (id<MTLTexture> _Nullable)newTextureForGLTFTexture:(GLTFTexture *_Nullable)gltfTexture
                                                sRGB:(BOOL)sRGB
                              outShouldUnpremultiply:(BOOL *)shouldUnpremultiply
{
    *shouldUnpremultiply = NO;
    if (gltfTexture == nil) {
        return nil;
    }
    if (gltfTexture.basisUSource) {
        return [gltfTexture.basisUSource newTextureWithDevice:self.device];
    }
    GLTFImage *source = gltfTexture.webpSource ?: gltfTexture.source;
    CGImageRef _Nullable cgImage = source.newCGImage;
    if (cgImage) {
        CGImageAlphaInfo alpha = CGImageGetAlphaInfo(cgImage);
        if (alpha == kCGImageAlphaPremultipliedLast || alpha == kCGImageAlphaPremultipliedFirst) {
            *shouldUnpremultiply = YES;
        }
        id<MTLTexture> texture = [self newTextureFromImage:cgImage sRGB:sRGB];
        CGImageRelease(cgImage);
        return texture;
    }
    // glTF texture seems to have an image, but we don't know how to convert it to a Metal texture.
    GLTFLogWarning(@"[GLTFKit2] WARNING: Conversion from glTF texture to Metal texture in specular-glossiness workflow failed");
    return nil;
}

- (id<MTLTexture>)newTextureFromImage:(CGImageRef)image sRGB:(BOOL)sRGB {
    int width = (int)CGImageGetWidth(image);
    int height = (int)CGImageGetHeight(image);
    int bytesPerRow = width * 4;
    void *data = malloc(bytesPerRow * height);
    memset(data, 0, bytesPerRow * height);
    CGColorSpaceRef colorSpace = sRGB ? CGColorSpaceCreateWithName(kCGColorSpaceSRGB) : CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    CGBitmapInfo bitmapInfo = (uint32_t)kCGImageByteOrder32Little | (uint32_t)kCGImageAlphaPremultipliedFirst;
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:sRGB ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm
                                                                                                 width:width
                                                                                                height:height
                                                                                             mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:textureDescriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:data bytesPerRow:bytesPerRow];

    CGContextRelease(context);
    CFRelease(colorSpace);
    free(data);

    return texture;
}

@end
