
#import "GLTFMeshoptSupport.h"
#import <GLTFKit2/GLTFAsset.h>

#include <algorithm>
#include <queue>

static inline double hypot3(double x, double y, double z) {
    return sqrt((x * x) + (y * y) + (z * z));
}

template <typename Int_t>
Int_t consumeLEB128(const uint8_t *source, size_t &inOutOffset) {
    Int_t n = 0;
    for (int i = 0; ; i += 7) {
        const uint8_t b = source[inOutOffset++];
        n |= (b & 0x7F) << i;

        if (b < 0x80) {
            return n;
        }
    }
}

template <typename UInt_t>
typename std::make_unsigned<UInt_t>::type dezig(UInt_t v) {
    return ((v & 1) != 0) ? ~(v >> 1) : v >> 1;
}

template <typename Int_t>
uint32_t decodeIndex(Int_t v, uint32_t &inOutLast) {
    return (inOutLast += dezig(v));
}

static BOOL GLTFMeshoptDecodeVertexBuffer(const uint8_t *source, size_t sourceLength,
                                          size_t elementCount, size_t byteStride,
                                          uint8_t *destination)
{
    assert(source[0] == 0xA0);

    std::array<uint8_t, 256> tempData;
    const ssize_t tailDataOffset = sourceLength - byteStride;
    memcpy(tempData.data(), source + tailDataOffset, byteStride);

    const size_t maxBlockElements = std::min((0x2000 / byteStride) & ~0x000F, 0x100ul);
    std::array<uint8_t, 16> deltas;
    ssize_t srcOffset = 1;
    for (int dstElemBase = 0; dstElemBase < elementCount; dstElemBase += maxBlockElements) {
        const size_t attrBlockElementCount = MIN(elementCount - dstElemBase, maxBlockElements);
        const size_t groupCount = ((attrBlockElementCount + 0x0F) & ~0x0F) >> 4;
        const size_t headerByteCount = ((groupCount + 0x03) & ~0x03) >> 2;

        for (int byte = 0; byte < byteStride; ++byte) {
            ssize_t headerBitsOffset = srcOffset;

            srcOffset += headerByteCount;
            for (int group = 0; group < groupCount; ++group) {
                int deltaMode = ((source[headerBitsOffset] >> ((group & 0x03) << 1)) & 0x03);
                // If this is the last group, move to the next byte of header bits.
                if ((group & 0x03) == 0x03) {
                    ++headerBitsOffset;
                }

                const int dstElemGroup = dstElemBase + (group << 4);

                switch (deltaMode) {
                    case 0: // All 16 byte deltas are 0; the size of the encoded block is 0 bytes
                        memset(deltas.data(), 0, sizeof(deltas));
                        break;
                    case 1: { // Deltas are using 2-bit sentinel encoding; the size of the encoded block is [4..20] bytes
                        const ssize_t srcBase = srcOffset;
                        srcOffset += 0x04;
                        for (int m = 0; m < 0x10; m++) {
                            // 0 = >>> 6, 1 = >>> 4, 2 = >>> 2, 3 = >>> 0
                            const int shift = (6 - ((m & 0x03) << 1));
                            int delta = (source[srcBase + (m >> 2)] >> shift) & 0x03;
                            if (delta == 3) {
                                delta = source[srcOffset++];
                            }
                            deltas[m] = delta;
                        }
                        break;
                    }
                    case 2: { // Deltas are using 4-bit sentinel encoding; the size of the encoded block is [8..24] bytes
                        const ssize_t srcBase = srcOffset;
                        srcOffset += 8;
                        for (int m = 0; m < 16; m++) {
                            // 0 = >> 6, 1 = >> 4, 2 = >> 2, 3 = >> 0
                            const int shift = (m & 0x01) ? 0 : 4;
                            int delta = (source[srcBase + (m >> 1)] >> shift) & 0x0f;
                            if (delta == 0xf) {
                                delta = source[srcOffset++];
                            }
                            deltas[m] = delta;
                        }
                        break;
                    }
                    case 3: // All deltas are stored verbatim; the size of the encoded block is 16 bytes
                        memcpy(deltas.data(), source + srcOffset, 16);
                        srcOffset += 16;
                        break;
                }

                for (int m = 0; m < 16; ++m) {
                    const int dstElem = dstElemGroup + m;
                    if (dstElem >= elementCount) {
                        break;
                    }

                    const int delta = dezig(deltas[m]);
                    const size_t dstIndex = dstElem * byteStride + byte;
                    destination[dstIndex] = (tempData[byte] += delta);
                }
            }
        }
    }

    return YES;
}

