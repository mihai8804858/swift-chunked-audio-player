import AVFoundation

#if swift(>=6.0)
extension CMSampleBuffer: @unchecked @retroactive Sendable {}
#else
extension CMSampleBuffer: @unchecked Sendable {}
#endif

extension CMSampleBuffer {
    public var timeRange: CMTimeRange {
        CMTimeRange(start: presentationTimeStamp, duration: duration)
    }
}
