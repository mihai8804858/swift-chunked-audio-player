import AVFoundation
import AudioToolbox

final class AudioFileStream {
    typealias ErrorCallback = (_ error: AudioPlayerError) -> Void
    typealias ASBDCallback = (_ asbd: AudioStreamBasicDescription) -> Void
    typealias PacketsCallback = (
        _ numberOfBytes: UInt32,
        _ bytes: UnsafeRawPointer,
        _ numberOfPackets: UInt32,
        _ packets: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) -> Void

    private let receiveError: ErrorCallback
    private let receiveASBD: ASBDCallback
    private let receivePackets: PacketsCallback

    private let syncQueue: DispatchQueue

    private(set) var audioStreamID: AudioFileStreamID?
    private(set) var fileTypeID: AudioFileTypeID?
    private(set) var parsingComplete = false

    init(
        type: AudioFileTypeID? = nil,
        queue: DispatchQueue,
        receiveError: @escaping ErrorCallback,
        receiveASBD: @escaping ASBDCallback,
        receivePackets: @escaping PacketsCallback
    ) {
        self.fileTypeID = type
        self.syncQueue = queue
        self.receiveError = receiveError
        self.receiveASBD = receiveASBD
        self.receivePackets = receivePackets
    }

    func open() {
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
        }, fileTypeID ?? 0, &audioStreamID )
        if status != noErr { receiveError(.status(status)) }
        if audioStreamID == nil { receiveError(.streamNotOpened) }
    }

    func close() {
        guard let streamID = audioStreamID else { return }
        AudioFileStreamClose(streamID)
        audioStreamID = nil
    }

    func parseData(_ data: Data) {
        syncQueue.async { [weak self] in
            guard let self, let audioStreamID else { return }
            data.withUnsafeBytes { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                AudioFileStreamParseBytes(audioStreamID, UInt32(data.count), baseAddress, [])
            }
        }
    }

    func finishDataParsing() {
        syncQueue.async { [weak self] in
            guard let self, let audioStreamID else { return }
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
        guard getInfoStatus == noErr else { return receiveError(.status(getInfoStatus)) }
        let getPropertyStatus = AudioFileStreamGetProperty(audioStreamID, propertyID, &asbdSize, &asbd)
        guard getPropertyStatus == noErr else { return receiveError(.status(getPropertyStatus)) }
        receiveASBD(asbd)
    }

    private func onFileStreamPacketsReceived(
        numberOfBytes: UInt32,
        bytes: UnsafeRawPointer,
        numberOfPackets: UInt32,
        packets: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        receivePackets(numberOfBytes, bytes, numberOfPackets, packets)
    }
}
