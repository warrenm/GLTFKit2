
import RealityKit

#if os(macOS)
typealias PlatformColor = NSColor
#elseif os(iOS) || os(tvOS)
typealias PlatformColor = UIColor
#endif

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
    private var textureResourcesForImageIdentifiers = [UUID : RealityKit.TextureResource]()

    var defaultMaterial: Material {
        return RealityKit.SimpleMaterial(color: .init(white: 0.5, alpha: 1.0), isMetallic: false)
    }

    func texture(for gltfTextureParams: GLTFTextureParams,
                 semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = gltfTexture.source else { return nil }
        let imageID = image.identifier
        var resource = textureResourcesForImageIdentifiers[imageID]
        if resource == nil {
            resource = loadTextureResource(for:image, semantic: semantic)
        }
        if let resource = resource {
            let descriptor = MTLSamplerDescriptor(from: gltfTexture.sampler ?? GLTFTextureSampler())
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            return RealityKit.PhysicallyBasedMaterial.Texture(resource, sampler: sampler)
        }
        return nil
    }

    func loadTextureResource(for gltfImage: GLTFImage,
                             semantic: RealityKit.TextureResource.Semantic) -> RealityKit.TextureResource?
    {
        guard let cgImage = gltfImage.newCGImage() else { return nil }
        let options = TextureResource.CreateOptions(semantic: semantic)
        guard let resource = try? TextureResource.generate(from: cgImage.takeUnretainedValue(),
                                                           options: options) else { return nil }
        textureResourcesForImageIdentifiers[gltfImage.identifier] = resource
        return resource
    }
}

@available(macOS 12.0, iOS 15.0, *)
public class GLTFRealityKitLoader {

#if os(macOS)
    let colorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
#endif

    public static func convert(scene: GLTFScene) -> RealityKit.Entity {
        let instance = GLTFRealityKitLoader()
        return instance.convert(scene: scene)
    }

    func convert(scene: GLTFScene) -> RealityKit.Entity {
        let context = GLTFRealityKitResourceContext()

        let rootEntity = Entity()

        do {
            let rootNodes = try scene.nodes.map { try self.convert(node: $0, context: context) }

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

        if let gltfMesh = gltfNode.mesh {
            let meshComponent = try convert(mesh: gltfMesh, context: context)
            nodeEntity.components.set(meshComponent)
        }

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

        if let gltfCamera = gltfNode.camera, let cameraComponent = convert(camera: gltfCamera) {
            nodeEntity.components.set(cameraComponent)
        }

        for childNode in gltfNode.childNodes {
            nodeEntity.addChild(try convert(node: childNode, context: context))
        }

        return nodeEntity
    }

    func convert(mesh gltfMesh: GLTFMesh, context: GLTFRealityKitResourceContext) throws -> RealityKit.ModelComponent {
        let meshDescriptors = try gltfMesh.primitives.map { try self.convert(primitive: $0, context:context) }
            .filter({$0 != nil})
            .map({$0!})

        let meshResource = try MeshResource.generate(from: meshDescriptors)

        let gltfMaterials = gltfMesh.primitives.map { $0.material }
        let materials = try gltfMaterials.map { return try self.convert(material: $0, context: context) }

        let model = ModelComponent(mesh: meshResource, materials: materials)

        return model
    }

    func convert(primitive gltfPrimitive: GLTFPrimitive,
                 context: GLTFRealityKitResourceContext) throws -> RealityKit.MeshDescriptor?
    {
        if gltfPrimitive.primitiveType != .triangles {
            return nil
        }

        var meshDescriptor = MeshDescriptor(name: gltfPrimitive.name ?? "(unnamed prim)") // TODO: Unique names

        if let positionAccessor = gltfPrimitive.attributes["POSITION"],
            let positionArray = packedFloat3Array(for: positionAccessor)
        {
            meshDescriptor.positions = MeshBuffers.Positions(positionArray)
        }

        if let normalAccessor = gltfPrimitive.attributes["NORMAL"],
            let normalArray = packedFloat3Array(for: normalAccessor)
        {
            meshDescriptor.normals = MeshBuffers.Normals(normalArray)
        }

        if let tangentAccessor = gltfPrimitive.attributes["TANGENT"],
            let tangentArray = packedFloat3Array(for: tangentAccessor)
        {
            meshDescriptor.tangents = MeshBuffers.Tangents(tangentArray)
        }

        if let texCoords0Accessor = gltfPrimitive.attributes["TEXCOORD_0"],
            let texCoordsArray = packedFloat2Array(for: texCoords0Accessor, flipVertically: true)
        {
            meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texCoordsArray)
        }

        // TODO: Support explicit bitangents and other user attributes?

        if let indexAccessor = gltfPrimitive.indices, let indices = packedUInt32Array(for: indexAccessor) {
            meshDescriptor.primitives = .triangles(indices)
        } else {
            let vertexCount = gltfPrimitive.attributes["POSITION"]?.count ?? 0
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
                    material.color.texture = context.texture(for: baseColorTexture, semantic: .color)
                }
            }
            material.opacityThreshold = gltfMaterial.alphaCutoff
            if (gltfMaterial.alphaMode == .blend) {
                // TODO: Convert base color alpha channel into opacity map?
                material.blending = .transparent(opacity: 1.0)
            }

