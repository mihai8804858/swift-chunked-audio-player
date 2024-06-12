import AVFoundation

extension CMSampleBuffer: @unchecked Sendable {}

extension CMSampleBuffer {
    public var timeRange: CMTimeRange {
        CMTimeRange(start: presentationTimeStamp, duration: duration)
    }
}
