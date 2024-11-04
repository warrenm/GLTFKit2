
#import "GLTFKTX2Support.h"

NSString *const GLTFMediaTypeKTX2 = @"image/ktx2";

#ifdef GLTF_BUILD_WITH_KTX2
#include <ktx.h>

MTLPixelFormat GLTFMetalPixelFormatForVkFormat(int vkformat);

static BOOL GLTFMetalDeviceSupportsETC(id<MTLDevice> device) {
    if (@available(macos 10.15, iOS 13.0, tvOS 13.0, *)) {
        return [device supportsFamily:MTLGPUFamilyApple8] ||
               [device supportsFamily:MTLGPUFamilyApple7] ||
               [device supportsFamily:MTLGPUFamilyApple6] ||
               [device supportsFamily:MTLGPUFamilyApple5] ||
               [device supportsFamily:MTLGPUFamilyApple4] ||
               [device supportsFamily:MTLGPUFamilyApple3] ||
               [device supportsFamily:MTLGPUFamilyApple2];
    }
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    if (@available(iOS 12.0, *)) {
        return [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily5_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v1];
    }
#endif
#if TARGET_OS_TV
    if (@available(tvOS 12.0, *)) {
        return [device supportsFeatureSet:MTLFeatureSet_tvOS_GPUFamily1_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_tvOS_GPUFamily2_v1];
    }
#endif
    return NO;
}

static BOOL GLTFMetalDeviceSupportsASTC(id<MTLDevice> device) {
    if (@available(macos 10.15, iOS 13.0, tvOS 13.0, *)) {
        return [device supportsFamily:MTLGPUFamilyApple8] ||
               [device supportsFamily:MTLGPUFamilyApple7] ||
               [device supportsFamily:MTLGPUFamilyApple6] ||
               [device supportsFamily:MTLGPUFamilyApple5] ||
               [device supportsFamily:MTLGPUFamilyApple4] ||
               [device supportsFamily:MTLGPUFamilyApple3] ||
               [device supportsFamily:MTLGPUFamilyApple2];
    }
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    if (@available(iOS 12.0, *)) {
        return [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily5_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily2_v1];
    }
#endif
#if TARGET_OS_TV
    if (@available(tvOS 12.0, *)) {
        return [device supportsFeatureSet:MTLFeatureSet_tvOS_GPUFamily1_v1] ||
               [device supportsFeatureSet:MTLFeatureSet_tvOS_GPUFamily2_v1];
    }
#endif
    return NO;
}

static BOOL GLTFMetalDeviceSupportsBC(id<MTLDevice> device) {
    BOOL hasRuntimeSupport = NO;
    if (@available(macos 11.0, iOS 16.4, tvOS 16.4, *)) {
        hasRuntimeSupport = [device supportsBCTextureCompression];
    }
    if (@available(macos 10.15, iOS 13.0, tvOS 13.0, *)) {
        return [device supportsFamily:MTLGPUFamilyMac2] || hasRuntimeSupport;
    } 
    return NO;
}

