import AVFoundation
import SwiftUI

final class DecibelsViewModel: ObservableObject {
    private let decibelsAnalyzer = DecibelsAnalyzer()
    private var decibelsRanges: [CMTimeRange: [Double]] = [:]

    @Published private(set) var decibels: Double?
    @Published private(set) var decibelsFraction: Double?

    func setTime(_ time: CMTime) {
        if let samplesRange = decibelsRanges.first(where: { $0.key.containsTime(time) }) {
            let sampleDuration = samplesRange.key.duration.seconds / Double(samplesRange.value.count)
            let offset = (time - samplesRange.key.start).seconds
            let index = Int(offset / sampleDuration)
            decibels = samplesRange.value[safe: index]
            decibelsFraction = decibels.map { abs($0) / abs(decibelsAnalyzer.noiseFloor) }
        } else {
            decibelsFraction = nil
            decibels = nil
        }
    }

    func addBuffer(_ buffer: CMSampleBuffer?) {
        guard let buffer, let bufferDecibels = decibelsAnalyzer.decibels(from: buffer) else { return }
        decibelsRanges[buffer.timeRange] = bufferDecibels
    }

    func removeAll() {
        decibelsRanges.removeAll()
        decibelsFraction = nil
        decibels = nil
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
