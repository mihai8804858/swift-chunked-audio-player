import AVFoundation
import AudioToolbox

final class AudioFileStream: @unchecked Sendable {
    struct Packets: @unchecked Sendable {
        let numberOfBytes: UInt32
        let bytes: UnsafeRawPointer
        let numberOfPackets: UInt32
        let packets: UnsafeMutablePointer<AudioStreamPacketDescription>?
    }

    enum Event: Sendable {
        case asbdReceived(AudioStreamBasicDescription)
        case packetsReceived(Packets)
        case failure(AudioPlayerError)
    }

    private let lock = NSLock()
    private let onEvent: @Sendable (Event) -> Void

    private(set) var audioStreamID: AudioFileStreamID?
    private(set) var fileTypeID: AudioFileTypeID?
    private(set) var parsingComplete = false

    init(
        type: AudioFileTypeID? = nil,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.fileTypeID = type
        self.onEvent = onEvent
    }

    func open() {
        withLock(lock) {
            let instance = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let status = AudioFileStreamOpen(instance, { instance, _, propertyID, _ in
                let stream = Unmanaged<AudioFileStream>.fromOpaque(instance).takeUnretainedValue()
                stream.onFileStreamPropertyReceived(propertyID: propertyID)
            }, { instance, numberBytes, numberPackets, bytes, packets in
                let stream = Unmanaged<AudioFileStream>.fromOpaque(instance).takeUnretainedValue()
                stream.onFileStreamPacketsReceived(
                    numberOfBytes: numberBytes,
                    bytes: bytes,
                    numberOfPackets: numberPackets,
                    packets: packets
                )
            }, fileTypeID ?? 0, &audioStreamID)
            if status != noErr { onEvent(.failure(.status(status))) }
            if audioStreamID == nil { onEvent(.failure(.streamNotOpened)) }
        }
    }

    func close() {
        withLock(lock) {
            guard let streamID = audioStreamID else { return }
            AudioFileStreamClose(streamID)
            audioStreamID = nil
        }
    }

    func parseData(_ data: Data) {
        withLock(lock) {
            guard let audioStreamID else { return }
            data.withUnsafeBytes { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                AudioFileStreamParseBytes(audioStreamID, UInt32(data.count), baseAddress, [])
            }
        }
    }

    func finishDataParsing() {
        withLock(lock) {
            guard let audioStreamID else { return }
            AudioFileStreamParseBytes(audioStreamID, 0, nil, [])
            parsingComplete = true
        }
    }

    // MARK: - Private

    private func onFileStreamPropertyReceived(propertyID: AudioFilePropertyID) {
        guard let audioStreamID = audioStreamID, propertyID == kAudioFileStreamProperty_DataFormat else { return }
        var asbdSize: UInt32 = 0
        var asbd = AudioStreamBasicDescription()
        let getInfoStatus = AudioFileStreamGetPropertyInfo(audioStreamID, propertyID, &asbdSize, nil)
        guard getInfoStatus == noErr else { return onEvent(.failure(.status(getInfoStatus))) }
        let getPropertyStatus = AudioFileStreamGetProperty(audioStreamID, propertyID, &asbdSize, &asbd)
        guard getPropertyStatus == noErr else { return onEvent(.failure(.status(getPropertyStatus))) }
        onEvent(.asbdReceived(asbd))
    }

    private func onFileStreamPacketsReceived(
        numberOfBytes: UInt32,
        bytes: UnsafeRawPointer,
        numberOfPackets: UInt32,
        packets: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        onEvent(.packetsReceived(Packets(
            numberOfBytes: numberOfBytes,
            bytes: bytes,
            numberOfPackets: numberOfPackets,
            packets: packets
        )))
    }
}
