
#import "GLTFAssetWriter.h"

#define CGLTF_WRITE_IMPLEMENTATION
#import "cgltf_write.h"

GLTFAssetExportOption const GLTFAssetExportAsBinary = @"GLTFAssetExportAsBinary";

static void *gltf_alloc(void *user, cgltf_size size) {
    (void)user;
    return malloc(size);
}

static void gltf_free(void *user, void *ptr) {
    (void)user;
    free(ptr);
}

@interface GLTFSerializedExtension : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSData *data;

@end

@implementation GLTFSerializedExtension

- (void)copyShallowlyToCGLTFExtension:(cgltf_extension *)outExtension {
    outExtension->name = (char *)self.name.UTF8String;
    outExtension->data = (char *)self.data.bytes;
}

@end

NSData * _Nullable GLTFExtrasFromJSONObject(_Nullable id obj, NSError **outError) {
    if (obj == nil) {
        return nil;
    }

    NSError *internalError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:&internalError];

    if (outError && internalError) {
        *outError = internalError;
    }
    return data;
}

NSArray<GLTFSerializedExtension *> *_Nullable GLTFSerializeExtensions(NSDictionary *extensions, NSError **outError) {
    if (extensions.count == 0) {
        return @[];
    }

    __block NSError *internalError = nil;
    NSMutableArray *serializedExtensions = [NSMutableArray arrayWithCapacity:extensions.count];
    [extensions enumerateKeysAndObjectsUsingBlock:^(NSString *key, id extensionObject, BOOL *stop) {
        GLTFSerializedExtension *serializedExtension = [GLTFSerializedExtension new];
        serializedExtension.name = key;
        NSData *data = [NSJSONSerialization dataWithJSONObject:extensionObject 
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&internalError];
        serializedExtension.data = data;
        if (serializedExtension.name && serializedExtension.data) {
            [serializedExtensions addObject:serializedExtension];
        } else {
            *stop = YES;
        }
    }];

    if (outError && internalError) {
        *outError = internalError;
    }
    return serializedExtensions;
}

void GLTFCopyTextureProperties(GLTFTextureParams *textureParams, cgltf_texture_view *textureView,
                               NSArray<GLTFTexture *> *sourceTextures, cgltf_texture *exportTextures)
{
    if (textureParams == nil) {
        return; // Nothing to do
    }
    if (textureParams.texture) {
        NSInteger textureIndex = [sourceTextures indexOfObject:textureParams.texture];
        if (textureIndex != NSNotFound) {
            textureView->texture = exportTextures + textureIndex;
        }
    }
    textureView->texcoord = (cgltf_int)textureParams.texCoord;
    textureView->scale = textureParams.scale;
    if (textureParams.transform) {
        textureView->has_transform = 1;
        simd_float2 scale = textureParams.transform.scale;
        memcpy(textureView->transform.scale, &scale, sizeof(float) * 2);
        simd_float2 offset = textureParams.transform.offset;
        memcpy(textureView->transform.offset, &offset, sizeof(float) * 2);
        textureView->transform.rotation = textureParams.transform.rotation;
        if (textureParams.transform.hasTexCoord) {
            textureView->transform.has_texcoord = 1;
            textureView->transform.texcoord = textureParams.transform.texCoord;
        }
    }
    // textureView->extras
    // textureView->extensions_count
    // textureView->extensions
}

@interface GLTFAssetWriter ()
@property (class, nonatomic, readonly) dispatch_queue_t writerQueue;
@property (nonatomic, strong) GLTFAsset *asset;
@end

static dispatch_queue_t _writerQueue;

@implementation GLTFAssetWriter

+ (dispatch_queue_t)writerQueue {
    if (_writerQueue == nil) {
        _writerQueue = dispatch_queue_create("com.metalbyexample.gltfkit2.asset-writer", DISPATCH_QUEUE_CONCURRENT);
    }
    return _writerQueue;
}

+ (void)writeAsset:(GLTFAsset *)asset
             toURL:(NSURL *)url
           options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
   progressHandler:(nullable GLTFAssetURLExportProgressHandler)handler
{
    dispatch_async(self.writerQueue, ^{
        GLTFAssetWriter *writer = [[GLTFAssetWriter alloc] init];
        [writer syncSerializeAsset:asset options:options handler:^(float progress,
                                                                   GLTFAssetStatus status,
                                                                   NSData * _Nullable data,
                                                                   NSError * _Nullable error,
                                                                   BOOL * _Nonnull stop) {
            handler(progress, status, error, stop);
        }];
    });
}

