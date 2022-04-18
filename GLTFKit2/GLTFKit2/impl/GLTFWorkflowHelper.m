
#import "GLTFWorkflowHelper.h"

#import <Metal/Metal.h>

static NSString *const GLTFWorkflowConversionShaderSource = @""
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"static constant float3 diffuseF0 { 0.04, 0.04, 0.04 };\n"
"struct sg_to_rm_params {\n"
"    float4 diffuseColorFactor;\n"
"    float3 specularFactor;\n"
"    float glossinessFactor;\n"
"};\n"
"static float max_component(float3 v) {\n"
"    return max(max(v.x, v.y), v.z);\n"
"}\n"
"static float y_from_rgb(float3 rgb) {\n"
"    return dot(rgb, float3(0.2126, 0.7152, 0.0722));\n"
"}\n"
"static float solve_metallic(float diffuse, float specular, float oneMinusSpecularStrength) {\n"
"    if (specular < diffuseF0.r) {\n"
"        return 0;\n"
"    }\n"
"    float a = diffuseF0.r;\n"
"    float b = diffuse * oneMinusSpecularStrength / (1 - diffuseF0.r) + specular - 2 * diffuseF0.r;\n"
"    float c = diffuseF0.r - specular;\n"
"    float D = b * b - 4 * a * c;\n"
"    return saturate((-b + sqrt(D)) / (2 * a));\n"
"}\n"
"static void get_rm_from_sg(float3 diffuse, float3 specular, float glossiness,\n"
"                           thread float3 *outBaseColor, thread float *outMetallic, thread float *outRoughness)\n"
"{\n"
"    const float epsilon = 1e-6;\n"
"    float oneMinusSpecularStrength = 1 - max_component(specular);\n"
"    float metallic = solve_metallic(y_from_rgb(diffuse), y_from_rgb(specular), oneMinusSpecularStrength);\n"
"    float3 baseColorFromDiffuse = diffuse * (oneMinusSpecularStrength / (1 - diffuseF0.r) / max(1 - metallic, epsilon));\n"
"    float3 baseColorFromSpecular = specular - (diffuseF0 * (1 - metallic)) * (1 / max(metallic, epsilon));\n"
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
"    float4 diffuseColor = params.diffuseColorFactor;\n"
"    if (!is_null_texture(diffuseTexture)) {\n"
"        float4 sampledDiffuse = diffuseTexture.sample(linearSampler, uv);\n"
"        sampledDiffuse.rgb /= sampledDiffuse.a;\n"
"        diffuseColor *= sampledDiffuse;\n"
"    }\n"
"    float3 specularColor = params.specularFactor;\n"
"    float glossiness = params.glossinessFactor;\n"
"    if (!is_null_texture(specularGlossinessTexture)) {\n"
"        float4 sampledSpecGloss = specularGlossinessTexture.sample(linearSampler, uv);\n"
"        specularColor *= (sampledSpecGloss.rgb / sampledSpecGloss.a);\n"
"        glossiness *= sampledSpecGloss.a;\n"
"    }\n"
"    float3 baseColor;\n"
"    float metallic, roughness;\n"
"    get_rm_from_sg(diffuseColor.rgb, specularColor, glossiness, &baseColor, &metallic, &roughness);\n"
"    baseColorTexture.write(float4(baseColor * diffuseColor.a, diffuseColor.a), ushort2(index));\n"
"    roughnessMetallicTexture.write(float4(0.0, roughness * roughness, metallic, 1.0), ushort2(index));\n"
"}\n";

