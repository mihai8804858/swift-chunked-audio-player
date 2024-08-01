import AVFoundation

#if hasAttribute(retroactive)
extension CMSampleBuffer: @unchecked @retroactive Sendable {}
#else
extension CMSampleBuffer: @unchecked Sendable {}
#endif

extension CMSampleBuffer {
    public var timeRange: CMTimeRange {
        CMTimeRange(start: presentationTimeStamp, duration: duration)
    }
}
