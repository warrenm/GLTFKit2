#  GLTFKit2

GLTFKit2 is an efficient glTF loader and exporter for Objective-C and Swift.

This project is a spiritual successor of the [GLTFKit](https://github.com/warrenm/GLTFKit) project, with many of the same aims, but some notable differences. GLTFKit2:

 - includes import and export, while GLTFKit was read-only.
 - strives to be as interoperable as possible, with extensions for Model I/O, SceneKit, and QuickLook. 
 - tries to retain all of the information from the asset file, meaning extensions and extras are available to client code even if they are unrecognized by the loader.
 - uses cgltf and JSMN internally to load the JSON portion of glTF files, which is more efficient than parsing with `NSJSONSerialization`.

## Usage

### Using the Framework

The GLTFKit2 Xcode project is completely self-contained and can be used to build a Cocoa framework for macOS. If you want to use GLTFKit2 as a framework, link to it and embed it in your target. You can also opt to include the source directly in your app target.

### Loading Assets

To load a glTF 2.0 model, import `<GLTFKit2/GLTFKit2.h>` and use the `GLTFAsset` class. Since assets can take a while to load, prefer to use the async loading methods.

**Objective-C**:

```obj-c
[GLTFAsset loadAssetWithURL:url
                    options:@{}
                    handler:^(float progress, 
                              GLTFAssetStatus status, 
                              GLTFAsset *asset, 
                              NSError *error, 
                              BOOL *stop)
{
    // Check for completion and/or error, use asset if complete, etc.
}
```

**Swift**:

```swift
GLTFAsset.load(with: url, options: [:]) { (progress, status, maybeAsset, maybeError, _) in
    // Check for completion and/or error, use asset if complete, etc.
}
```

The URL must be a local file URL. Loading of remote assets and resources is not supported.

### Interoperating with SceneKit

The framework can be used to easily transform glTF assets into `SCNScene`s to interoperate with SceneKit.

First, load the asset as shown above. Then, to get the default scene of a glTF asset, use the `SCNScene` class extension method `+[SCNScene sceneWithGLTFAsset:]`.

## Status and Conformance

Below is a checklist of glTF features and their current level of support.

### Status

#### Encodings
- [x] JSON
- [x] Binary (.glb)

#### Buffer Storage
- [x] External references (`buffer.uri`)
- [x] Base-64 encoded buffers

#### Well-Known Vertex Accessor Semantics
  
- [x] POSITION
- [x] NORMAL
- [x] TANGENT
- [x] TEXCOORD_0
- [x] TEXCOORD_1
- [x] COLOR_0
- [ ] JOINTS_0
- [ ] WEIGHTS_0

#### Primitive Types
- [ ] Points
- [ ] Lines
- [ ] Line Loop
- [ ] Line Strip
- [x] Triangles
- [x] Triangle Strip
- [ ] Triangle Fan

#### Images
- [x] External image references (`image.uri`)
- [x] Base-64 encoded images
- [x] PNG
- [x] JPEG
- [x] TIFF
- [ ] OpenEXR
- [ ] Radiance
- [ ] KTX2 / Basis Universal

#### Materials
- [x] Base color factor
- [x] Metallic factor
- [x] Roughness factor
- [x] Emissive factor
- [x] Base color map
- [x] Metallic-roughness map
- [ ] Occlusion map
- [x] Emissive map
- [ ] Normal texture scale
- [x] Alpha mode
    - [x] Opaque alpha mode
    - [x] Mask alpha mode
    - [x] Blend alpha mode
- [x] Double-sided materials

#### Samplers
- [x] Wrap mode
- [x] Minification/magnification filters
- [x] Mipmaps

#### Cameras
- [x] Perspective cameras
- [ ] Orthographic cameras

#### Morph Targets
- [ ] Morph targets
  
#### Animation
- [x] Translation animations
- [x] Rotation animations
- [x] Scale animations
- [ ] Morph target weight animations
- [x] Linear interpolation
- [ ] Discrete animations
- [ ] Cubic spline interpolation

#### Skinning
- [ ] Joint matrix calculation

#### Sparse Accessors
- [ ] Sparse accessors

#### Extensions
 - [ ] KHR_draco_mesh_compression (_No support planned._)
 - [ ] KHR_lights_punctual
 - [ ] KHR_materials_clearcoat
 - [ ] KHR_materials_ior
 - [ ] KHR_materials_pbrSpecularGlossiness
 - [ ] KHR_materials_sheen
 - [ ] KHR_materials_specular
 - [ ] KHR_materials_transmission
 - [ ] KHR_materials_unlit
 - [ ] KHR_materials_variants
 - [ ] KHR_materials_volume (_No support planned._)
 - [ ] KHR_mesh_quantization (_No support planned._)
 - [ ] KHR_techniques_webgl (_No support planned._)
 - [ ] KHR_texture_basisu
 - [x] KHR_texture_transform
 - [ ] KHR_xmp
 - [ ] ADOBE_materials_clearcoat_specular (_No support planned._)
 - [ ] ADOBE_materials_thin_transparency (_No support planned._)
 - [ ] AGI_articulations (_No support planned._)
 - [ ] AGI_stk_metadata (_No support planned._)
 - [ ] CESIUM_primitive_outline (_No support planned._)
 - [ ] EXT_lights_image_based
 - [ ] EXT_mesh_gpu_instancing (_No support planned._)
 - [ ] EXT_meshopt_compression (_No support planned._)
 - [ ] EXT_texture_webp (_No support planned._)
 - [ ] FB_geometry_metadata (_No support planned._)
 - [ ] MSFT_lod (_No support planned._)
 - [ ] MSFT_packing_normalRoughnessMetallic
 - [ ] MSFT_packing_occlusionRoughnessMetallic
 - [ ] MSFT_texture_dds (_No support planned._)

### Conformance

This implementation is known to be **non-conforming** to the glTF 2.0 specification and is under active development.

## Contributing

Pull requests are welcome, but will be audited strictly in order to maintain code style. If you have any concerns about contributing, please raise an issue on Github so we can talk about it.

## License

    Copyright (c) 2021 Warren Moore

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
    documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
    Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
    WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