typedef struct {
    simd_float4 diffuseColorFactor;
    simd_float3 specularFactor;
    float glossinessFactor;
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

@interface GLTFWorkflowHelper ()
@property (nonatomic, strong) GLTFPBRSpecularGlossinessParams *specularGlossiness;
@property (nonatomic, assign) simd_float4 baseColorFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *baseColorTexture;
@property (nonatomic, assign) float metallicFactor;
@property (nonatomic, assign) float roughnessFactor;
@property (nonatomic, nullable, strong) GLTFTextureParams *metallicRoughnessTexture;
@end

@implementation GLTFWorkflowHelper

- (instancetype)initWithSpecularGlossiness:(GLTFPBRSpecularGlossinessParams *)specularGlossiness {
    if (self = [super init]) {
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

    if (!hasTextures) {
        simd_float3 diffuseFactor = self.specularGlossiness.diffuseFactor.xyz;
        float opacityFactor = self.specularGlossiness.diffuseFactor.w;
        simd_float3 specularFactor = self.specularGlossiness.specularFactor;
        float glossinessFactor = self.specularGlossiness.glossinessFactor;
        simd_float3 albedo;
        float metallic, roughness;
        GLTFGetMetallicRoughnessFromSpecularGlossiness(diffuseFactor, specularFactor, glossinessFactor,
                                                       &albedo, &metallic, &roughness);
        self.baseColorFactor = simd_make_float4(albedo, opacityFactor);
        self.metallicFactor = metallic;
        self.roughnessFactor = roughness;
    } else {
        CGImageRef diffuseImage = [self.specularGlossiness.diffuseTexture.texture.source newCGImage];
        CGImageRef specularGlossinessImage = [self.specularGlossiness.specularGlossinessTexture.texture.source newCGImage];

        int diffuseWidth = diffuseImage ? (int)CGImageGetWidth(diffuseImage) : 0;
        int diffuseHeight = diffuseImage ? (int)CGImageGetHeight(diffuseImage) : 0;

        int specularWidth = specularGlossinessImage ? (int)CGImageGetWidth(specularGlossinessImage) : 0;
        int specularHeight = specularGlossinessImage ? (int)CGImageGetHeight(specularGlossinessImage) : 0;

        int outputWidth = MAX(diffuseWidth, specularWidth);
        int outputHeight = MAX(diffuseHeight, specularHeight);

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();

        //[MTLCaptureManager.sharedCaptureManager startCaptureWithDevice:device];

        id<MTLTexture> diffuseTexture = nil;
        if (diffuseWidth > 0 && diffuseHeight > 0) {
            diffuseTexture = [self newTextureFromImage:diffuseImage device:device];
        }

        id<MTLTexture> specularGlossinessTexture = nil;
        if (specularWidth > 0 && specularHeight > 0) {
            specularGlossinessTexture = [self newTextureFromImage:specularGlossinessImage device:device];
        }

        MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;
        MTLTextureDescriptor *baseColorDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                                                 width:outputWidth
                                                                                                height:outputHeight
                                                                                             mipmapped:NO];
        baseColorDesc.usage = MTLTextureUsageShaderWrite;
        id<MTLTexture> baseColorTexture = [device newTextureWithDescriptor:baseColorDesc];

        MTLTextureDescriptor *metallicDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                                                 width:outputWidth
                                                                                                height:outputHeight
                                                                                             mipmapped:NO];
        metallicDesc.usage = MTLTextureUsageShaderWrite;
        id<MTLTexture> metallicRoughnessTexture = [device newTextureWithDescriptor:metallicDesc];

        NSError *error = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:GLTFWorkflowConversionShaderSource options:nil error:&error];

        id<MTLFunction> kernelFunction = [library newFunctionWithName:@"sg_to_mr"];
        id<MTLComputePipelineState> computePipelineState = [device newComputePipelineStateWithFunction:kernelFunction error:&error];

        id<MTLCommandQueue> commandQueue = [device newCommandQueue];

        GLTFWorkflowHelperParams params;
        params.diffuseColorFactor = self.specularGlossiness.diffuseFactor;
        params.specularFactor = self.specularGlossiness.specularFactor;
        params.glossinessFactor = self.specularGlossiness.glossinessFactor;

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

        #if TARGET_OS_OSX
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder synchronizeResource:baseColorTexture];
        [blitEncoder synchronizeResource:metallicRoughnessTexture];
        [blitEncoder endEncoding];
        #endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        CGImageRef baseColorImage = [self newImageFromTexture:baseColorTexture];
        CGImageRef metallicRoughnessImage = [self newImageFromTexture:metallicRoughnessTexture];

        self.baseColorTexture = [[GLTFTextureParams alloc] init];
        self.baseColorTexture.texture = [[GLTFTexture alloc] init];
        self.baseColorTexture.texture.sampler = self.specularGlossiness.diffuseTexture.texture.sampler;
        self.baseColorTexture.texture.source = [[GLTFImage alloc] initWithCGImage:baseColorImage];

        self.metallicRoughnessTexture = [[GLTFTextureParams alloc] init];
        self.metallicRoughnessTexture.texture = [[GLTFTexture alloc] init];
        self.metallicRoughnessTexture.texture.sampler = self.specularGlossiness.specularGlossinessTexture.texture.sampler;
        self.metallicRoughnessTexture.texture.source = [[GLTFImage alloc] initWithCGImage:metallicRoughnessImage];

        CGImageRelease(baseColorImage);
        CGImageRelease(metallicRoughnessImage);
        CGImageRelease(diffuseImage);
        CGImageRelease(specularGlossinessImage);

        //[MTLCaptureManager.sharedCaptureManager stopCapture];
    }
}

- (id<MTLTexture>)newTextureFromImage:(CGImageRef)image device:(id<MTLDevice>)device {
    int width = (int)CGImageGetWidth(image);
    int height = (int)CGImageGetHeight(image);
    int bytesPerRow = width * 4;
    void *data = malloc(bytesPerRow * height);
    memset(data, 0, bytesPerRow * height);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    int bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB
                                                                                                 width:width
                                                                                                height:height
                                                                                             mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:textureDescriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:data bytesPerRow:bytesPerRow];

    CGContextRelease(context);
    CFRelease(colorSpace);
    free(data);

    return texture;
}

- (CGImageRef)newImageFromTexture:(id<MTLTexture>)texture {
    int width = (int)texture.width;
    int height = (int)texture.height;
    int bytesPerRow = width * 4;
    void *data = malloc(bytesPerRow * height);
    [texture getBytes:data bytesPerRow:bytesPerRow fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    int bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CFRelease(colorSpace);
    free(data);
    return image;
}

@end
