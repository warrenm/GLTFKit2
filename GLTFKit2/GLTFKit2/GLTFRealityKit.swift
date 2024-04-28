#if !os(tvOS)

import RealityKit
import Accelerate

#if os(macOS)
typealias PlatformColor = NSColor
#elseif os(iOS) || os(visionOS)
typealias PlatformColor = UIColor
#endif

func degreesFromRadians(_ rad: Float) -> Float { return rad * (180 / .pi) }

// Omit support for RealityKit entirely on platforms (such as macOS 11 Big Sur)
// that don't have the required API features from RealityKit 2. We would, of course,
// prefer to use a check that actually corresponds to the minimum supported SDKs
// (macOS 12 Monterey, iOS 15, etc.), but we lack the tools necessary to do so,
// so we fall back on language version.
// https://forums.swift.org/t/do-we-need-something-like-if-available/40349/34
#if swift(>=5.5)

fileprivate func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + t * (b - a)
}

fileprivate func lerp(_ a: simd_float3, _ b: simd_float3, _ t: Float) -> simd_float3 {
    return a + t * (b - a)
}

fileprivate func unlerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    if a == b { return 0 } // No solution; avoid division by zero
    return (t - a) / (b - a)
}

func packedStride(for accessor: GLTFAccessor) -> Int {
    var size = 0
    switch accessor.componentType {
    case .byte: fallthrough
    case .unsignedByte:
        size = 1
    case .short: fallthrough
    case .unsignedShort:
        size = 2
    case .unsignedInt: fallthrough
    case .float:
        size = 4
    default:
        break
    }
    switch accessor.dimension {
    case .scalar:
        break
    case .vector2:
        size *= 2
    case .vector3:
        size *= 3
    case .vector4:
        size *= 4
    default:
        break
    }
    return size
}

func packedFloatArray(for accessor: GLTFAccessor) -> [Float]? {
    if accessor.componentType != .float || accessor.dimension != .scalar { return nil }
    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }
    let valueCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let inputStride = bufferView.stride == 0 ? MemoryLayout<Float>.stride : bufferView.stride
    let values = [Float](unsafeUninitializedCapacity: valueCount) { buffer, initializedCount in
        bufferData.withUnsafeBytes({ rawPtr in
            // TODO: Fast path when stride == 4
            for i in 0..<valueCount {
                guard let floatPtr = rawPtr.baseAddress?.advanced(by: offset + inputStride * i)
                    .assumingMemoryBound(to: Float.self) else { initializedCount = 0; return }
                buffer[i] = floatPtr.pointee
            }
            initializedCount = valueCount
        })
    }
    return values
}

func packedFloat2Array(for accessor: GLTFAccessor, flipVertically: Bool = false) -> [SIMD2<Float>]? {
    if accessor.componentType != .float || accessor.dimension != .vector2 {
        return nil
    }

    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }

    let vertexCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let elementStride = (bufferView.stride != 0) ? bufferView.stride : packedStride(for: accessor)
    let vectors = [SIMD2<Float>](unsafeUninitializedCapacity: vertexCount) { buffer, initializedCount in
        bufferData.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
            for v in 0..<vertexCount {
                let elementPtr = basePtr.advanced(by: elementStride * v).bindMemory(to: Float.self, capacity: 3)
                buffer[v] = SIMD2(elementPtr[0], flipVertically ? 1 - elementPtr[1] : elementPtr[1])
            }
            initializedCount = vertexCount
        }
    }
    return vectors
}

func packedFloat3Array(for accessor: GLTFAccessor) -> [SIMD3<Float>]? {
    if accessor.componentType != .float || (accessor.dimension != .vector3 && accessor.dimension != .vector4) {
        return nil
    }

    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }

    let vertexCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let elementStride = (bufferView.stride != 0) ? bufferView.stride : packedStride(for: accessor)
    let vectors = [SIMD3<Float>](unsafeUninitializedCapacity: vertexCount) { buffer, initializedCount in
        bufferData.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
            for v in 0..<vertexCount {
                let elementPtr = basePtr.advanced(by: elementStride * v).bindMemory(to: Float.self, capacity: 3)
                buffer[v] = SIMD3(elementPtr[0], elementPtr[1], elementPtr[2])
            }
            initializedCount = vertexCount
        }
    }
    return vectors
}

