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
    enum ColorMask {
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
            cgImage = gltfImage.newCGImage()?.takeRetainedValue() // TODO: Leak?
            if cgImage != nil {
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
        guard let inputFormat = vImage_CGImageFormat(cgImage: cgImage) else { return nil }
        guard var inputBuffer = try? vImage_Buffer(cgImage: cgImage, format: inputFormat) else { return nil }
        var outputBuffer = vImage_Buffer()
        vImageBuffer_Init(&outputBuffer, inputBuffer.height, inputBuffer.width, inputFormat.bitsPerPixel, vImage_Flags())
        defer { outputBuffer.data.deallocate() }
        let red: Float = (channels == .red) ? 1.0 : 0.0
        let green: Float = (channels == .green) ? 1.0 : 0.0
        let blue: Float = (channels == .blue) ? 1.0 : 0.0
        let divisor: Int32 = 0x1000
        let fDivisor = Float(divisor)
        let coefficientMatrix = [ Int16(red * fDivisor), Int16(green * fDivisor), Int16(blue * fDivisor) ]
        let preBias: [Int16] = [ 0, 0, 0, 0 ]
        let postBias: Int32 = 0
        vImageMatrixMultiply_ARGB8888ToPlanar8(&inputBuffer, &outputBuffer, coefficientMatrix, divisor,
                                               preBias, postBias, vImage_Flags())
        let outputColorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
        let outputFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8, colorSpace: outputColorSpace,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                                renderingIntent: .defaultIntent)!
        let outputImage = try? outputBuffer.createCGImage(format: outputFormat)
        return outputImage
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
                return convert(scene: scene)
            }
        } else {
            throw NSError(domain: GLTFErrorDomain,
                          code: 1020,
                          userInfo: [ NSLocalizedDescriptionKey : "The glTF asset did not specify a default scene" ])
        }
    }

    public static func convert(scene: GLTFScene) -> RealityKit.Entity {
        let instance = GLTFRealityKitLoader()
        return instance.convert(scene: scene)
    }

    func convert(scene: GLTFScene) -> RealityKit.Entity {
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
        let meshDescriptorAndMaterials = try gltfMesh.primitives.compactMap { primitive -> (RealityKit.MeshDescriptor, RealityKit.Material)? in
            if let meshDescriptor = try self.convert(primitive: primitive, context:context) {
                let material = try self.convert(material: primitive.material, context: context)
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

        let model = ModelComponent(mesh: meshResource, materials: meshDescriptorAndMaterials.map { $0.1} )

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

#endif // swift >=5.5

#endif // !tvOS
