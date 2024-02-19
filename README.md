#  GLTFKit2

GLTFKit2 is an efficient glTF loader and exporter for Objective-C and Swift.

This project is a spiritual successor of the [GLTFKit](https://github.com/warrenm/GLTFKit) project, with many of the same aims, but some notable differences. GLTFKit2:

 - includes import and export (WIP), while GLTFKit was read-only.
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

### Using Draco Mesh Decompression

GLTFKit2 supports meshes compressed with the [Draco geometry compression library](https://github.com/google/draco) through a plugin system. To activate Draco decompression support, implement the `GLTFDracoMeshDecompressor` protocol in your target, then set the `dracoDecompressorClassName` property on `GLTFAsset` to the name of the conforming class. The framework will then use the supplied class to convert compressed mesh data into glTF primitives which are suitable for rendering. A sample Draco decompressor class is provided in the macOS GLTFViewer target. You are responsible for compiling and linking to the Draco library itself in your own target. If you would prefer not to compile the library yourself, consider using [DracoSwift](https://github.com/warrenm/DracoSwift).

### Using KTX2 with Basis Universal

GLTFKit2 optionally supports the [KHR_texture_basisu](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_texture_basisu) extension for loading KTX2 with Basis Universal textures via [libktx](https://github.com/KhronosGroup/KTX-Software). This repository contains a pre-built XCFramework with Universal binaries for macOS and iOS. If you wish to use KTX2 textures in your target, simply add `GLTFKit2/deps/libktx/ktx.xcframework` to the GLTFKit2 **framework** target, and it will automatically be detected and used to load KTX2 textures, whether embedded or stored externally in ktx2 files.

## Status and Conformance

Below is a checklist of glTF features and their current level of support.

### Status

- [x] Import
- [ ] Export

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
- [x] JOINTS_0
- [x] WEIGHTS_0

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

#### Materials
- [x] Base color factor
- [x] Metallic factor
- [x] Roughness factor
- [x] Emissive factor
- [x] Base color map
- [x] Metallic-roughness map
- [x] Occlusion map
- [x] Emissive map
- [x] Normal texture scale
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
- [x] Morph targets
  
#### Animation
- [x] Translation animations
- [x] Rotation animations
- [x] Scale animations
- [x] Morph target weight animations
- [x] Linear interpolation
- [ ] Discrete animations
- [ ] Cubic spline interpolation

#### Skinning
- [x] Joint matrix calculation

#### Sparse Accessors
- [x] Sparse accessors

#### Extensions
 - [x] EXT_mesh_gpu_instancing
 - [x] EXT_meshopt_compression
 - [x] KHR_draco_mesh_compression (via plug-in)
 - [x] KHR_lights_punctual
 - [x] KHR_materials_clearcoat
 - [x] KHR_emissive_strength
 - [x] KHR_materials_ior
 - [x] KHR_materials_iridescence
 - [x] KHR_materials_sheen
 - [x] KHR_materials_specular
 - [x] KHR_materials_transmission
 - [x] KHR_materials_unlit
 - [ ] KHR_materials_variants
 - [x] KHR_materials_volume
 - [x] KHR_mesh_quantization
 - [x] KHR_texture_basisu
 - [x] KHR_texture_transform
 - [ ] KHR_xmp_json_ld

 Extension support indicates that an extension's features are available as first-class objects through the `GLTFAsset` API. Not all features are available after an asset is bridged to another framework (e.g. SceneKit) that does not have support for such features. In particular, no Apple-provided rendering engine supports transmission or volume rendering at this time.

### Conformance

This implementation is known to be **non-conforming** to the glTF 2.0 specification and is under active development.

## Contributing

Pull requests are welcome, but will be audited strictly in order to maintain code style. If you have any concerns about contributing, please raise an issue on Github so we can talk about it.

## License

    Copyright (c) 2021—2024 Warren Moore

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