func packedQuatfArray(for accessor: GLTFAccessor) -> [simd_quatf]? {
    if accessor.componentType != .float || accessor.dimension != .vector4 {
        return nil
    }
    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }
    let vertexCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let elementStride = (bufferView.stride != 0) ? bufferView.stride : packedStride(for: accessor)
    let vectors = [simd_quatf](unsafeUninitializedCapacity: vertexCount) { buffer, initializedCount in
        bufferData.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
            for v in 0..<vertexCount {
                let elementPtr = basePtr.advanced(by: elementStride * v).bindMemory(to: Float.self, capacity: 4)
                buffer[v] = simd_quaternion(elementPtr[0], elementPtr[1], elementPtr[2], elementPtr[3])
            }
            initializedCount = vertexCount
        }
    }
    return vectors
}

func packedUInt32Array(for accessor: GLTFAccessor) -> [UInt32]? {
    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }

    let indexCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let indices = [UInt32](unsafeUninitializedCapacity: indexCount) { buffer, initializedCount in
        bufferData.withUnsafeBytes({ rawPtr in
            switch accessor.componentType {
            case .unsignedByte:
                guard let ubytePtr = rawPtr.baseAddress?.advanced(by: offset)
                    .bindMemory(to: UInt8.self, capacity: indexCount) else { initializedCount = 0; return }
                for i in 0..<indexCount {
                    buffer[i] = UInt32(ubytePtr[i])
                }
                initializedCount = indexCount
                break
            case .unsignedShort:
                guard let ushortPtr = rawPtr.baseAddress?.advanced(by: offset)
                    .bindMemory(to: UInt16.self, capacity: indexCount) else { initializedCount = 0; return }
                for i in 0..<indexCount {
                    buffer[i] = UInt32(ushortPtr[i])
                }
                initializedCount = indexCount
                break
            case .unsignedInt:
                guard let uintPtr = rawPtr.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
                memcpy(UnsafeMutableRawPointer(buffer.baseAddress!), uintPtr, MemoryLayout<UInt32>.stride * indexCount)
                initializedCount = indexCount
                break
            default:
                break
            }
        })
    }
    return indices
}

func convertMinMipFilters(from filter: GLTFMinMipFilter) -> (MTLSamplerMinMagFilter, MTLSamplerMipFilter) {
    switch filter {
    case .linear:
        return (.linear, .notMipmapped)
    case .nearest:
        return (.nearest, .notMipmapped)
    case .nearestNearest:
        return (.nearest, .nearest)
    case .linearNearest:
        return (.linear, .nearest)
    case .nearestLinear:
        return (.nearest, .linear)
    default:
        return (.linear, .linear)
    }
}

func convertMagFilter(from filter: GLTFMagFilter) -> MTLSamplerMinMagFilter {
    switch (filter) {
    case .nearest:
        return .nearest
    default:
        return .linear
    }
}

func convertAddressMode(from addressMode: GLTFAddressMode) -> MTLSamplerAddressMode {
    switch addressMode {
    case .repeat:
        return .repeat
    case .mirroredRepeat:
        return .mirrorRepeat
    default:
        return .clampToEdge
    }
}

extension MTLSamplerDescriptor {
    convenience init(from sampler: GLTFTextureSampler) {
        self.init()
        self.normalizedCoordinates = true
        let (minFilter, mipFilter) = convertMinMipFilters(from: sampler.minMipFilter)
        self.minFilter = minFilter
        self.mipFilter = mipFilter
        self.magFilter = convertMagFilter(from: sampler.magFilter)
        self.sAddressMode = convertAddressMode(from: sampler.wrapS)
        self.tAddressMode = convertAddressMode(from: sampler.wrapT)
    }
}

