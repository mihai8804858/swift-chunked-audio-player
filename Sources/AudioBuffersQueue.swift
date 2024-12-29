import AVFoundation
import os

final class AudioBuffersQueue: Sendable {
    private let audioDescription: AudioStreamBasicDescription
    private nonisolated(unsafe) var allBuffers = [CMSampleBuffer]()
    private nonisolated(unsafe) var buffers = [CMSampleBuffer]()
    private let lock = NSLock()

    private(set) nonisolated(unsafe) var duration = CMTime.zero

    var isEmpty: Bool {
        withLock { buffers.isEmpty }
    }

    init(audioDescription: AudioStreamBasicDescription) {
        self.audioDescription = audioDescription
        self.duration = CMTime(value: 0, timescale: Int32(audioDescription.mSampleRate))
    }

    func enqueue(
        numberOfBytes: UInt32,
        bytes: UnsafeRawPointer,
        numberOfPackets: UInt32,
        packets: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) throws {
        try withLock {
            guard let buffer = try makeSampleBuffer(
                from: Data(bytes: bytes, count: Int(numberOfBytes)),
                packetCount: numberOfPackets,
                packetDescriptions: packets
            ) else { return }
            updateDuration(for: buffer)
            buffers.append(buffer)
            allBuffers.append(buffer)
        }
    }

    func peek() -> CMSampleBuffer? {
        withLock { buffers.first }
    }

    func dequeue() -> CMSampleBuffer? {
        withLock {
            if buffers.isEmpty { return nil }
            return buffers.removeFirst()
        }
    }

    func removeFirst() {
        _ = dequeue()
    }

    func removeAll() {
        withLock {
            allBuffers.removeAll()
            buffers.removeAll()
            duration = .zero
        }
    }

    func buffer(at time: CMTime) -> CMSampleBuffer? {
        withLock { allBuffers.first { $0.timeRange.containsTime(time) } }
    }

    func flush() {
        withLock { buffers.removeAll() }
    }

    func seek(to time: CMTime) {
        withLock {
            guard let index = allBuffers.enumerated().first(where: { _, buffer in
                buffer.timeRange.containsTime(time)
            })?.offset else { return }
            buffers = Array(allBuffers[index...])
        }
    }

    // MARK: - Private

    private func makeSampleBuffer(
        from data: Data,
        packetCount: UInt32,
        packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
    ) throws -> CMSampleBuffer? {
        guard let blockBuffer = try makeBlockBuffer(from: data) else { return nil }
        let formatDescription = try CMFormatDescription(audioStreamBasicDescription: audioDescription)
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(packetCount),
            presentationTimeStamp: duration,
            packetDescriptions: packetDescriptions,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr else { throw AudioPlayerError.status(createStatus) }

        return sampleBuffer
    }

    private func makeBlockBuffer(from data: Data) throws -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == noErr else { throw AudioPlayerError.status(createStatus) }
        guard let blockBuffer else { return nil }
        return try data.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            let replaceStatus = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
            guard replaceStatus == noErr else { throw AudioPlayerError.status(replaceStatus) }

            return blockBuffer
        }
    }

    private func updateDuration(for buffer: CMSampleBuffer) {
        duration = buffer.presentationTimeStamp + buffer.duration
    }

    private func withLock<T>(_ perform: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try perform()
    }
}
