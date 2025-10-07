import simd

import ModelIO // for now

func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + t * (b - a)
}

func lerp(_ a: simd_float3, _ b: simd_float3, _ t: Float) -> simd_float3 {
    return a + t * (b - a)
}

func lerp(_ a: simd_quatf, _ b: simd_quatf, _ t: Float) -> simd_quatf {
    return simd_quatf(vector: a.vector + t * (b.vector - a.vector))
}

func unlerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    if a == b { return 0 } // No solution; avoid division by zero
    return (t - a) / (b - a)
}

//func cubic_interp(_ a: Float, _ b: Float,
//                  _ leftTangent: Float, _ rightTangent: Float,
//                  _ t: Float, _ dT: Float) -> Float
//{
//    let t2 = t * t, t3 = t2 * t
//    return (2 * t3 - 3 * t2 + 1) * a +
//           dT * (t3 - 2 * t2 + t) * leftTangent +
//           (-2 * t3 + 3 * t2) * b +
//           dT * (t3 - t2) * rightTangent
//}

func cubic_interp(_ a: SIMD3<Float>, _ b: SIMD3<Float>,
                  _ leftTangent: SIMD3<Float>, _ rightTangent: SIMD3<Float>,
                  _ t: Float, _ dT: Float) -> SIMD3<Float>
{
    let t2 = t * t, t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * a +
           dT * (t3 - 2 * t2 + t) * leftTangent +
           (-2 * t3 + 3 * t2) * b +
           dT * (t3 - t2) * rightTangent
}

protocol GLTFAnimatedValue {
    var sampleCount: Int { get }
    var minimumTime: Float { get }
    var maximumTime: Float { get }
    var interpolation: GLTFInterpolationMode { get }
    var keyTimes: [Float] { get }
}

extension GLTFAnimatedValue {
    var sampleCount: Int {
        return keyTimes.count
    }

    var minimumTime: Float {
        return keyTimes.first ?? 0.0
    }

    var maximumTime: Float {
        return keyTimes.last ?? 0.0
    }

    func keyTimeIndicesFor(time: Float) -> (index: Int, nextIndex: Int)? {
        guard !keyTimes.isEmpty else { return nil }
        if time <= keyTimes[0] {
            return keyTimes.count > 1 ? (0, 1) : (0, 0)
        }
        if time >= keyTimes[keyTimes.count - 1] {
            let lastIndex = keyTimes.count - 1
            return lastIndex > 0 ? (lastIndex - 1, lastIndex) : (lastIndex, lastIndex)
        }
        // Binary search
        var low = 0
        var high = keyTimes.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if keyTimes[mid] <= time {
                low = mid
            } else {
                high = mid
            }
        }
        return (low, high)
    }
}

class GLTFAnimatedVector3 : GLTFAnimatedValue {
    let keyTimes: [Float]
    let values: [SIMD3<Float>]
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [SIMD3<Float>], interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.interpolation = interpolation

        if interpolation == .cubic {
            assert(values.count == keyTimes.count * 3)
        } else {
            assert(values.count == keyTimes.count)
        }
    }

    func value(at time: Float) -> SIMD3<Float> {
        guard !values.isEmpty else { return [0, 0, 0] }

        guard let (index, nextIndex) = keyTimeIndicesFor(time: time) else {
            return values[0]
        }

        if index == nextIndex {
            return values[index]
        }

        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = unlerp(t0, t1, time)

        switch interpolation {
        case .step:
            return values[index]
        case .linear:
            return lerp(values[index], values[nextIndex], factor)
        case .cubic:
            return cubic_interp(values[index * 3 + 1], values[nextIndex * 3 + 1],
                                values[index * 3 + 2], values[nextIndex * 3 + 0],
                                factor, (t1 - t0))
        default:
            return lerp(values[index], values[nextIndex], factor)
        }
    }
}

class GLTFAnimatedQuaternion : GLTFAnimatedValue {
    let keyTimes: [Float]
    let values: [simd_quatf]
    let interpolation: GLTFInterpolationMode