@available(macOS 12.0, iOS 15.0, *)
class GLTFRealityKitResourceContext {
    enum ColorMask : Int {
        case red
        case green
        case blue
        case all
    }

    private var cgImagesForImageIdentifiers = [UUID : CGImage]()
    private var textureResourcesForImageIdentifiers = [UUID : [(RealityKit.TextureResource, ColorMask)]]()

    var defaultMaterial: Material {
        return RealityKit.SimpleMaterial(color: .init(white: 0.5, alpha: 1.0), isMetallic: false)
    }

    func texture(for gltfTextureParams: GLTFTextureParams, channels: ColorMask,
                 semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = gltfTexture.source else { return nil }
        if let resource = textureResource(for:image, channels: channels, semantic: semantic) {
            let descriptor = MTLSamplerDescriptor(from: gltfTexture.sampler ?? GLTFTextureSampler())
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            return RealityKit.PhysicallyBasedMaterial.Texture(resource, sampler: sampler)
        }
        return nil
    }

    func textureResource(for gltfImage: GLTFImage, channels: ColorMask,
                         semantic: RealityKit.TextureResource.Semantic) -> RealityKit.TextureResource?
    {
        let existingResources = textureResourcesForImageIdentifiers[gltfImage.identifier]
        if let existingMatch = existingResources?.first(where: { $0.1 == channels })?.0 {
            return existingMatch
        }
        var cgImage = cgImagesForImageIdentifiers[gltfImage.identifier]
        if cgImage == nil {
            cgImage = gltfImage.newCGImage()?.takeRetainedValue()
            if cgImage != nil {
                #if os(visionOS)
                // Image decoding is not as robust on visionOS as on other platforms,
                // so we "pre-decode" here into a known-good image layout.
                cgImage = decodeCGImage(cgImage!)
                #endif
                cgImagesForImageIdentifiers[gltfImage.identifier] = cgImage
            }
        }
        guard let originalImage = cgImage else { return nil }

        guard let sourceImage = (channels == .all) ? originalImage :
                singleChannelImage(from: originalImage, channels: channels) else { return nil }

        let options = TextureResource.CreateOptions(semantic: semantic)
        guard let resource = try? TextureResource.generate(from: sourceImage, options: options) else { return nil }
        if textureResourcesForImageIdentifiers[gltfImage.identifier] != nil {
            textureResourcesForImageIdentifiers[gltfImage.identifier]!.append((resource, channels))
        } else {
            textureResourcesForImageIdentifiers[gltfImage.identifier] = [(resource, channels)]
        }

        return resource
    }

    func singleChannelImage(from cgImage: CGImage, channels: ColorMask) -> CGImage? {
        guard (cgImage.colorSpace?.model == .rgb) else {
            // Can't extract from a non-RGB[A] image with this method. Fall back to the input image hoping it's monochrome.
            return cgImage
        }
        guard let inputFormat = vImage_CGImageFormat(cgImage: cgImage) else { return nil }
        guard var inputBuffer = try? vImage_Buffer(cgImage: cgImage, format: inputFormat) else { return nil }
        var outputBuffer = vImage_Buffer()
        vImageBuffer_Init(&outputBuffer, inputBuffer.height, inputBuffer.width, inputFormat.bitsPerPixel, vImage_Flags())
        defer { outputBuffer.data.deallocate() }
        var channel = 0
        switch (channels) { case .red: channel = 0; case .green: channel = 1; case .blue: channel = 2; default: break }
        let outputColorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
        let outputFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8, colorSpace: outputColorSpace,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                                renderingIntent: .defaultIntent)!
        vImageExtractChannel_ARGB8888(&inputBuffer, &outputBuffer, channel, vImage_Flags())
        let outputImage = try? outputBuffer.createCGImage(format: outputFormat)
        return outputImage
    }

    func decodeCGImage(_ image: CGImage) -> CGImage? {
        let isSingleChannel = (image.colorSpace?.model == .monochrome)
        let wantsAlpha = ![CGImageAlphaInfo.none, CGImageAlphaInfo.noneSkipLast, CGImageAlphaInfo.noneSkipFirst].contains(image.alphaInfo)
        let bitsPerComponent = 8
        let width = image.width, height = image.height
        let bytesPerPixel = isSingleChannel ? 1 : 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpace(name: isSingleChannel ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB)!
        var bitmapInfo = CGBitmapInfo.byteOrderDefault.rawValue
        if (wantsAlpha) {
            if (image.alphaInfo == .alphaOnly) {
                bitmapInfo |= image.alphaInfo.rawValue
            } else {
                bitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue
            }
        } else {
            if (isSingleChannel) {
                bitmapInfo |= CGImageAlphaInfo.none.rawValue
            } else {
                bitmapInfo |= CGImageAlphaInfo.noneSkipLast.rawValue
            }
        }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), byTiling: false)
        let image = context.makeImage()
        return image
    }
}

