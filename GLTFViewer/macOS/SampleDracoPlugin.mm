
#import "SampleDracoPlugin.h"

#if __has_include("draco/compression/decode.h")

#include "draco/compression/decode.h"

static GLTFComponentType GLTFComponentTypeForDracoDataType(draco::DataType type) {
    switch (type) {
        case draco::DT_INT8:
            return GLTFComponentTypeByte;
        case draco::DT_UINT8:
            return GLTFComponentTypeUnsignedByte;
        case draco::DT_INT16:
            return GLTFComponentTypeShort;
        case draco::DT_UINT16:
            return GLTFComponentTypeUnsignedShort;
        case draco::DT_UINT32:
            return GLTFComponentTypeUnsignedInt;
        case draco::DT_FLOAT32:
            return GLTFComponentTypeFloat;
        default:
            return GLTFComponentTypeInvalid;
    }
}

static void *GLTFCopyPointAttributeData(const draco::PointCloud &pc, const draco::PointAttribute &pa, int &outSize) {
    int pointCount = pc.num_points();
    draco::DataType type = pa.data_type();
    int componentCount = pa.num_components();
    int componentSize = draco::DataTypeLength(type);
    int elementSize = componentCount * componentSize;
    int dataSize = pointCount * elementSize;
    void *data = malloc(dataSize);
    if (pa.is_mapping_identity()) {
        auto attrPtr = pa.GetAddress(draco::AttributeValueIndex(0));
        ::memcpy(data, attrPtr, dataSize);
    } else {
        for (draco::PointIndex i(0); i < pointCount; ++i) {
            const draco::AttributeValueIndex valueIndex = pa.mapped_index(i);
            void *elementPtr = (char *)data + i.value() * elementSize;
            pa.GetValue(valueIndex, elementPtr);
        }
    }
    outSize = dataSize;
    return data;
}

static uint32_t *GLTFCopyUInt32IndexDataForMesh(draco::Mesh *mesh, size_t &outIndexCount, size_t &outIndexBufferSize) {
    size_t indexCount = mesh->num_faces() * 3;
    size_t indexBufferSize = indexCount * sizeof(uint32_t);
    uint32_t *indices = (uint32_t *)calloc(indexCount, sizeof(uint32_t));
    for (int f = 0; f < mesh->num_faces(); ++f) {
        auto const &face = mesh->face(draco::FaceIndex(f));
        indices[f * 3 + 0] = face[0].value();
        indices[f * 3 + 1] = face[1].value();
        indices[f * 3 + 2] = face[2].value();
    }
    outIndexCount = indexCount;
    outIndexBufferSize = indexBufferSize;
    return indices;
}

@implementation DracoDecompressor

+ (GLTFPrimitive *)newPrimitiveForCompressedBufferView:(GLTFBufferView *)bufferView
                                          attributeMap:(NSDictionary<NSString *, NSNumber *> *)attributeMap;
{
    // TODO: Verify null safety here; is it possible we don't have a backing buffer?
    const char *data = (const char *)bufferView.buffer.data.bytes + bufferView.offset;
    draco::DecoderBuffer buffer;
    buffer.Init(data, bufferView.length);
    draco::Decoder decoder;
    std::unique_ptr<draco::Mesh> mesh;
    auto typeOrStatus = draco::Decoder::GetEncodedGeometryType(&buffer);
    if (!typeOrStatus.ok()) {
        return nil;
    }
    GLTFAccessor *indexAccessor = nil;
    __block NSMutableArray<GLTFAttribute *> *attributes = [NSMutableArray array];
    draco::EncodedGeometryType geometryType = typeOrStatus.value();
    if (geometryType == draco::TRIANGULAR_MESH) {
        auto meshOrStatus = decoder.DecodeMeshFromBuffer(&buffer);
        if (meshOrStatus.ok()) {
            mesh = std::move(meshOrStatus).value();
            draco::Mesh *meshPtr = mesh.get();
            [attributeMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *index, BOOL *stop) {
                uint32_t attrId = index.unsignedIntValue;
                const draco::PointAttribute *dracoAttribute = meshPtr->GetAttributeByUniqueId(attrId);
                int attributeBufferLength;
                void *attributePtr = GLTFCopyPointAttributeData(*meshPtr, *dracoAttribute, attributeBufferLength);
                NSData *attributeData = [NSData dataWithBytesNoCopy:attributePtr
                                                             length:attributeBufferLength
                                                       freeWhenDone:YES];
                GLTFBuffer *attributeBuffer = [[GLTFBuffer alloc] initWithData:attributeData];
                GLTFBufferView *attributeBufferView = [[GLTFBufferView alloc] initWithBuffer:attributeBuffer
                                                                                      length:attributeBufferLength
                                                                                      offset:0
                                                                                      stride:0];
                GLTFComponentType componentType = GLTFComponentTypeForDracoDataType(dracoAttribute->data_type());
                GLTFValueDimension dimension = static_cast<GLTFValueDimension>(dracoAttribute->num_components());
                BOOL normalized = dracoAttribute->normalized();
                GLTFAccessor *attributeAccessor = [[GLTFAccessor alloc] initWithBufferView:attributeBufferView
                                                                                    offset:0
                                                                             componentType:componentType
                                                                                 dimension:dimension
                                                                                     count:meshPtr->num_points()
                                                                                normalized:normalized];
                GLTFAttribute *attribute = [[GLTFAttribute alloc] initWithName:key accessor:attributeAccessor];
                [attributes addObject:attribute];
            }];
            size_t indexCount, indexBufferSize;
            uint32_t *indices = GLTFCopyUInt32IndexDataForMesh(meshPtr, indexCount, indexBufferSize);
            NSData *indexData = [NSData dataWithBytesNoCopy:indices length:indexBufferSize freeWhenDone:YES];
            GLTFBuffer *indexBuffer = [[GLTFBuffer alloc] initWithData:indexData];
            GLTFBufferView *indexBufferView = [[GLTFBufferView alloc] initWithBuffer:indexBuffer
                                                                              length:indexBufferSize
                                                                              offset:0
                                                                              stride:0];
            indexAccessor = [[GLTFAccessor alloc] initWithBufferView:indexBufferView
                                                              offset:0
                                                       componentType:GLTFComponentTypeUnsignedInt
                                                           dimension:GLTFValueDimensionScalar
                                                               count:indexCount
                                                          normalized:NO];
        }
    }
    return [[GLTFPrimitive alloc] initWithPrimitiveType:GLTFPrimitiveTypeTriangles
                                             attributes:attributes
                                                indices:indexAccessor];
}

@end

#endif