+ (void)serializeAsset:(GLTFAsset *)asset
               options:(nullable NSDictionary<GLTFAssetExportOption, id> *)options
       progressHandler:(nullable GLTFAssetDataExportProgressHandler)handler
{
    dispatch_async(self.writerQueue, ^{
        GLTFAssetWriter *writer = [[GLTFAssetWriter alloc] init];
        [writer syncSerializeAsset:asset options:options handler:handler];
    });
}

- (void)syncSerializeAsset:(GLTFAsset *)asset
                   options:(NSDictionary *)options
                   handler:(GLTFAssetDataExportProgressHandler)handler
{
    NSError *internalError = nil;

    cgltf_memory_options memory = { gltf_alloc, gltf_free, NULL };

    cgltf_data *gltf = calloc(1, sizeof(cgltf_data));
    gltf->memory = memory;

    gltf->buffers = calloc(asset.buffers.count, sizeof(cgltf_buffer));
    gltf->buffers_count = asset.buffers.count;
    for (size_t i = 0; i < asset.buffers.count; ++i) {
        GLTFBuffer *buffer = asset.buffers[i];
        cgltf_buffer *gltfBuffer = gltf->buffers + i;
        if (buffer.name) {
            gltfBuffer->name = strdup(buffer.name.UTF8String);
        }
        gltfBuffer->size = buffer.length;
        if (buffer.uri) {
            gltfBuffer->uri = strdup(buffer.uri.absoluteString.UTF8String);
        }
        // gltfBuffer->extras
        // gltfBuffer->extensions_count
        // gltfBuffer->extensions
    }

    gltf->buffer_views = calloc(asset.bufferViews.count, sizeof(cgltf_buffer_view));
    gltf->buffer_views_count = asset.bufferViews.count;
    for (size_t i = 0; i < asset.bufferViews.count; ++i) {
        GLTFBufferView *bufferView = asset.bufferViews[i];
        cgltf_buffer_view *gltfBufferView = gltf->buffer_views + i;
        if (bufferView.name) {
            gltfBufferView->name = strdup(bufferView.name.UTF8String);
        }
        if (bufferView.buffer) {
            NSInteger bufferIndex = [asset.buffers indexOfObject:bufferView.buffer];
            if (bufferIndex != NSNotFound) {
                gltfBufferView->buffer = gltf->buffers + bufferIndex;
            }
        }
        gltfBufferView->offset = bufferView.offset;
        gltfBufferView->size = bufferView.length;
        gltfBufferView->stride = bufferView.stride;
        // gltfBufferView->extras
        // gltfBufferView->extensions_count
        // gltfBufferView->extensions
    }

    gltf->accessors = calloc(asset.accessors.count, sizeof(cgltf_accessor));
    gltf->accessors_count = asset.accessors.count;
    for (size_t i = 0; i < asset.accessors.count; ++i) {
        GLTFAccessor *accessor = asset.accessors[i];
        cgltf_accessor *gltfAccessor = gltf->accessors + i;
        if (accessor.name) {
            gltfAccessor->name = strdup(accessor.name.UTF8String);
        }
        gltfAccessor->component_type = (cgltf_component_type)accessor.componentType;
        gltfAccessor->normalized = (cgltf_bool)accessor.isNormalized;
        gltfAccessor->type = (cgltf_type)accessor.dimension;
        gltfAccessor->offset = accessor.offset;
        gltfAccessor->count = accessor.count;
        gltfAccessor->stride = 0; // accessor.stride;
        if (accessor.bufferView) {
            NSInteger bufferViewIndex = [asset.bufferViews indexOfObject:accessor.bufferView];
            if (bufferViewIndex != NSNotFound) {
                gltfAccessor->buffer_view = gltf->buffer_views + bufferViewIndex;
            }
        }
        gltfAccessor->has_min = (cgltf_bool)(accessor.minValues.count > 0);
        for (int c = 0; c < accessor.minValues.count; ++c) {
            gltfAccessor->min[c] = accessor.minValues[c].floatValue;
        }
        gltfAccessor->has_max = (cgltf_bool)(accessor.maxValues.count > 0);
        for (int c = 0; c < accessor.maxValues.count; ++c) {
            gltfAccessor->max[c] = accessor.maxValues[c].floatValue;
        }
        gltfAccessor->is_sparse = 0;
        // gltfAccessor->sparse
        // gltfAccessor->extras
        // gltfAccessor->extensions_count
        // gltfAccessor->extensions
    }

    gltf->cameras = calloc(asset.cameras.count, sizeof(cgltf_camera));
    gltf->cameras_count = asset.cameras.count;
    for (size_t i = 0; i < asset.cameras.count; ++i) {
        GLTFCamera *camera = asset.cameras[i];
        cgltf_camera *gltfCamera = gltf->cameras + i;
        if (camera.name) {
            gltfCamera->name = strdup(camera.name.UTF8String);
        }
        if (camera.perspective != nil) {
            gltfCamera->type = cgltf_camera_type_perspective;
            gltfCamera->data.perspective.yfov = camera.perspective.yFOV;
            if (camera.perspective.aspectRatio > 0.0) {
                gltfCamera->data.perspective.has_aspect_ratio = true;
                gltfCamera->data.perspective.aspect_ratio = camera.perspective.aspectRatio;
            }
            gltfCamera->data.perspective.znear = camera.zNear;
            if (camera.zFar > 0.0) {
                gltfCamera->data.perspective.has_zfar = true;
                gltfCamera->data.perspective.zfar = camera.zFar;
            }
        } else if (camera.orthographic) {
            gltfCamera->type = cgltf_camera_type_orthographic;
            gltfCamera->data.orthographic.xmag = camera.orthographic.xMag;
            gltfCamera->data.orthographic.ymag = camera.orthographic.yMag;
            gltfCamera->data.orthographic.znear = camera.zNear;
            gltfCamera->data.orthographic.zfar = camera.zFar;
        } else {
            gltfCamera->type = cgltf_camera_type_invalid;
        }
        //gltfCamera->extras
        //gltfCamera->extensions_count
        //gltfCamera->extensions
    }

    gltf->lights = calloc(asset.lights.count, sizeof(cgltf_light));
    gltf->lights_count = asset.lights.count;
    for (size_t i = 0; i < asset.lights.count; ++i) {
        GLTFLight *light = asset.lights[i];
        cgltf_light *gltfLight = gltf->lights + i;
        if (light.name) {
            gltfLight->name = strdup(light.name.UTF8String);
        }
        simd_float3 rgb = light.color;
        memcpy(&gltfLight->color[0], &rgb, sizeof(float) * 3);
        gltfLight->intensity = light.intensity;
        gltfLight->type = (cgltf_light_type)light.type;
        gltfLight->range = light.range;
        gltfLight->spot_inner_cone_angle = light.innerConeAngle;
        gltfLight->spot_outer_cone_angle = light.outerConeAngle;
        //gltfLight->extras
    }

    gltf->images = calloc(asset.images.count, sizeof(cgltf_image));
    gltf->images_count = asset.images.count;
    for (size_t i = 0; i < asset.images.count; ++i) {
        GLTFImage *image = asset.images[i];
        cgltf_image *gltfImage = gltf->images + i;
        if (image.name) {
            gltfImage->name = strdup(image.name.UTF8String);
        }
        if (image.uri) {
            gltfImage->uri = strdup(image.uri.lastPathComponent.UTF8String);
        }
        if (image.bufferView) {
            NSInteger bufferViewIndex = [asset.bufferViews indexOfObject:image.bufferView];
            if (bufferViewIndex != NSNotFound) {
                gltfImage->buffer_view = gltf->buffer_views + bufferViewIndex;
            }
        }
        if (image.mimeType) {
            gltfImage->mime_type = strdup(image.mimeType.UTF8String);
        }
        //gltfImage->extras
        //gltfImage->extensions_count
        //gltfImage->extensions
    }

    gltf->samplers = calloc(asset.samplers.count, sizeof(cgltf_sampler));
    gltf->samplers_count = asset.samplers.count;
    for (size_t i = 0; i < asset.samplers.count; ++i) {
        GLTFTextureSampler *sampler = asset.samplers[i];
        cgltf_sampler *gltfSampler = gltf->samplers + i;
        if (sampler.name) {
            gltfSampler->name = strdup(sampler.name.UTF8String);
        }
        gltfSampler->mag_filter = (cgltf_int)sampler.magFilter;
        gltfSampler->min_filter = (cgltf_int)sampler.minMipFilter;
        gltfSampler->wrap_s = (cgltf_int)sampler.wrapS;
        gltfSampler->wrap_t = (cgltf_int)sampler.wrapT;
        //gltfSampler->extras
        //gltfSampler->extensions_count
        //gltfSampler->extensions
    }

    gltf->textures = calloc(asset.textures.count, sizeof(cgltf_texture));
    gltf->textures_count = asset.textures.count;
    for (size_t i = 0; i < asset.textures.count; ++i) {
        GLTFTexture *texture = asset.textures[i];
        cgltf_texture *gltfTexture = gltf->textures + i;
        if (texture.name) {
            gltfTexture->name = strdup(texture.name.UTF8String);
        }
        if (texture.source) {
            NSInteger sourceIndex = [asset.images indexOfObject:texture.source];
            if (sourceIndex != NSNotFound) {
                gltfTexture->image = gltf->images + sourceIndex;
            }
        }
        if (texture.sampler) {
            NSInteger samplerIndex = [asset.samplers indexOfObject:texture.sampler];
            if (samplerIndex != NSNotFound) {
                gltfTexture->sampler = gltf->samplers + samplerIndex;
            }
        }
        //gltfTexture->has_basisu
        //gltfTexture->basisu_image
        //gltfTexture->extras
        //gltfTexture->extensions_count
        //gltfTexture->extensions
    }

    gltf->materials = calloc(asset.materials.count, sizeof(cgltf_material));
    gltf->materials_count = asset.materials.count;
    for (size_t i = 0; i < asset.materials.count; ++i) {
        GLTFMaterial *material = asset.materials[i];
        cgltf_material *gltfMaterial = gltf->materials + i;
        if (material.name) {
            gltfMaterial->name = strdup(material.name.UTF8String);
        }
        gltfMaterial->alpha_mode = (cgltf_alpha_mode)material.alphaMode;
        gltfMaterial->alpha_cutoff = (cgltf_float)material.alphaCutoff;
        gltfMaterial->double_sided = (cgltf_bool)material.isDoubleSided;
        gltfMaterial->unlit = (cgltf_bool)material.isUnlit;
        if (material.metallicRoughness != nil) {
            gltfMaterial->has_pbr_metallic_roughness = 1;
            GLTFCopyTextureProperties(material.metallicRoughness.baseColorTexture,
                                      &gltfMaterial->pbr_metallic_roughness.base_color_texture,
                                      asset.textures, gltf->textures);
            GLTFCopyTextureProperties(material.metallicRoughness.metallicRoughnessTexture,
                                      &gltfMaterial->pbr_metallic_roughness.metallic_roughness_texture,
                                      asset.textures, gltf->textures);
            simd_float4 baseColorFactor = material.metallicRoughness.baseColorFactor;
            memcpy(gltfMaterial->pbr_metallic_roughness.base_color_factor, &baseColorFactor, sizeof(float) * 4);
            gltfMaterial->pbr_metallic_roughness.metallic_factor = material.metallicRoughness.metallicFactor;
            gltfMaterial->pbr_metallic_roughness.roughness_factor = material.metallicRoughness.roughnessFactor;
            // gltfMaterial->pbr_metallic_roughness.extras
        }
        gltfMaterial->has_pbr_specular_glossiness = 0; // Obsolete
        if (material.clearcoat != nil) {
            gltfMaterial->has_clearcoat = 1;
            GLTFCopyTextureProperties(material.clearcoat.clearcoatTexture,
                                      &gltfMaterial->clearcoat.clearcoat_texture,
                                      asset.textures, gltf->textures);
            GLTFCopyTextureProperties(material.clearcoat.clearcoatRoughnessTexture,
                                      &gltfMaterial->clearcoat.clearcoat_roughness_texture,
                                      asset.textures, gltf->textures);
            GLTFCopyTextureProperties(material.clearcoat.clearcoatNormalTexture,
                                      &gltfMaterial->clearcoat.clearcoat_normal_texture,
                                      asset.textures, gltf->textures);
            gltfMaterial->clearcoat.clearcoat_factor = material.clearcoat.clearcoatFactor;
            gltfMaterial->clearcoat.clearcoat_roughness_factor = material.clearcoat.clearcoatRoughnessFactor;
        }
        if (material.transmission != nil) {
            gltfMaterial->has_transmission = 1;
            GLTFCopyTextureProperties(material.transmission.transmissionTexture,
                                      &gltfMaterial->transmission.transmission_texture,
                                      asset.textures, gltf->textures);
            gltfMaterial->transmission.transmission_factor = material.transmission.transmissionFactor;
        }
        if (material.volume != nil) {
            gltfMaterial->has_volume = 1;
            GLTFCopyTextureProperties(material.volume.thicknessTexture,
                                      &gltfMaterial->volume.thickness_texture,
                                      asset.textures, gltf->textures);
            gltfMaterial->volume.thickness_factor = material.volume.thicknessFactor;
            simd_float3 attenuationColor = material.volume.attenuationColor;
            memcpy(gltfMaterial->volume.attenuation_color, &attenuationColor, sizeof(float) * 3);
            gltfMaterial->volume.attenuation_distance = material.volume.attenuationDistance;
        }
        if (material.indexOfRefraction != nil) {
            gltfMaterial->has_ior = 1;
            gltfMaterial->ior.ior = material.indexOfRefraction.floatValue;
        }
        if (material.specular != nil) {
            gltfMaterial->has_specular = 1;
            GLTFCopyTextureProperties(material.specular.specularTexture,
                                      &gltfMaterial->specular.specular_texture,
                                      asset.textures, gltf->textures);
            GLTFCopyTextureProperties(material.specular.specularColorTexture,
                                      &gltfMaterial->specular.specular_color_texture,
                                      asset.textures, gltf->textures);
            simd_float3 specularColorFactor = material.specular.specularColorFactor;
            memcpy(gltfMaterial->specular.specular_color_factor, &specularColorFactor, sizeof(float) * 3);
            gltfMaterial->specular.specular_factor = material.specular.specularFactor;
        }
        if (material.sheen != nil) {
            gltfMaterial->has_sheen = 1;
            GLTFCopyTextureProperties(material.sheen.sheenColorTexture,
                                      &gltfMaterial->sheen.sheen_color_texture,
                                      asset.textures, gltf->textures);
            simd_float3 sheenColorFactor = material.sheen.sheenColorFactor;
            memcpy(gltfMaterial->sheen.sheen_color_factor, &sheenColorFactor, sizeof(float) * 3);
            GLTFCopyTextureProperties(material.sheen.sheenRoughnessTexture,
                                      &gltfMaterial->sheen.sheen_roughness_texture,
                                      asset.textures, gltf->textures);
            gltfMaterial->sheen.sheen_roughness_factor = material.sheen.sheenRoughnessFactor;
        }
        if (material.emissive != nil) {
            GLTFCopyTextureProperties(material.emissive.emissiveTexture,
                                      &gltfMaterial->emissive_texture,
                                      asset.textures, gltf->textures);
            simd_float3 emissiveFactor = material.emissive.emissiveFactor;
            memcpy(gltfMaterial->emissive_factor, &emissiveFactor, sizeof(float) * 3);
            if (material.emissive.emissiveStrength != 1.0) {
                gltfMaterial->has_emissive_strength = 1;
                gltfMaterial->emissive_strength.emissive_strength = material.emissive.emissiveStrength;
            }
        }
        if (material.iridescence != nil) {
            gltfMaterial->has_iridescence = 1;

            gltfMaterial->iridescence.iridescence_factor = material.iridescence.iridescenceFactor;
            GLTFCopyTextureProperties(material.iridescence.iridescenceTexture,
                                      &gltfMaterial->iridescence.iridescence_texture,
                                      asset.textures, gltf->textures);
            gltfMaterial->iridescence.iridescence_ior = material.iridescence.iridescenceIndexOfRefraction;
            gltfMaterial->iridescence.iridescence_thickness_min = material.iridescence.iridescenceThicknessMinimum;
            gltfMaterial->iridescence.iridescence_thickness_max = material.iridescence.iridescenceThicknessMaximum;
            GLTFCopyTextureProperties(material.iridescence.iridescenceThicknessTexture,
                                      &gltfMaterial->iridescence.iridescence_thickness_texture,
                                      asset.textures, gltf->textures);
        }
        GLTFCopyTextureProperties(material.normalTexture,
                                  &gltfMaterial->normal_texture,
                                  asset.textures, gltf->textures);
        GLTFCopyTextureProperties(material.occlusionTexture,
                                  &gltfMaterial->occlusion_texture,
                                  asset.textures, gltf->textures);

        // gltfMaterial->extras
        // gltfMaterial->extensions_count
        // gltfMaterial->extensions
    }

    //meshes

    //TODO: skins
    //TODO: animations

    gltf->nodes = calloc(asset.nodes.count, sizeof(cgltf_node));
    gltf->nodes_count = asset.nodes.count;
    for (size_t i = 0; i < asset.nodes.count; ++i) {
        GLTFNode *node = asset.nodes[i];
        cgltf_node *gltfNode = gltf->nodes + i;
        if (node.name) {
            gltfNode->name = strdup(node.name.UTF8String);
        }

        gltfNode->has_translation = 0;
        gltfNode->has_rotation = 0;
        gltfNode->has_scale = 0;
        gltfNode->has_matrix = 1;
        simd_float4x4 M = node.matrix;
        // TODO: Write TRS properties instead if our transform is an animation target
        memcpy(&gltfNode->matrix[0], &M, sizeof(float) * 16);

        if (node.parentNode) {
            NSInteger parentIndex = [asset.nodes indexOfObject:node.parentNode];
            if (parentIndex != NSNotFound) {
                gltfNode->parent = gltf->nodes + parentIndex;
            }
        }

        if (node.childNodes.count > 0) {
            gltfNode->children = calloc(node.childNodes.count, sizeof(cgltf_node *));
            gltfNode->children_count = node.childNodes.count;
            for (int j = 0; j < node.childNodes.count; ++j) {
                NSInteger childIndex = [asset.nodes indexOfObject:node.childNodes[j]];
                if (childIndex != NSNotFound) {
                    gltfNode->children[gltfNode->children_count++] = gltf->nodes + childIndex;
                }
            }
        }

        if (node.mesh != nil) {
            NSInteger meshIndex = [asset.meshes indexOfObject:node.mesh];
            if (meshIndex != NSNotFound) {
                gltfNode->mesh = gltf->meshes + meshIndex;
            }
        }

        if (node.camera != nil) {
            NSInteger cameraIndex = [asset.cameras indexOfObject:node.camera];
            if (cameraIndex != NSNotFound) {
                gltfNode->camera = gltf->cameras + cameraIndex;
            }
        }

        if (node.light != nil) {
            NSInteger lightIndex = [asset.lights indexOfObject:node.light];
            if (lightIndex != NSNotFound) {
                gltfNode->light = gltf->lights + lightIndex;
            }
        }

        gltfNode->skin = NULL;
        gltfNode->weights = NULL;
        gltfNode->weights_count = 0;

        gltfNode->has_mesh_gpu_instancing = 0;
        //gltfNode->extras
        //gltfNode->extensions;
        //gltfNode->extensions_count;
    }

    gltf->scenes = calloc(asset.scenes.count, sizeof(cgltf_scene));
    gltf->scenes_count = asset.scenes.count;
    for (size_t i = 0; i < asset.scenes.count; ++i) {
        GLTFScene *scene = asset.scenes[i];
        cgltf_scene *gltfScene = gltf->scenes + i;
        gltfScene->name = strdup(scene.name.UTF8String);
        gltfScene->nodes = calloc(scene.nodes.count, sizeof(cgltf_node *));
        for (size_t j = 0; j < scene.nodes.count; ++j) {
            NSInteger nodeIndex = [asset.nodes indexOfObject:scene.nodes[j]];
            if (nodeIndex != NSNotFound) {
                gltfScene->nodes[gltfScene->nodes_count++] = gltf->nodes + nodeIndex;
            }
        }
        //gltfScene->extras;
        //gltfScene->extensions;
        //gltfScene->extensions_count;
    }
    
    if (asset.defaultScene) {
        NSInteger defaultSceneIndex = [asset.scenes indexOfObject:asset.defaultScene];
        if (defaultSceneIndex != NSNotFound) {
            gltf->scene = gltf->scenes + defaultSceneIndex;
        }
    }
    
    // TODO: variants

    if (asset.copyright) {
        gltf->asset.copyright = strdup(asset.copyright.UTF8String);
    }
    gltf->asset.generator = strdup("GLTFKit2 v0.6 (based on cgltf v1.13)");
    gltf->asset.version = strdup("2.0");
    gltf->asset.min_version = NULL;
    // TODO: asset-level extensions

    cgltf_options gltfOptions;
    bzero(&gltfOptions, sizeof(cgltf_options));
    gltfOptions.type = cgltf_file_type_gltf;
    gltfOptions.memory = memory;
    //gltfOptions.file = cgltf_file_options;

    cgltf_size bufferSize = cgltf_write(&gltfOptions, NULL, 0, gltf);
    void *buffer = realloc(NULL, bufferSize);
    cgltf_size outSize = cgltf_write(&gltfOptions, (char *)buffer, bufferSize, gltf);

    // We omit the trailing NIL, since we treat the buffer as binary data, not a string
    NSData *data = [NSData dataWithBytesNoCopy:buffer length:(outSize - 1) freeWhenDone:YES];

    cgltf_free(gltf);
    gltf = NULL;

    BOOL stop = NO;
    handler(1.0, GLTFAssetStatusComplete, data, internalError, &stop);
}

@end