@available(macOS 12.0, iOS 15.0, *)
public class GLTFRealityKitLoader {

#if os(macOS)
    let colorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
#endif

    public static func load(from url: URL) async throws -> RealityKit.Entity {
        let asset = try GLTFAsset(url: url)
        if let scene = asset.defaultScene {
            return DispatchQueue.main.asyncAndWait {
                return convert(scene: scene, asset: asset)
            }
        } else {
            throw NSError(domain: GLTFErrorDomain,
                          code: 1020,
                          userInfo: [ NSLocalizedDescriptionKey : "The glTF asset did not specify a default scene" ])
        }
    }

    public static func convert(scene: GLTFScene) -> RealityKit.Entity {
        let instance = GLTFRealityKitLoader()
        return instance.convert(scene: scene, asset: nil)
    }

    public static func convert(scene: GLTFScene, asset: GLTFAsset?) -> RealityKit.Entity {
        let instance = GLTFRealityKitLoader()
        return instance.convert(scene: scene, asset: asset)
    }

    func convert(scene: GLTFScene, asset: GLTFAsset? = nil) -> RealityKit.Entity {
        let context = GLTFRealityKitResourceContext()

        let rootEntity = Entity()

        do {
            let rootNodes = try scene.nodes.compactMap { try self.convert(node: $0, context: context) }

            for rootNode in rootNodes {
                rootEntity.addChild(rootNode)
            }
        } catch {
            fatalError("Error when converting scene: \(error)")
        }

        // TODO: Morph targets, skinned animation, etc.

        for animation in asset?.animations ?? [] {
            animation.store(in: rootEntity)
        }

        return rootEntity
    }

    func convert(node gltfNode: GLTFNode, context: GLTFRealityKitResourceContext) throws -> RealityKit.Entity {
        let nodeEntity = Entity()
        nodeEntity.name = gltfNode.name ?? "(unnamed node)"

        nodeEntity.transform = Transform(matrix: gltfNode.matrix) // TODO: Properly compose node's TRS properties

        if let gltfMesh = gltfNode.mesh,
           let meshComponent = try convert(mesh: gltfMesh, context: context) {
            nodeEntity.components.set(meshComponent)
        }

        #if !os(visionOS)
        if let gltfLight = gltfNode.light {
            switch gltfLight.type {
            case .directional:
                nodeEntity.components.set(convert(directionalLight: gltfLight))
            case .point:
                nodeEntity.components.set(convert(pointLight: gltfLight))
            case .spot:
                nodeEntity.components.set(convert(spotLight: gltfLight))
            default:
                break
            }
        }
        #endif

        if let gltfCamera = gltfNode.camera, let cameraComponent = convert(camera: gltfCamera) {
            nodeEntity.components.set(cameraComponent)
        }

        for childNode in gltfNode.childNodes {
            nodeEntity.addChild(try convert(node: childNode, context: context))
        }

        return nodeEntity
    }

