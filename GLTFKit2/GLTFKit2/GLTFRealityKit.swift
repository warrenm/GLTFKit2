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

func packedFloat4Array(for accessor: GLTFAccessor) -> [SIMD4<Float>]? {
    if accessor.componentType != .float || (accessor.dimension != .vector4) {
        return nil
    }

    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }

    let vertexCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let elementStride = (bufferView.stride != 0) ? bufferView.stride : packedStride(for: accessor)
    let vectors = [SIMD4<Float>](unsafeUninitializedCapacity: vertexCount) { buffer, initializedCount in
        bufferData.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
            for v in 0..<vertexCount {
                let elementPtr = basePtr.advanced(by: elementStride * v).bindMemory(to: Float.self, capacity: 4)
                buffer[v] = SIMD4(elementPtr[0], elementPtr[1], elementPtr[2], elementPtr[3])
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

func packedUShort4Array(for accessor: GLTFAccessor) -> [SIMD4<UInt16>]? {
    if (accessor.componentType != .unsignedByte && accessor.componentType != .unsignedShort) || (accessor.dimension != .vector4) {
        return nil
    }
    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }

    let vectorCount = accessor.count
    let offset = bufferView.offset + accessor.offset
    let vectors = [SIMD4<UInt16>](unsafeUninitializedCapacity: vectorCount) { destPtr, initializedCount in
        bufferData.withUnsafeBytes({ sourcePtr in
            initializedCount = 0
            guard let accessorBase = sourcePtr.baseAddress?.advanced(by: offset) else { return }
            switch accessor.componentType {
            case .unsignedByte:
                let sourceStride = (bufferView.stride == 0) ? MemoryLayout<SIMD4<UInt8>>.stride : bufferView.stride
                for i in 0..<vectorCount {
                    let components = accessorBase.advanced(by: sourceStride * i).bindMemory(to: UInt8.self, capacity: 4)
                    destPtr[i] = SIMD4<UInt16>(UInt16(components[0]), UInt16(components[1]), UInt16(components[2]), UInt16(components[3]))
                }
                initializedCount = vectorCount
            case .unsignedShort:
                let sourceStride = (bufferView.stride == 0) ? MemoryLayout<SIMD4<UInt16>>.stride : bufferView.stride
                if sourceStride == MemoryLayout<SIMD4<UInt16>>.stride {
                    // Source buffer view is packed; copy everything in one shot
                    memcpy(UnsafeMutableRawPointer(destPtr.baseAddress!), accessorBase, sourceStride * vectorCount)
                    initializedCount = vectorCount
                } else {
                    // We're not packed, so copy each vector individually
                    for i in 0..<vectorCount {
                        let components = accessorBase.advanced(by: sourceStride * i).bindMemory(to: UInt16.self, capacity: 4)
                        destPtr[i] = SIMD4<UInt16>(components[0], components[1], components[2], components[3])
                    }
                    initializedCount = vectorCount
                }
            default:
                break
            }
        })
    }
    return vectors
}

func packedFloat4x4(for accessor: GLTFAccessor) -> [simd_float4x4]? {
    if (accessor.componentType != .float) || (accessor.dimension != .matrix4) {
        return nil
    }
    guard let bufferView = accessor.bufferView else { return nil }
    guard let bufferData = bufferView.buffer.data else { return nil }

    let sourceStride = bufferView.stride == 0 ? MemoryLayout<simd_float4x4>.stride : bufferView.stride
    let offset = bufferView.offset + accessor.offset
    let matrices = [simd_float4x4].init(unsafeUninitializedCapacity: accessor.count) { destPtr, initializedCount in
        bufferData.withUnsafeBytes { sourceBase in
            guard let accessorBase = sourceBase.baseAddress?.advanced(by: offset) else { initializedCount = 0; return }
            if sourceStride == MemoryLayout<simd_float4x4>.stride {
                memcpy(&destPtr[0], accessorBase, sourceStride * accessor.count)
            } else {
                for i in 0..<accessor.count {
                    let srcMatrix = accessorBase.advanced(by: sourceStride * i)
                    memcpy(&destPtr[i], srcMatrix, MemoryLayout<simd_float4x4>.size)
                }
            }
            initializedCount = accessor.count;
        }
    }
    return matrices
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

fileprivate class UniqueNameGenerator {
    private var countsForPrefixes = [String : Int]()

    func nextUniqueName(prefix: String) -> String {
        if let existingCount = countsForPrefixes[prefix] {
            countsForPrefixes[prefix] = existingCount + 1
            return "\(prefix)\(existingCount)"
        } else {
            countsForPrefixes[prefix] = 1
            return "\(prefix)1"
        }
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

    var defaultMaterial: any Material {
        return RealityKit.SimpleMaterial(color: .init(white: 0.5, alpha: 1.0), isMetallic: false)
    }

    @MainActor func texture(for gltfTextureParams: GLTFTextureParams, channels: ColorMask,
                            semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.webpSource ?? gltfTexture.source) else { return nil }
        if let resource = textureResource(for:image, channels: channels, semantic: semantic) {
            let descriptor = MTLSamplerDescriptor(from: gltfTexture.sampler ?? GLTFTextureSampler())
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            return RealityKit.PhysicallyBasedMaterial.Texture(resource, sampler: sampler)
        }
        return nil
    }

    @MainActor func textureResource(for gltfImage: GLTFImage, channels: ColorMask,
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
        var bitmapInfo: UInt32 = 0
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

#if os(visionOS)
typealias GLTFRKSkeleton = RealityKit.MeshResource.Skeleton
#else
struct GLTFRKSkeleton : Identifiable {
    var id: String
}
#endif

@available(macOS 12.0, iOS 15.0, *)
public class GLTFRealityKitLoader {

#if os(macOS)
    let colorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
#endif
    private let nameGenerator = UniqueNameGenerator()

    public static func load(from url: URL) async throws -> RealityKit.Entity {
        let asset = try GLTFAsset(url: url)
        if let scene = asset.defaultScene {
            return await MainActor.run {
                return convert(scene: scene)
            }
        } else {
            throw NSError(domain: GLTFErrorDomain,
                          code: 1020,
                          userInfo: [ NSLocalizedDescriptionKey : "The glTF asset did not specify a default scene" ])
        }
    }

    @MainActor public static func convert(scene: GLTFScene) -> RealityKit.Entity {
        let instance = GLTFRealityKitLoader()
        return instance.convert(scene: scene)
    }

    @MainActor func convert(scene: GLTFScene) -> RealityKit.Entity {
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

    @MainActor func convert(node gltfNode: GLTFNode, context: GLTFRealityKitResourceContext) throws -> RealityKit.Entity {
        let nodeEntity = ModelEntity()

        // TODO: This only ensures uniqueness for unnamed nodes; the asset could still contain duplicate names.
        nodeEntity.name = gltfNode.name ?? nameGenerator.nextUniqueName(prefix: "Node")

        nodeEntity.transform = Transform(matrix: gltfNode.matrix) // TODO: Properly compose node's TRS properties

        var skeleton: GLTFRKSkeleton?
        #if os(visionOS)
        if let skin = gltfNode.skin {
            skeleton = convert(skin: skin, context: context)
        }
        #endif

        if let gltfMesh = gltfNode.mesh,
           let meshComponent = try convert(mesh: gltfMesh, skeleton: skeleton, context: context) {
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

    #if os(visionOS)
    func convert(skin gltfSkin: GLTFSkin, context: GLTFRealityKitResourceContext) -> MeshResource.Skeleton? {
        let skeletonName = gltfSkin.name ?? nameGenerator.nextUniqueName(prefix: "Skin")
        let jointNames = gltfSkin.joints.compactMap { return $0.name }

        let jointParents = gltfSkin.joints.map { skeletonNode in
            if let parent = skeletonNode.parent {
                return gltfSkin.joints.firstIndex(of: parent)
            } else {
                return nil
            }
        }

        let ibmMatrices = {
            if let ibmAccessor = gltfSkin.inverseBindMatrices, let matrices = packedFloat4x4(for: ibmAccessor) {
                return matrices
            } else {
                return [simd_float4x4](repeating: matrix_identity_float4x4, count: jointNames.count)
            }
        }()

        return MeshResource.Skeleton(id: skeletonName, jointNames: jointNames,
                                     inverseBindPoseMatrices: ibmMatrices, parentIndices: jointParents)
    }
    #endif

    @MainActor func convert(mesh gltfMesh: GLTFMesh, skeleton: GLTFRKSkeleton? = nil,
                            context: GLTFRealityKitResourceContext) throws -> RealityKit.ModelComponent?
    {
        var primitiveMaterialIndex: Int = 0
        let partsAndMaterials = try gltfMesh.primitives.compactMap { primitive -> (MeshResource.Part, any RealityKit.Material)? in
            if let part = self.convert(primitive: primitive, materialIndex: primitiveMaterialIndex, 
                                       skeletonID: skeleton?.id, context:context)
            {
                let material = try self.convert(material: primitive.material, context: context)
                primitiveMaterialIndex += 1
                return (part, material)
            }
            // If we fail to create a part from a primitive, omit it from the list.
            return nil
        }

        if partsAndMaterials.count == 0 {
            // If we weren't able to successfully build any parts for our primitives, don't bother generating a mesh.
            return nil
        }

        let parts = partsAndMaterials.map { $0.0 }
        let materials = partsAndMaterials.map { $0.1 }
        
        // TODO: This only ensures uniqueness for unnamed meshes; the asset could still contain duplicate names.
        let modelName = gltfMesh.name ?? nameGenerator.nextUniqueName(prefix: "Mesh")
        let model = MeshResource.Model(id: modelName, parts: parts)

        var meshContents = MeshResource.Contents()
        meshContents.models = MeshModelCollection([model])
        #if os(visionOS)
        if let skeleton = skeleton {
            meshContents.skeletons = MeshSkeletonCollection([skeleton])
        }
        #endif

        let meshResource = try MeshResource.generate(from: meshContents)
        let modelComponent = ModelComponent(mesh: meshResource, materials: materials)

        return modelComponent
    }

    func convert(primitive gltfPrimitive: GLTFPrimitive, materialIndex: Int = 0, skeletonID: String? = nil,
                 context: GLTFRealityKitResourceContext) -> RealityKit.MeshResource.Part?
    {
        if gltfPrimitive.primitiveType != .triangles {
            return nil
        }

        let partName = nameGenerator.nextUniqueName(prefix: "Primitive")
        var part = MeshResource.Part(id: partName, materialIndex: materialIndex)

        if let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
           let positionArray = packedFloat3Array(for: positionAttribute.accessor)
        {
            part[MeshBuffers.positions] = MeshBuffers.Positions(positionArray)
        }

        if let normalAttribute = gltfPrimitive.attribute(forName: "NORMAL"),
           let normalArray = packedFloat3Array(for: normalAttribute.accessor)
        {
            part[MeshBuffers.normals] = MeshBuffers.Normals(normalArray)
        }

        if let tangentAttribute = gltfPrimitive.attribute(forName: "TANGENT"),
           let tangentArray = packedFloat3Array(for: tangentAttribute.accessor)
        {
            part[MeshBuffers.tangents] = MeshBuffers.Tangents(tangentArray)
        }

        if let texCoords0Attribute = gltfPrimitive.attribute(forName: "TEXCOORD_0"),
           let texCoordsArray = packedFloat2Array(for: texCoords0Attribute.accessor, flipVertically: true)
        {
            part[MeshBuffers.textureCoordinates] = MeshBuffers.TextureCoordinates(texCoordsArray)
        }

        #if os(visionOS)
        if let joints0Attribute = gltfPrimitive.attribute(forName: "JOINTS_0"),
           let weights0Attribute = gltfPrimitive.attribute(forName: "WEIGHTS_0"),
           let jointsArray = packedUShort4Array(for: joints0Attribute.accessor),
           let weightsArray = packedFloat4Array(for: weights0Attribute.accessor)
        {
            let weightsPerVertex = 4
            func jointInfluences(forJoints joints: [SIMD4<UInt16>], weights: [SIMD4<Float>]) -> [MeshJointInfluence] {
                return zip(joints, weights).reduce(into: [MeshJointInfluence]()) { partialResult, jointsAndWeights in
                    let joints = jointsAndWeights.0; let weights = jointsAndWeights.1
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[0]), weight: weights[0]))
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[1]), weight: weights[1]))
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[2]), weight: weights[2]))
                    partialResult.append(MeshJointInfluence(jointIndex: Int(joints[3]), weight: weights[3]))
                }
            }

            let influences = jointInfluences(forJoints: jointsArray, weights: weightsArray)
            part.jointInfluences = MeshResource.JointInfluences(influences: MeshBuffers.JointInfluences(influences),
                                                                influencesPerVertex: weightsPerVertex)
            part.skeletonID = skeletonID
        }
        #endif

        // TODO: Support explicit bitangents and other user attributes?

        if let indexAccessor = gltfPrimitive.indices, let indices = packedUInt32Array(for: indexAccessor) {
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        } else {
            let vertexCount = gltfPrimitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            let indices = [UInt32](UInt32(0)..<UInt32(vertexCount))
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        }

        return part
    }

    @MainActor func convert(material gltfMaterial: GLTFMaterial?,
                            context: GLTFRealityKitResourceContext) throws -> any RealityKit.Material
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
                                                    far: (camera.zFar > 0.0) ? camera.zFar : .infinity,
                                                    fieldOfViewInDegrees: degreesFromRadians(perspectiveParams.yFOV))
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