            return material
        } else {
            var material = PhysicallyBasedMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.baseColor.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.baseColor.texture = context.texture(for: baseColorTexture, semantic: .color)
                }
                if let metallicRoughnessTexture = metallicRoughness.metallicRoughnessTexture {
                    material.metallic.texture = context.texture(for: metallicRoughnessTexture, semantic: .raw)
                    material.roughness.texture = context.texture(for: metallicRoughnessTexture, semantic: .raw)
                }
            }
            if let normal = gltfMaterial.normalTexture {
                material.normal.texture = context.texture(for: normal, semantic: .normal)
            }
            if let emissive = gltfMaterial.emissive {
                material.emissiveIntensity = emissive.emissiveStrength
                if let emissiveTexture = emissive.emissiveTexture {
                    material.emissiveColor.texture = context.texture(for: emissiveTexture, semantic: .color)
                }
            }
            if let occlusion = gltfMaterial.occlusionTexture {
                material.ambientOcclusion.texture = context.texture(for: occlusion, semantic: .raw)
            }
            if let clearcoat = gltfMaterial.clearcoat {
                material.clearcoat.scale = clearcoat.clearcoatFactor
                if let clearcoatTexture = clearcoat.clearcoatTexture {
                    material.clearcoat.texture = context.texture(for: clearcoatTexture, semantic: .raw)
                }
                material.clearcoatRoughness.scale = clearcoat.clearcoatRoughnessFactor
                if let clearcoatRoughnessTexture = clearcoat.clearcoatRoughnessTexture {
                    material.clearcoatRoughness.texture = context.texture(for: clearcoatRoughnessTexture,
                                                                          semantic: .raw)
                }
            }
            material.opacityThreshold = gltfMaterial.alphaCutoff
            if (gltfMaterial.alphaMode == .blend) {
                // TODO: Convert base color alpha channel into opacity map?
                material.blending = .transparent(opacity: 1.0)
            }
            material.faceCulling = gltfMaterial.isDoubleSided ? .none : .back

            // TODO: sheen
            return material
        }
    }

    func convert(spotLight gltfLight: GLTFLight) -> SpotLightComponent {
        let light = SpotLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                       intensity: gltfLight.intensity,
                                       innerAngleInDegrees: gltfLight.innerConeAngle,
                                       outerAngleInDegrees: gltfLight.outerConeAngle,
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

    func convert(camera: GLTFCamera) -> PerspectiveCameraComponent? {
        if let perspectiveParams = camera.perspective {
            let camera = PerspectiveCameraComponent(near: camera.zNear,
                                                    far: camera.zFar,
                                                    fieldOfViewInDegrees: perspectiveParams.yFOV)
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