    func convert(mesh gltfMesh: GLTFMesh, context: GLTFRealityKitResourceContext) throws -> RealityKit.ModelComponent? {
        var primitiveMaterialIndex: UInt32 = 0
        let meshDescriptorAndMaterials = try gltfMesh.primitives.compactMap { primitive -> (RealityKit.MeshDescriptor, RealityKit.Material)? in
            if var meshDescriptor = try self.convert(primitive: primitive, context:context) {
                let material = try self.convert(material: primitive.material, context: context)
                meshDescriptor.materials = .allFaces(primitiveMaterialIndex)
                primitiveMaterialIndex += 1
                return (meshDescriptor, material)
            }
            // If we fail to create a mesh descriptor for a primitive, omit it from the list.
            return nil
        }

        if meshDescriptorAndMaterials.count == 0 {
            // If we weren't able to successfully build any mesh descriptors for our primitives,
            // don't bother generating a mesh.
            return nil
        }

        let meshResource = try MeshResource.generate(from: meshDescriptorAndMaterials.map { $0.0 })

        let model = ModelComponent(mesh: meshResource, materials: meshDescriptorAndMaterials.map { $0.1 } )

        return model
    }

    func convert(primitive gltfPrimitive: GLTFPrimitive,
                 context: GLTFRealityKitResourceContext) throws -> RealityKit.MeshDescriptor?
    {
        if gltfPrimitive.primitiveType != .triangles {
            return nil
        }

        var meshDescriptor = MeshDescriptor(name: gltfPrimitive.name ?? "(unnamed prim)") // TODO: Unique names

        if let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
           let positionArray = packedFloat3Array(for: positionAttribute.accessor)
        {
            meshDescriptor.positions = MeshBuffers.Positions(positionArray)
        }

        if let normalAttribute = gltfPrimitive.attribute(forName: "NORMAL"),
           let normalArray = packedFloat3Array(for: normalAttribute.accessor)
        {
            meshDescriptor.normals = MeshBuffers.Normals(normalArray)
        }

        if let tangentAttribute = gltfPrimitive.attribute(forName: "TANGENT"),
           let tangentArray = packedFloat3Array(for: tangentAttribute.accessor)
        {
            meshDescriptor.tangents = MeshBuffers.Tangents(tangentArray)
        }

        if let texCoords0Attribute = gltfPrimitive.attribute(forName: "TEXCOORD_0"),
           let texCoordsArray = packedFloat2Array(for: texCoords0Attribute.accessor, flipVertically: true)
        {
            meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texCoordsArray)
        }

        // TODO: Support explicit bitangents and other user attributes?

        if let indexAccessor = gltfPrimitive.indices, let indices = packedUInt32Array(for: indexAccessor) {
            meshDescriptor.primitives = .triangles(indices)
        } else {
            let vertexCount = gltfPrimitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            let indices = [UInt32](UInt32(0)..<UInt32(vertexCount))
            meshDescriptor.primitives = .triangles(indices)
        }