id<MTLTexture> GLTFCreateTextureFromKTX2Data(NSData *data, id<MTLDevice> device) {
    KTX_error_code result;
    uint32_t flags = KTX_TEXTURE_CREATE_CHECK_GLTF_BASISU_BIT |
                     KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT |
                     KTX_TEXTURE_CREATE_SKIP_KVDATA_BIT;
    ktxTexture2 *ktx2Texture = NULL;
    result = ktxTexture2_CreateFromMemory(data.bytes, data.length, flags, &ktx2Texture);
    if (result != KTX_SUCCESS) {
        return nil;
    }

    if (ktxTexture2_NeedsTranscoding(ktx2Texture)) {
        BOOL deviceHasASTC = GLTFMetalDeviceSupportsASTC(device);
        BOOL deviceHasETC2 = GLTFMetalDeviceSupportsETC(device);
        BOOL deviceHasBC = GLTFMetalDeviceSupportsBC(device);

        khr_df_model_e colorModel = ktxTexture2_GetColorModel_e(ktx2Texture);

        ktx_transcode_fmt_e tf = KTX_TTF_NOSELECTION;
        if (colorModel == KHR_DF_MODEL_UASTC && deviceHasASTC) {
            tf = KTX_TTF_ASTC_4x4_RGBA;
        } else if (colorModel == KHR_DF_MODEL_ETC1S && deviceHasETC2) {
            tf = KTX_TTF_ETC;
        } else if (deviceHasASTC) {
            tf = KTX_TTF_ASTC_4x4_RGBA;
        } else if (deviceHasETC2) {
            tf = KTX_TTF_ETC2_RGBA;
        } else if (deviceHasBC) {
            tf = KTX_TTF_BC3_RGBA;
        }

        result = ktxTexture2_TranscodeBasis(ktx2Texture, tf, 0);
    }

    MTLTextureType type = MTLTextureType2D;
    MTLPixelFormat pixelFormat = GLTFMetalPixelFormatForVkFormat(ktx2Texture->vkFormat);

    BOOL genMipmaps = ktx2Texture->generateMipmaps;
    NSUInteger levelCount = ktx2Texture->numLevels;
    NSUInteger baseWidth = ktx2Texture->baseWidth;
    NSUInteger baseHeight = ktx2Texture->baseHeight;
    NSUInteger baseDepth = ktx2Texture->baseDepth;
    NSUInteger maxMipLevelCount = floor(log2(MAX(baseWidth, baseHeight))) + 1;
    NSUInteger storedMipLevelCount = genMipmaps ? maxMipLevelCount : levelCount;

    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor new];
    textureDescriptor.textureType = type;
    textureDescriptor.pixelFormat = pixelFormat;
    textureDescriptor.width = baseWidth;
    textureDescriptor.height = (ktx2Texture->numDimensions > 1) ? baseHeight : 1;
    textureDescriptor.depth = (ktx2Texture->numDimensions > 2) ? baseDepth : 1;
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    textureDescriptor.storageMode = MTLStorageModeShared;
#if TARGET_OS_OSX
    if (!device.hasUnifiedMemory) {
        textureDescriptor.storageMode = MTLStorageModeManaged;
    }
#endif
    textureDescriptor.arrayLength = 1;
    textureDescriptor.mipmapLevelCount = storedMipLevelCount;

    id<MTLTexture> texture = [device newTextureWithDescriptor:textureDescriptor];

    ktxTexture *ktx1Texture = (ktxTexture *)ktx2Texture;

    ktx_uint32_t layer = 0, faceSlice = 0;
    for (ktx_uint32_t level = 0; level < ktx2Texture->numLevels; ++level) {
        ktx_size_t offset = 0;
        result = ktxTexture_GetImageOffset(ktx1Texture, level, layer, faceSlice, &offset);
        ktx_uint8_t *imageBytes = ktxTexture_GetData(ktx1Texture) + offset;
        ktx_uint32_t bytesPerRow = ktxTexture_GetRowPitch(ktx1Texture, level);
        ktx_size_t bytesPerImage = ktxTexture_GetImageSize(ktx1Texture, level);
        size_t levelWidth = MAX(1, (baseWidth >> level));
        size_t levelHeight = MAX(1, (baseHeight >> level));
        [texture replaceRegion:MTLRegionMake2D(0, 0, levelWidth, levelHeight)
                   mipmapLevel:level
                         slice:faceSlice
                     withBytes:imageBytes
                   bytesPerRow:bytesPerRow
                 bytesPerImage:bytesPerImage];
    }

    ktxTexture_Destroy(ktx1Texture);

    if (genMipmaps) {
        // TODO:
        // id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        // id<MTLBlitCommandEncoder> mipmapCommandEncoder = [commandBuffer blitCommandEncoder];
        // [mipmapCommandEncoder generateMipmapsForTexture:texture];
        // [mipmapCommandEncoder endEncoding];
        // [commandBuffer commit];
    }

    return texture;
}

