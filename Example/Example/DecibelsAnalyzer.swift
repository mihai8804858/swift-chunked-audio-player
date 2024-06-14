import AVFoundation
import Accelerate

struct DecibelsAnalyzer {
    let noiseFloor: Double

    init(noiseFloor: Double = -70) {
        self.noiseFloor = noiseFloor
    }

    func decibels(from buffer: CMSampleBuffer) -> [Double]? {
        samples(from: buffer).flatMap(decibels)
    }

    private func samples(from buffer: CMSampleBuffer) -> [Int16]? {
        guard let dataBuffer = buffer.dataBuffer else { return nil }
        let size = MemoryLayout<Int16>.size
        var data = [Int16](repeating: 0, count: dataBuffer.dataLength / size)
        CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: data.count * size, destination: &data)

        return data
    }

    private func decibels(from samples: [Int16]) -> [Double]? {
        var decibelsSamples = [Double](repeating: 0, count: samples.count)
        vDSP.convertElements(of: samples, to: &decibelsSamples)
        vDSP.absolute(decibelsSamples, result: &decibelsSamples)
        vDSP.convert(amplitude: decibelsSamples, toDecibels: &decibelsSamples, zeroReference: Double(Int16.max))
        decibelsSamples = vDSP.clip(decibelsSamples, to: Double(noiseFloor)...0)

        return decibelsSamples
    }
}