        return meshDescriptor
    }

    func convert(material gltfMaterial: GLTFMaterial?,
                 context: GLTFRealityKitResourceContext) throws -> RealityKit.Material
    {
        guard let gltfMaterial = gltfMaterial else { return context.defaultMaterial }

        if gltfMaterial.isUnlit {
            var material = UnlitMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.color.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.color.texture = context.texture(for: baseColorTexture, channels: .all, semantic: .color)
                }
            }
            if gltfMaterial.alphaMode == .mask {
                material.opacityThreshold = gltfMaterial.alphaCutoff
            } else if gltfMaterial.alphaMode == .blend {
                // TODO: Convert base color alpha channel into opacity map?
                material.blending = .transparent(opacity: 1.0)
            }
            return material
        } else {
            var material = PhysicallyBasedMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.baseColor.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.baseColor.texture = context.texture(for: baseColorTexture,
                                                                 channels: .all,
                                                                 semantic: .color)
                }
                material.roughness.scale = metallicRoughness.roughnessFactor
                material.metallic.scale = metallicRoughness.metallicFactor
                if let metallicRoughnessTexture = metallicRoughness.metallicRoughnessTexture {
                    material.roughness.texture = context.texture(for: metallicRoughnessTexture,
                                                                 channels: .green,
                                                                 semantic: .scalar)
                    material.metallic.texture = context.texture(for: metallicRoughnessTexture,
                                                                channels: .blue,
                                                                semantic: .scalar)
                }
            }
            if let normal = gltfMaterial.normalTexture {
                material.normal.texture = context.texture(for: normal, channels: .all, semantic: .normal)
            }
            if let emissive = gltfMaterial.emissive {
                material.emissiveIntensity = emissive.emissiveStrength
                if let emissiveTexture = emissive.emissiveTexture {
                    material.emissiveColor.texture = context.texture(for: emissiveTexture,
                                                                     channels: .all,
                                                                     semantic: .color)
                }
            }
            if let occlusion = gltfMaterial.occlusionTexture {
                material.ambientOcclusion.texture = context.texture(for: occlusion, channels: .red, semantic: .scalar)
            }
            if let clearcoat = gltfMaterial.clearcoat {
                material.clearcoat.scale = clearcoat.clearcoatFactor
                if let clearcoatTexture = clearcoat.clearcoatTexture {
                    material.clearcoat.texture = context.texture(for: clearcoatTexture, channels: .red, semantic: .raw)
                }
                material.clearcoatRoughness.scale = clearcoat.clearcoatRoughnessFactor
                if let clearcoatRoughnessTexture = clearcoat.clearcoatRoughnessTexture {
                    material.clearcoatRoughness.texture = context.texture(for: clearcoatRoughnessTexture,
                                                                          channels: .green,
                                                                          semantic: .raw)
                }
            }
            if gltfMaterial.alphaMode == .mask {
                material.opacityThreshold = gltfMaterial.alphaCutoff
            } else if gltfMaterial.alphaMode == .blend {
                // TODO: Convert base color alpha channel into opacity map?
                material.blending = .transparent(opacity: 1.0)
            }
            material.faceCulling = gltfMaterial.isDoubleSided ? .none : .back

            // TODO: sheen
            return material
        }
    }

    #if !os(visionOS)

    func convert(spotLight gltfLight: GLTFLight) -> SpotLightComponent {
        let light = SpotLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                       intensity: gltfLight.intensity,
                                       innerAngleInDegrees: degreesFromRadians(gltfLight.innerConeAngle),
                                       outerAngleInDegrees: degreesFromRadians(gltfLight.outerConeAngle),
                                       attenuationRadius: gltfLight.range)
        return light
    }

    func convert(pointLight gltfLight: GLTFLight) -> PointLightComponent {
        let light = PointLightComponent(color:platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                        intensity: gltfLight.intensity,
                                        attenuationRadius:gltfLight.range)
        return light
    }

    func convert(directionalLight gltfLight: GLTFLight) -> DirectionalLightComponent {
        let light = DirectionalLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                              intensity: gltfLight.intensity,
                                              isRealWorldProxy: false)
        return light
    }

    #endif

    func convert(camera: GLTFCamera) -> PerspectiveCameraComponent? {
        if let perspectiveParams = camera.perspective {
            let camera = PerspectiveCameraComponent(near: camera.zNear,
                                                    far: camera.zFar,
                                                    fieldOfViewInDegrees: degreesFromRadians(perspectiveParams.yFOV))
            // TODO: Correctly handle infinite far clip distance (camera.zFar == 0)
            return camera
        }
        return nil
    }

    func platformColor(for vector: simd_float4) -> PlatformColor {
#if os(macOS)
        let components = [CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z), CGFloat(vector.w)]
        let color = NSColor(colorSpace: colorSpace, components: components, count: components.count)
        return color
#else
        let components = [CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z), CGFloat(vector.w)]
        // TODO: Use proper color space (linear sRGB)
        let color = UIColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
        return color