    init(keyTimes: [Float], values: [simd_quatf], interpolation: GLTFInterpolationMode) {
        self.keyTimes = keyTimes
        self.values = values
        self.interpolation = interpolation
    }

    func value(at time: Float) -> simd_quatf {
        guard !values.isEmpty else { return simd_quatf() }

        guard let (index, nextIndex) = keyTimeIndicesFor(time: time) else {
            return values[0]
        }

        if index == nextIndex {
            return values[index]
        }

        let t0 = keyTimes[index]
        let t1 = keyTimes[nextIndex]
        let factor = unlerp(t0, t1, time)

        switch interpolation {
        case .step:
            return values[index]
        case .linear:
            return simd_slerp(values[index], values[nextIndex], factor)
        case .cubic:
            // TODO: cubic quaternion interpolation
            return simd_slerp(values[index * 3 + 1], values[nextIndex * 3 + 1], factor)
        default:
            return simd_slerp(values[index], values[nextIndex], factor)
        }
    }
}

class GLTFTransformSampler {
    let startTime: Float
    let endTime: Float
    let recommendedSampleInterval: Float
    let translation: GLTFAnimatedVector3
    let rotation: GLTFAnimatedQuaternion
    let scale: GLTFAnimatedVector3
    let hasStepChannel: Bool

    init(target: GLTFNode, translationChannel: GLTFAnimationChannel?,
         rotationChannel: GLTFAnimationChannel?, scaleChannel: GLTFAnimationChannel?,
         maximumSampleInterval: Float)
    {
        var minTime: Float = .infinity, maxTime: Float = -.infinity
        for channel in [translationChannel, rotationChannel, scaleChannel] {
            if let sampler = channel?.sampler {
                let input = sampler.input
                let channelMinTime = input.minValues.first?.floatValue ?? .infinity
                let channelMaxTime = input.maxValues.first?.floatValue ?? -.infinity
                minTime = min(minTime, channelMinTime)
                maxTime = max(maxTime, channelMaxTime)
            }
        }
        var translationTimes = [minTime]; var translationValues = [target.translation]
        var translationInterp = GLTFInterpolationMode.linear
        if let sampler = translationChannel?.sampler,
           let times = packedFloatArray(for: sampler.input),
           let values = packedFloat3Array(for: sampler.output)
        {
            translationTimes = times
            translationValues = values
            translationInterp = sampler.interpolationMode

        }
        var rotationTimes = [minTime]; var rotationValues = [target.rotation]
        var rotationInterp = GLTFInterpolationMode.linear
        if let sampler = rotationChannel?.sampler,
           let times = packedFloatArray(for: sampler.input),
           let values = packedQuatfArray(for: sampler.output)
        {
            rotationTimes = times
            rotationValues = values
            rotationInterp = sampler.interpolationMode
        }
        var scaleTimes = [minTime]; var scaleValues = [target.scale]
        var scaleInterp = GLTFInterpolationMode.linear
        if let sampler = scaleChannel?.sampler,
           let times = packedFloatArray(for: sampler.input),
           let values = packedFloat3Array(for: sampler.output)
        {
            scaleTimes = times
            scaleValues = values
            scaleInterp = sampler.interpolationMode
        }
        startTime = minTime
        endTime = maxTime
        hasStepChannel = (translationInterp == .step) || (rotationInterp == .step) || (scaleInterp == .step)

        translation = GLTFAnimatedVector3(keyTimes: translationTimes, values: translationValues, interpolation: translationInterp)
        rotation = GLTFAnimatedQuaternion(keyTimes: rotationTimes, values: rotationValues, interpolation: rotationInterp)
        scale = GLTFAnimatedVector3(keyTimes: scaleTimes, values: scaleValues, interpolation: scaleInterp)

        let duration = maxTime - minTime
        let averageKeyDuration = duration / Float(max(translationTimes.count, max(rotationTimes.count, scaleTimes.count)))
        recommendedSampleInterval = averageKeyDuration > maximumSampleInterval ? maximumSampleInterval : averageKeyDuration
    }
}