MTLPixelFormat GLTFMetalPixelFormatForVkFormat(int vkformat) {
    switch (vkformat) {
        case 9:          /* VK_FORMAT_R8_UNORM */                    return MTLPixelFormatR8Unorm;
        case 10:         /* VK_FORMAT_R8_SNORM */                    return MTLPixelFormatR8Snorm;
        case 13:         /* VK_FORMAT_R8_UINT */                     return MTLPixelFormatR8Uint;
        case 14:         /* VK_FORMAT_R8_SINT */                     return MTLPixelFormatR8Sint;
        case 16:         /* VK_FORMAT_R8G8_UNORM */                  return MTLPixelFormatRG8Unorm;
        case 17:         /* VK_FORMAT_R8G8_SNORM */                  return MTLPixelFormatRG8Snorm;
        case 20:         /* VK_FORMAT_R8G8_UINT */                   return MTLPixelFormatRG8Uint;
        case 21:         /* VK_FORMAT_R8G8_SINT */                   return MTLPixelFormatRG8Sint;
        case 37:         /* VK_FORMAT_R8G8B8A8_UNORM */              return MTLPixelFormatRGBA8Unorm;
        case 38:         /* VK_FORMAT_R8G8B8A8_SNORM */              return MTLPixelFormatRGBA8Snorm;
        case 41:         /* VK_FORMAT_R8G8B8A8_UINT */               return MTLPixelFormatRGBA8Uint;
        case 42:         /* VK_FORMAT_R8G8B8A8_SINT */               return MTLPixelFormatRGBA8Sint;
        case 43:         /* VK_FORMAT_R8G8B8A8_SRGB */               return MTLPixelFormatRGBA8Unorm_sRGB;
        case 44:         /* VK_FORMAT_B8G8R8A8_UNORM */              return MTLPixelFormatBGRA8Unorm;
        case 50:         /* VK_FORMAT_B8G8R8A8_SRGB */               return MTLPixelFormatBGRA8Unorm_sRGB;
        case 58:         /* VK_FORMAT_A2R10G10B10_UNORM_PACK32 */    return MTLPixelFormatBGR10A2Unorm;
        case 64:         /* VK_FORMAT_A2B10G10R10_UNORM_PACK32 */    return MTLPixelFormatRGB10A2Unorm;
        case 68:         /* VK_FORMAT_A2B10G10R10_UINT_PACK32 */     return MTLPixelFormatRGB10A2Uint;
        case 70:         /* VK_FORMAT_R16_UNORM */                   return MTLPixelFormatR16Unorm;
        case 71:         /* VK_FORMAT_R16_SNORM */                   return MTLPixelFormatR16Snorm;
        case 74:         /* VK_FORMAT_R16_UINT */                    return MTLPixelFormatR16Uint;
        case 75:         /* VK_FORMAT_R16_SINT */                    return MTLPixelFormatR16Sint;
        case 76:         /* VK_FORMAT_R16_SFLOAT */                  return MTLPixelFormatR16Float;
        case 77:         /* VK_FORMAT_R16G16_UNORM */                return MTLPixelFormatRG16Unorm;
        case 78:         /* VK_FORMAT_R16G16_SNORM */                return MTLPixelFormatRG16Snorm;
        case 81:         /* VK_FORMAT_R16G16_UINT */                 return MTLPixelFormatRG16Uint;
        case 82:         /* VK_FORMAT_R16G16_SINT */                 return MTLPixelFormatRG16Sint;
        case 83:         /* VK_FORMAT_R16G16_SFLOAT */               return MTLPixelFormatRG16Float;
        case 91:         /* VK_FORMAT_R16G16B16A16_UNORM */          return MTLPixelFormatRGBA16Unorm;
        case 92:         /* VK_FORMAT_R16G16B16A16_SNORM */          return MTLPixelFormatRGBA16Snorm;
        case 95:         /* VK_FORMAT_R16G16B16A16_UINT */           return MTLPixelFormatRGBA16Uint;
        case 96:         /* VK_FORMAT_R16G16B16A16_SINT */           return MTLPixelFormatRGBA16Sint;
        case 97:         /* VK_FORMAT_R16G16B16A16_SFLOAT */         return MTLPixelFormatRGBA16Float;
        case 98:         /* VK_FORMAT_R32_UINT */                    return MTLPixelFormatR32Uint;
        case 99:         /* VK_FORMAT_R32_SINT */                    return MTLPixelFormatR32Sint;
        case 100:        /* VK_FORMAT_R32_SFLOAT */                  return MTLPixelFormatR32Float;
        case 101:        /* VK_FORMAT_R32G32_UINT */                 return MTLPixelFormatRG32Uint;
        case 102:        /* VK_FORMAT_R32G32_SINT */                 return MTLPixelFormatRG32Sint;
        case 103:        /* VK_FORMAT_R32G32_SFLOAT */               return MTLPixelFormatRG32Float;
        case 107:        /* VK_FORMAT_R32G32B32A32_UINT */           return MTLPixelFormatRGBA32Uint;
        case 108:        /* VK_FORMAT_R32G32B32A32_SINT */           return MTLPixelFormatRGBA32Sint;
        case 109:        /* VK_FORMAT_R32G32B32A32_SFLOAT */         return MTLPixelFormatRGBA32Float;
        case 122:        /* VK_FORMAT_B10G11R11_UFLOAT_PACK32 */     return MTLPixelFormatRG11B10Float;
        case 123:        /* VK_FORMAT_E5B9G9R9_UFLOAT_PACK32 */      return MTLPixelFormatRGB9E5Float;
        case 126:        /* VK_FORMAT_D32_SFLOAT */                  return MTLPixelFormatDepth32Float;
        case 127:        /* VK_FORMAT_S8_UINT */                     return MTLPixelFormatStencil8;
        case 1000156000: /* VK_FORMAT_G8B8G8R8_422_UNORM */          return MTLPixelFormatGBGR422;
        case 1000156001: /* VK_FORMAT_B8G8R8G8_422_UNORM */          return MTLPixelFormatBGRG422;
        default:
            break;
    }
    if (@available(macos 11.0, macCatalyst 14.0, *)) {
        switch (vkformat) {
            case 2:          /* VK_FORMAT_R4G4B4A4_UNORM_PACK16 */       return MTLPixelFormatABGR4Unorm;
            case 4:          /* VK_FORMAT_R5G6B5_UNORM_PACK16 */         return MTLPixelFormatB5G6R5Unorm;
            case 6:          /* VK_FORMAT_R5G5B5A1_UNORM_PACK16 */       return MTLPixelFormatA1BGR5Unorm;
            case 8:          /* VK_FORMAT_A1R5G5B5_UNORM_PACK16 */       return MTLPixelFormatBGR5A1Unorm;
            case 15:         /* VK_FORMAT_R8_SRGB */                     return MTLPixelFormatR8Unorm_sRGB;
            case 22:         /* VK_FORMAT_R8G8_SRGB */                   return MTLPixelFormatRG8Unorm_sRGB;
            case 147:        /* VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK */     return MTLPixelFormatETC2_RGB8;
            case 148:        /* VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK */      return MTLPixelFormatETC2_RGB8_sRGB;
            case 149:        /* VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK */   return MTLPixelFormatETC2_RGB8A1;
            case 150:        /* VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK */    return MTLPixelFormatETC2_RGB8A1_sRGB;
            case 151:        /* VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK */   return MTLPixelFormatEAC_RGBA8;
            case 152:        /* VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK */    return MTLPixelFormatEAC_RGBA8_sRGB;
            case 153:        /* VK_FORMAT_EAC_R11_UNORM_BLOCK */         return MTLPixelFormatEAC_R11Unorm;
            case 154:        /* VK_FORMAT_EAC_R11_SNORM_BLOCK */         return MTLPixelFormatEAC_R11Snorm;
            case 155:        /* VK_FORMAT_EAC_R11G11_UNORM_BLOCK */      return MTLPixelFormatEAC_RG11Unorm;
            case 156:        /* VK_FORMAT_EAC_R11G11_SNORM_BLOCK */      return MTLPixelFormatEAC_RG11Snorm;
            case 157:        /* VK_FORMAT_ASTC_4x4_UNORM_BLOCK */        return MTLPixelFormatASTC_4x4_LDR;
            case 158:        /* VK_FORMAT_ASTC_4x4_SRGB_BLOCK */         return MTLPixelFormatASTC_4x4_sRGB;
            case 159:        /* VK_FORMAT_ASTC_5x4_UNORM_BLOCK */        return MTLPixelFormatASTC_5x4_LDR;
            case 160:        /* VK_FORMAT_ASTC_5x4_SRGB_BLOCK */         return MTLPixelFormatASTC_5x4_sRGB;
            case 161:        /* VK_FORMAT_ASTC_5x5_UNORM_BLOCK */        return MTLPixelFormatASTC_5x5_LDR;
            case 162:        /* VK_FORMAT_ASTC_5x5_SRGB_BLOCK */         return MTLPixelFormatASTC_5x5_sRGB;
            case 163:        /* VK_FORMAT_ASTC_6x5_UNORM_BLOCK */        return MTLPixelFormatASTC_6x5_LDR;
            case 164:        /* VK_FORMAT_ASTC_6x5_SRGB_BLOCK */         return MTLPixelFormatASTC_6x5_sRGB;
            case 165:        /* VK_FORMAT_ASTC_6x6_UNORM_BLOCK */        return MTLPixelFormatASTC_6x6_LDR;
            case 166:        /* VK_FORMAT_ASTC_6x6_SRGB_BLOCK */         return MTLPixelFormatASTC_6x6_sRGB;
            case 167:        /* VK_FORMAT_ASTC_8x5_UNORM_BLOCK */        return MTLPixelFormatASTC_8x5_LDR;
            case 168:        /* VK_FORMAT_ASTC_8x5_SRGB_BLOCK */         return MTLPixelFormatASTC_8x5_sRGB;
            case 169:        /* VK_FORMAT_ASTC_8x6_UNORM_BLOCK */        return MTLPixelFormatASTC_8x6_LDR;
            case 170:        /* VK_FORMAT_ASTC_8x6_SRGB_BLOCK */         return MTLPixelFormatASTC_8x6_sRGB;
            case 171:        /* VK_FORMAT_ASTC_8x8_UNORM_BLOCK */        return MTLPixelFormatASTC_8x8_LDR;
            case 172:        /* VK_FORMAT_ASTC_8x8_SRGB_BLOCK */         return MTLPixelFormatASTC_8x8_sRGB;
            case 173:        /* VK_FORMAT_ASTC_10x5_UNORM_BLOCK */       return MTLPixelFormatASTC_10x5_LDR;
            case 174:        /* VK_FORMAT_ASTC_10x5_SRGB_BLOCK */        return MTLPixelFormatASTC_10x5_sRGB;
            case 175:        /* VK_FORMAT_ASTC_10x6_UNORM_BLOCK */       return MTLPixelFormatASTC_10x6_LDR;
            case 176:        /* VK_FORMAT_ASTC_10x6_SRGB_BLOCK */        return MTLPixelFormatASTC_10x6_sRGB;
            case 177:        /* VK_FORMAT_ASTC_10x8_UNORM_BLOCK */       return MTLPixelFormatASTC_10x8_LDR;
            case 178:        /* VK_FORMAT_ASTC_10x8_SRGB_BLOCK */        return MTLPixelFormatASTC_10x8_sRGB;
            case 179:        /* VK_FORMAT_ASTC_10x10_UNORM_BLOCK */      return MTLPixelFormatASTC_10x10_LDR;
            case 180:        /* VK_FORMAT_ASTC_10x10_SRGB_BLOCK */       return MTLPixelFormatASTC_10x10_sRGB;
            case 181:        /* VK_FORMAT_ASTC_12x10_UNORM_BLOCK */      return MTLPixelFormatASTC_12x10_LDR;
            case 182:        /* VK_FORMAT_ASTC_12x10_SRGB_BLOCK */       return MTLPixelFormatASTC_12x10_sRGB;
            case 183:        /* VK_FORMAT_ASTC_12x12_UNORM_BLOCK */      return MTLPixelFormatASTC_12x12_LDR;
            case 184:        /* VK_FORMAT_ASTC_12x12_SRGB_BLOCK */       return MTLPixelFormatASTC_12x12_sRGB;
            case 1000054000: /* VK_FORMAT_PVRTC1_2BPP_UNORM_BLOCK_IMG */ return MTLPixelFormatPVRTC_RGBA_2BPP;
            case 1000054001: /* VK_FORMAT_PVRTC1_4BPP_UNORM_BLOCK_IMG */ return MTLPixelFormatPVRTC_RGBA_4BPP;
            case 1000054004: /* VK_FORMAT_PVRTC1_2BPP_SRGB_BLOCK_IMG */  return MTLPixelFormatPVRTC_RGBA_2BPP_sRGB;
            case 1000054005: /* VK_FORMAT_PVRTC1_4BPP_SRGB_BLOCK_IMG */  return MTLPixelFormatPVRTC_RGBA_4BPP_sRGB;
            default:
                break;
        }
    }
    if (@available(macos 10.11, iOS 16.4, tvOS 16.4, *)) {
        switch (vkformat) {
            case 133:        /* VK_FORMAT_BC1_RGBA_UNORM_BLOCK */    return MTLPixelFormatBC1_RGBA;
            case 134:        /* VK_FORMAT_BC1_RGBA_SRGB_BLOCK */     return MTLPixelFormatBC1_RGBA_sRGB;
            case 135:        /* VK_FORMAT_BC2_UNORM_BLOCK */         return MTLPixelFormatBC2_RGBA;
            case 136:        /* VK_FORMAT_BC2_SRGB_BLOCK */          return MTLPixelFormatBC2_RGBA_sRGB;
            case 137:        /* VK_FORMAT_BC3_UNORM_BLOCK */         return MTLPixelFormatBC3_RGBA;
            case 138:        /* VK_FORMAT_BC3_SRGB_BLOCK */          return MTLPixelFormatBC3_RGBA_sRGB;
            case 139:        /* VK_FORMAT_BC4_UNORM_BLOCK */         return MTLPixelFormatBC4_RUnorm;
            case 140:        /* VK_FORMAT_BC4_SNORM_BLOCK */         return MTLPixelFormatBC4_RSnorm;
            case 141:        /* VK_FORMAT_BC5_UNORM_BLOCK */         return MTLPixelFormatBC5_RGUnorm;
            case 142:        /* VK_FORMAT_BC5_SNORM_BLOCK */         return MTLPixelFormatBC5_RGSnorm;
            case 143:        /* VK_FORMAT_BC6H_UFLOAT_BLOCK */       return MTLPixelFormatBC6H_RGBUfloat;
            case 144:        /* VK_FORMAT_BC6H_SFLOAT_BLOCK */       return MTLPixelFormatBC6H_RGBFloat;
            case 145:        /* VK_FORMAT_BC7_UNORM_BLOCK */         return MTLPixelFormatBC7_RGBAUnorm;
            case 146:        /* VK_FORMAT_BC7_SRGB_BLOCK */          return MTLPixelFormatBC7_RGBAUnorm_sRGB;
            default:
                break;
        }
    }
    return MTLPixelFormatInvalid;
}

#endif