#endif
    }
}

public class GLTFAnimationPlaybackController {
    class BoundAnimation {
        let entity: Entity
        let path: GLTFAnimationPath
        let times: [Float]
        let beginTime: TimeInterval
        let endTime: TimeInterval

        init(entity: Entity, path: GLTFAnimationPath, times: [Float]) {
            self.entity = entity
            self.path = path
            self.times = times
            beginTime = TimeInterval(times.first ?? 0.0)
            endTime = TimeInterval(times.last ?? 0.0)
        }

        func apply(at time: TimeInterval) {
            preconditionFailure("Concrete subclasses of BoundAnimation should override apply(at:)")
        }
    }

    private class Float3Animation : BoundAnimation {
        let values: [simd_float3]

        init(entity: Entity, path: GLTFAnimationPath, times: [Float], values: [simd_float3]) {
            self.values = values
            super.init(entity: entity, path: path, times: times)
        }

        override func apply(at time: TimeInterval) {
            let parentTime = Float(time)
            if time < beginTime || time > endTime { return }
            guard let nextIndex = times.firstIndex(where: { $0 > parentTime }) else { return }
            let prevIndex = max(0, nextIndex - 1)
            let frameProgress = unlerp(times[prevIndex], times[nextIndex], parentTime)
            let lowerValue = values[prevIndex], upperValue = values[nextIndex]
            let currentValue = lerp(lowerValue, upperValue, frameProgress)
            if path == .translation {
                entity.transform.translation = currentValue
            } else if path == .scale {
                entity.transform.scale = currentValue
            }
        }
    }

    private class QuatfAnimation : BoundAnimation {
        let values: [simd_quatf]

        init(entity: Entity, path: GLTFAnimationPath, times: [Float], values: [simd_quatf]) {
            self.values = values
            super.init(entity: entity, path: path, times: times)
        }

        override func apply(at time: TimeInterval) {
            let parentTime = Float(time)
            if time < beginTime || time > endTime { return }
            guard let nextIndex = times.firstIndex(where: { $0 > parentTime }) else { return }
            let prevIndex = max(0, nextIndex - 1)
            let frameProgress = unlerp(times[prevIndex], times[nextIndex], parentTime)
            let lowerValue = values[prevIndex], upperValue = values[nextIndex]
            let currentValue = simd_slerp(lowerValue, upperValue, frameProgress)
            if path == .rotation {
                entity.transform.rotation = currentValue
            }
        }
    }

    var repeatDuration: TimeInterval = 0
    private var paused: Bool = false
    private var complete: Bool = false
    private var time: TimeInterval = 0
    private var animations = [BoundAnimation]()

    private var displayLink: CADisplayLink?

    init(animation: GLTFAnimation, rootEntity: RealityKit.Entity) {
        for channel in animation.channels {
            guard let targetName = channel.target.node?.name else { continue }
            var targetEntity: Entity?
            if rootEntity.name == targetName {
                targetEntity = rootEntity
            } else {
                targetEntity = rootEntity.findEntity(named: targetName)
            }
            guard let targetEntity else { continue }
            let path = GLTFAnimationPath(rawValue: channel.target.path)
            guard let keyTimes = packedFloatArray(for: channel.sampler.input) else { continue }
            if path == .translation {
                if let keyValues = packedFloat3Array(for: channel.sampler.output) {
                    animations.append(Float3Animation(entity: targetEntity, path: path, times: keyTimes, values: keyValues))
                }
            } else if path == .rotation {
                if let keyValues = packedQuatfArray(for: channel.sampler.output) {
                    animations.append(QuatfAnimation(entity: targetEntity, path: path, times: keyTimes, values: keyValues))
                }
            } else if path == .scale {
                if let keyValues = packedFloat3Array(for: channel.sampler.output) {
                    animations.append(Float3Animation(entity: targetEntity, path: path, times: keyTimes, values: keyValues))
                }
            }
        }

        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink?.add(to: RunLoop.main, forMode: .default)
    }