static void GLTFApplyMeshoptFilter(uint8_t *destination, size_t elementCount, size_t stride,
                                   GLTFMeshoptCompressionFilter filter)
{
    switch (filter) {
        case GLTFMeshoptCompressionFilterOctahedral: {
            assert(stride == 4 || stride == 8);

            switch (stride) {
                case 4: {
                    int8_t *dst = reinterpret_cast<int8_t *>(destination);
                    int maxInt = 127;

                    for (int i = 0; i < 4 * elementCount; i += 4) {
                        double x = dst[i + 0], y = dst[i + 1], one = dst[i + 2];
                        x /= one;
                        y /= one;
                        const double z = 1.0 - fabs(x) - fabs(y);
                        const double t = MAX(-z, 0.0);
                        x -= (x >= 0) ? t : -t;
                        y -= (y >= 0) ? t : -t;
                        const double h = maxInt / hypot3(x, y, z);
                        dst[i + 0] = round(x * h);
                        dst[i + 1] = round(y * h);
                        dst[i + 2] = round(z * h);
                        // keep dst[i + 3] as is
                    }
                    break;
                }
                case 8: {
                    int16_t *dst = reinterpret_cast<int16_t *>(destination);
                    int maxInt = 32767;

                    for (int i = 0; i < 4 * elementCount; i += 4) {
                        double x = dst[i + 0], y = dst[i + 1], one = dst[i + 2];
                        x /= one;
                        y /= one;
                        const double z = 1.0 - fabs(x) - fabs(y);
                        const double t = MAX(-z, 0.0);
                        x -= (x >= 0) ? t : -t;
                        y -= (y >= 0) ? t : -t;
                        const double h = maxInt / hypot3(x, y, z);
                        dst[i + 0] = round(x * h);
                        dst[i + 1] = round(y * h);
                        dst[i + 2] = round(z * h);
                        // keep dst[i + 3] as is
                    }
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case GLTFMeshoptCompressionFilterQuaternion: {
            assert(stride == 8);

            int16_t *dst = reinterpret_cast<int16_t *>(destination);

            for (int i = 0; i < 4 * elementCount; i += 4) {
                const int16_t inputW = dst[i + 3];
                const int maxComponent = inputW & 0x03;
                const float s = M_SQRT1_2 / (inputW | 0x03);
                float x = dst[i + 0] * s;
                float y = dst[i + 1] * s;
                float z = dst[i + 2] * s;
                float w = sqrtf(MAX(0.0, 1.0 - (x * x) - (y * y) - (z * z)));
                dst[i + (maxComponent + 1) % 4] = roundf(x * 32767);
                dst[i + (maxComponent + 2) % 4] = roundf(y * 32767);
                dst[i + (maxComponent + 3) % 4] = roundf(z * 32767);
                dst[i + (maxComponent + 0) % 4] = roundf(w * 32767);
            }
            break;
        }
        case GLTFMeshoptCompressionFilterExponential: {
            assert(stride % 4 == 0);

            const int32_t *src = reinterpret_cast<const int32_t *>(destination);
            float *dst = reinterpret_cast<float *>(destination); // Strict aliasing violation

            for (int i = 0; i < (stride * elementCount) / 4; ++i) {
                int32_t v = src[i];
                int8_t exp = v >> 24;
                exp = MAX(-100, MIN(exp, 100));
                // We do some gymnastics here to avoid performing a left shift on a negative number,
                // which is technically UB, even though it works under Clang.
                uint32_t uv;
                memcpy(&uv, &v, sizeof(int32_t));
                uv = (uv << 8) >> 8; // Extract mantissa bits
                uv = (uv & 0x800000) ? (uv | 0xff000000) : uv; // Manual sign extension
                int32_t mantissa;
                memcpy(&mantissa, &uv, sizeof(int32_t));
                dst[i] = powf(2.0f, (float)exp) * (float)mantissa;
            }
            break;
        }
        default:
            break;
    }
}

template <typename DstInt_t>
BOOL GLTFMeshoptDecodeIndexBuffer(const uint8_t *source, size_t sourceLength, size_t count, size_t byteStride,
                                  DstInt_t *dst)
{
    assert(source[0] == 0xE1);
    assert(count % 3 == 0);
    assert(byteStride == 2 || byteStride == 4);

    const size_t triCount = count / 3;

    ssize_t codeOffset = 1;
    size_t dataOffset = codeOffset + triCount;
    ssize_t tailOffset = sourceLength - 16;

    uint32_t next = 0, last = 0;
    std::deque<uint32_t> edgefifo {}; // cap = 32
    std::deque<uint32_t> vertexfifo {}; // cap = 16

    ssize_t dstOffset = 0;
    for (int i = 0; i < triCount; i++) {
        const uint8_t code = source[codeOffset++];
        const uint8_t b0 = code >> 4, b1 = code & 0x0F;

        if (b0 < 0x0F) {
            const uint32_t a = edgefifo[(b0 << 1) + 0];
            const uint32_t b = edgefifo[(b0 << 1) + 1];
            uint32_t c = -1;

            if (b1 == 0x00) {
                c = next++;
                vertexfifo.push_front(c);
            } else if (b1 < 0x0D) {
                c = vertexfifo[b1];
            } else if (b1 == 0x0D) {
                c = --last;
                vertexfifo.push_front(c);
            } else if (b1 == 0x0E) {
                c = ++last;
                vertexfifo.push_front(c);
            } else if (b1 == 0x0F) {
                size_t v = consumeLEB128<uint32_t>(source, dataOffset);
                c = decodeIndex(v, last);
                vertexfifo.push_front(c);
            }

            edgefifo.push_front(b); edgefifo.push_front(c);
            edgefifo.push_front(c); edgefifo.push_front(a);

            dst[dstOffset++] = a;
            dst[dstOffset++] = b;
            dst[dstOffset++] = c;
        } else { // b0 == 0x0F
            uint32_t a, b, c;

            if (b1 < 0x0E) {
                uint8_t e = source[tailOffset + b1];
                uint8_t z = e >> 4;
                uint8_t w = e & 0x0F;

                a = next++;

                if (z == 0x00) {
                    b = next++;
                } else {
                    b = vertexfifo[z - 1];
                }

                if (w == 0x00) {
                    c = next++;
                } else {
                    c = vertexfifo[w - 1];
                }

                vertexfifo.push_front(a);
                if (z == 0x00) {
                    vertexfifo.push_front(b);
                }
                if (w == 0x00) {
                    vertexfifo.push_front(c);
                }
            } else {
                uint8_t e = source[dataOffset++];
                if (e == 0x00)
                    next = 0;

                uint8_t z = e >> 4;
                uint8_t w = e & 0x0F;

                if (b1 == 0x0E) {
                    a = next++;
                } else {
                    a = decodeIndex(consumeLEB128<uint32_t>(source, dataOffset), last);
                }

                if (z == 0x00) {
                    b = next++;
                } else if (z == 0x0F) {
                    b = decodeIndex(consumeLEB128<uint32_t>(source, dataOffset), last);
                } else {
                    b = vertexfifo[z - 1];
                }

                if (w == 0x00) {
                    c = next++;
                } else if (w == 0x0F) {
                    c = decodeIndex(consumeLEB128<uint32_t>(source, dataOffset), last);
                } else {
                    c = vertexfifo[w - 1];
                }

                vertexfifo.push_front(a);
                if (z == 0x00 || z == 0x0F)
                    vertexfifo.push_front(b);
                if (w == 0x00 || w == 0x0F)
                    vertexfifo.push_front(c);
            }

            edgefifo.push_front(a); edgefifo.push_front(b);
            edgefifo.push_front(b); edgefifo.push_front(c);
            edgefifo.push_front(c); edgefifo.push_front(a);

            dst[dstOffset++] = a;
            dst[dstOffset++] = b;
            dst[dstOffset++] = c;
        }
    }
    return YES;
}

template <typename DstInt_t>
BOOL GLTFMeshoptDecodeIndexSequence(const uint8_t *source, size_t count, size_t byteStride, DstInt_t *dst) {
    assert(source[0] == 0xD1);
    assert(byteStride == 2 || byteStride == 4);

    std::array<uint32_t, 2> last {};
    size_t dataOffset = 1;
    for (int i = 0; i < count; i++) {
        uint32_t v = consumeLEB128<uint32_t>(source, dataOffset);
        int b = (v & 1);
        int32_t delta = dezig(v >> 1);
        dst[i] = (last[b] += delta);
    }
    return YES;
}

BOOL GLTFMeshoptDecodeBufferView(GLTFBufferView *bufferView, uint8_t *destination, NSError **outError) {
    assert(bufferView.meshoptCompression != nil && "Cannot decode buffer view with no associated meshopt extension");

    GLTFMeshoptCompression *compression = bufferView.meshoptCompression;

    const uint8_t *sourceBufferBaseAddr = reinterpret_cast<const uint8_t *>(compression.buffer.data.bytes);
    const uint8_t *source = sourceBufferBaseAddr + compression.offset;
    size_t sourceLength = compression.length;

    switch (compression.mode) {
        case GLTFMeshoptCompressionModeAttributes: {
            GLTFMeshoptDecodeVertexBuffer(source, sourceLength, compression.count, compression.stride, destination);
            GLTFApplyMeshoptFilter(destination, compression.count, compression.stride, compression.filter);
            return YES;
        }
        case GLTFMeshoptCompressionModeTriangles: {
            switch (compression.stride) {
                case 2: {
                    uint16_t *dst = reinterpret_cast<uint16_t *>(destination);
                    return GLTFMeshoptDecodeIndexBuffer(source, sourceLength, compression.count, compression.stride, dst);
                }
                case 4: {
                    uint32_t *dst = reinterpret_cast<uint32_t *>(destination);
                    return GLTFMeshoptDecodeIndexBuffer(source, sourceLength, compression.count, compression.stride, dst);
                }
                default:
                    return NO;
            }
            break;
        }
        case GLTFMeshoptCompressionModeIndices: {
            switch (compression.stride) {
                case 2: {
                    uint16_t *dst = reinterpret_cast<uint16_t *>(destination);
                    return GLTFMeshoptDecodeIndexSequence(source, compression.count, compression.stride, dst);
                }
                case 4: {
                    uint32_t *dst = reinterpret_cast<uint32_t *>(destination);
                    return GLTFMeshoptDecodeIndexSequence(source, compression.count, compression.stride, dst);
                }
                default:
                    return NO;
            }
            break;
        }
    }
    return NO;
}