    public func pause() {
        paused = true
    }

    public func resume() {
        paused = false
    }

    public func stop() {
        paused = true
        complete = true
    }

    func update(timestep: TimeInterval) {
        if complete { return }
        if paused { return }

        time += timestep

        var anyActive = false
        for animation in animations {
            animation.apply(at: time)
            if animation.endTime > time {
                anyActive = true
            }
        }

        if !anyActive {
            complete = true
        }
    }

    @objc
    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        DispatchQueue.main.async {
            self.update(timestep: displayLink.duration)
        }
    }
}

class GLTFAnimationSystem : RealityKit.System {
    private static let query = EntityQuery(
        where: .has(GLTFAnimationController.self)
    )

    static var hasRegistered = false
    static func registerIfNeeded() {
        if !hasRegistered {
            Self.registerSystem()
            GLTFAnimationContainer.registerComponent()
            GLTFAnimationController.registerComponent()
            hasRegistered = true
        }
    }

    required init(scene: RealityKit.Scene) {}

    // TODO: update(context:) isn't called at a regular cadence when RealityKit doesn't think it needs to re-render.
    // We currently use one CADisplayLink per running animation to receive regular callbacks to drive animations.
    // It would be much more efficient to use a single CADisplayLink instead and drive all controllers with it.
    func update(context: SceneUpdateContext) {
//        let animationEntities = context.scene.performQuery(Self.query)
//
//        for entity in animationEntities {
//            guard let controller = entity.components[GLTFAnimationController.self] else { continue }
//            controller.update(timestep: context.deltaTime)
//        }
    }
}

public struct GLTFAnimationContainer : Component {
    public private(set) var availableAnimations: [GLTFAnimation] = []

    mutating func store(_ animation: GLTFAnimation) {
        availableAnimations.append(animation)
    }
}

public struct GLTFAnimationController : Component {
    private var activeControllers = [GLTFAnimationPlaybackController]()

    mutating func playAnimation(_ animation: GLTFAnimation, repeatDuration: TimeInterval, on entity: Entity) -> GLTFAnimationPlaybackController {
        let playbackController = GLTFAnimationPlaybackController(animation: animation, rootEntity: entity)
        playbackController.repeatDuration = repeatDuration
        activeControllers.append(playbackController)
        return playbackController
    }

    func update(timestep: TimeInterval) {
        for animationController in activeControllers {
            animationController.update(timestep: timestep)
        }
    }
}

public protocol CanPlayGLTFAnimations {
    func playAnimation(_ animation: GLTFAnimation, repeatDuration: TimeInterval) -> GLTFAnimationPlaybackController
}

extension RealityKit.Entity : CanPlayGLTFAnimations {
    public func playAnimation(_ animation: GLTFAnimation, repeatDuration: TimeInterval) -> GLTFAnimationPlaybackController {
        if (!components.has(GLTFAnimationController.self)) {
            components.set(GLTFAnimationController())
        }
        return components[GLTFAnimationController.self]!.playAnimation(animation, repeatDuration: repeatDuration, on: self)
    }
}

public protocol ContainsGLTFAnimations {
    var availableGLTFAnimations: [GLTFAnimation] { get }
}

extension RealityKit.Entity : ContainsGLTFAnimations {
    public var availableGLTFAnimations: [GLTFAnimation] {
        if (!components.has(GLTFAnimationContainer.self)) {
            components.set(GLTFAnimationContainer())
        }
        return components[GLTFAnimationContainer.self]!.availableAnimations
    }
}

extension GLTFAnimation {
    func store(in entity: Entity) {
        GLTFAnimationSystem.registerIfNeeded()

        if (!entity.components.has(GLTFAnimationContainer.self)) {
            entity.components.set(GLTFAnimationContainer())
        }
        entity.components[GLTFAnimationContainer.self]?.store(self)
    }
}

#endif // swift >=5.5

#endif // !tvOS
