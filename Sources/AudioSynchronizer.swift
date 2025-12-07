import AVFoundation
import AudioToolbox
import Combine

final class AudioSynchronizer: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case playing
        case paused
        case complete
        case failed(AudioPlayerError?)
    }

    enum Event: Equatable, Sendable {
        case stateChanged(State)
        case rateChanged(Float)
        case timeChanged(CMTime)
        case durationChanged(CMTime)
        case sampleBufferChanged(CMSampleBuffer?)
    }

    private let queue = DispatchQueue(label: "audio.player.queue")
    private let onEvent: @Sendable (Event) -> Void
    private let timeUpdateInterval: CMTime

    private var isBuffering = false
    private var receiveComplete = false
    private var audioBuffersQueue: AudioBuffersQueue?
    private var audioFileStream: AudioFileStream?
    private var audioRenderer: AVSampleBufferAudioRenderer?
    private var audioSynchronizer: AVSampleBufferRenderSynchronizer?
    private var currentSampleBufferTime: CMTime?

    private var audioRendererErrorCancellable: AnyCancellable?
    private var audioRendererRateCancellable: AnyCancellable?
    private var audioRendererTimeCancellable: AnyCancellable?

    private var dataComplete: Bool {
        receiveComplete && audioFileStream?.parsingComplete == true
    }

    var rate: Float = 1.0 {
        didSet {
            if rate == 0.0 {
                pause()
            } else {
                resume(at: rate)
            }
        }
    }

    var volume: Float = 1.0 {
        didSet {
            audioRenderer?.volume = volume
        }
    }

    var isMuted: Bool = false {
        didSet {
            audioRenderer?.isMuted = isMuted
        }
    }

    init(
        timeUpdateInterval: CMTime,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.timeUpdateInterval = timeUpdateInterval
        self.onEvent = onEvent
    }

    func prepare(type: AudioFileTypeID? = nil) {
        invalidate()
        audioFileStream = makeFileStream(type: type)
        audioFileStream?.open()
    }

    func pause() {
        guard let audioSynchronizer, audioSynchronizer.rate != 0.0 else { return }
        audioSynchronizer.rate = 0.0
        rate = 0
        onEvent(.stateChanged(.paused))
    }

    func resume(at resumeRate: Float = 1.0) {
        guard let audioSynchronizer else { return }
        let oldRate = audioSynchronizer.rate
        guard audioSynchronizer.rate != resumeRate else { return }
        audioSynchronizer.rate = resumeRate
        rate = resumeRate
        if oldRate == 0.0 && resumeRate != 0.0 {
            onEvent(.stateChanged(.playing))
        }
    }

    func rewind(_ time: CMTime) {
        guard let audioSynchronizer else { return }
        seek(to: audioSynchronizer.currentTime() - time)
    }

    func forward(_ time: CMTime) {
        guard let audioSynchronizer else { return }
        seek(to: audioSynchronizer.currentTime() + time)
    }

    func seek(to time: CMTime) {
        guard let audioSynchronizer, let audioRenderer, let audioBuffersQueue else { return }
        let range = CMTimeRange(start: .zero, duration: audioBuffersQueue.duration)
        let clampedTime = time.clamped(to: range)
        let currentRate = audioSynchronizer.rate
        audioSynchronizer.rate = 0.0
        audioRenderer.stopRequestingMediaData()
        audioRenderer.flush()
        audioBuffersQueue.flush()
        audioBuffersQueue.seek(to: clampedTime)
        restartRequestingMediaData(audioRenderer, from: clampedTime, rate: currentRate)
    }

    func receive(data: Data) {
        audioFileStream?.parseData(data)
    }

    func finish() {
        audioFileStream?.finishDataParsing()
        receiveComplete = true
    }

    func invalidate(_ completion: @escaping @Sendable () -> Void = {}) {
        removeBuffers()
        closeFileStream()
        cancelObservation()
        isBuffering = false
        receiveComplete = false
        currentSampleBufferTime = nil
        onEvent(.sampleBufferChanged(nil))
        if let audioSynchronizer, let audioRenderer {
            audioRenderer.stopRequestingMediaData()
            audioSynchronizer.removeRenderer(audioRenderer, at: .zero) { [weak self] _ in
                self?.audioRenderer = nil
                self?.audioSynchronizer = nil
                completion()
            }
        } else {
            audioRenderer = nil
            audioSynchronizer = nil
            completion()
        }
    }

    // MARK: - Private

    private func makeFileStream(type: AudioFileTypeID?) -> AudioFileStream {
        AudioFileStream(type: type) { [weak self] event in
            guard let self else { return }
            switch event {
            case let .failure(error): onEvent(.stateChanged(.failed(error)))
            case let .asbdReceived(asbd): onFileStreamDescriptionReceived(asbd: asbd)
            case let .packetsReceived(packets): onFileStreamPacketsReceived(packets: packets)
            }
        }
    }

    private func onFileStreamDescriptionReceived(asbd: AudioStreamBasicDescription) {
        let renderer = AVSampleBufferAudioRenderer()
        renderer.volume = volume
        renderer.isMuted = isMuted
        let synchronizer = AVSampleBufferRenderSynchronizer()
        synchronizer.addRenderer(renderer)
        audioRenderer = renderer
        audioSynchronizer = synchronizer
        audioBuffersQueue = AudioBuffersQueue(audioDescription: asbd)
        observeRenderer(renderer, synchronizer: synchronizer)
        startRequestingMediaData(renderer)
    }

    private func onFileStreamPacketsReceived(packets: AudioFileStream.Packets) {
        do {
            guard let audioBuffersQueue, let audioSynchronizer, let audioRenderer else { return }
            try audioBuffersQueue.enqueue(packets: packets)
            onEvent(.durationChanged(audioBuffersQueue.duration))
            if let buffer = audioBuffersQueue.peek(), isBuffering {
                audioRenderer.enqueue(buffer)
                audioBuffersQueue.removeFirst()
                if audioRenderer.hasSufficientMediaDataForReliablePlaybackStart || dataComplete {
                    audioSynchronizer.setRate(rate, time: audioSynchronizer.currentTime())
                    isBuffering = false
                }
            }
        } catch {
            onEvent(.stateChanged(.failed(AudioPlayerError(error: error))))
        }
    }

    private func startRequestingMediaData(_ renderer: AVSampleBufferAudioRenderer) {
        nonisolated(unsafe) var didStart = false
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self, let audioRenderer, let audioBuffersQueue else { return }
            while let buffer = audioBuffersQueue.peek(), audioRenderer.isReadyForMoreMediaData {
                audioRenderer.enqueue(buffer)
                audioBuffersQueue.removeFirst()
                startPlaybackIfNeeded(at: .zero, didStart: &didStart)
            }
            startPlaybackIfNeeded(at: .zero, didStart: &didStart)
            stopRequestingMediaDataIfNeeded()
        }
    }

    private func restartRequestingMediaData(_ renderer: AVSampleBufferAudioRenderer, from time: CMTime, rate: Float) {
        nonisolated(unsafe) var didStart = false
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self, let audioRenderer, let audioSynchronizer, let audioBuffersQueue else { return }
            while let buffer = audioBuffersQueue.peek(), audioRenderer.isReadyForMoreMediaData {
                audioRenderer.enqueue(buffer)
                audioBuffersQueue.removeFirst()
            }
            if !didStart {
                audioSynchronizer.setRate(rate, time: time)
                didStart = true
            }
            stopRequestingMediaDataIfNeeded()
        }
    }

    private func startPlaybackIfNeeded(at time: CMTime, didStart: inout Bool) {
        guard let audioRenderer,
              let audioSynchronizer,
              audioSynchronizer.rate == 0,
              !didStart else { return }
        let shouldStart = audioRenderer.hasSufficientMediaDataForReliablePlaybackStart || dataComplete
        guard shouldStart else { return }
        audioSynchronizer.setRate(rate, time: time)
        didStart = true
        onEvent(.stateChanged(.playing))
    }

    private func stopRequestingMediaDataIfNeeded() {
        guard let audioRenderer, let audioBuffersQueue else { return }
        if audioBuffersQueue.isEmpty && dataComplete {
            audioRenderer.stopRequestingMediaData()
        }
    }

    private func closeFileStream() {
        audioFileStream?.close()
        audioFileStream = nil
    }

    private func removeBuffers() {
        audioBuffersQueue?.removeAll()
        audioBuffersQueue = nil
        audioRenderer?.flush()
    }

    private func observeRenderer(
        _ renderer: AVSampleBufferAudioRenderer,
        synchronizer: AVSampleBufferRenderSynchronizer
    ) {
        observeRate(synchronizer)
        observeTime(renderer)
        observeError(renderer)
    }

    private func cancelObservation() {
        cancelRateObservation()
        cancelTimeObservation()
        cancelErrorObservation()
    }

    private func observeRate(_ audioSynchronizer: AVSampleBufferRenderSynchronizer) {
        cancelRateObservation()
        let name = AVSampleBufferRenderSynchronizer.rateDidChangeNotification
        audioRendererRateCancellable = NotificationCenter.default
            .publisher(for: name).sink { [weak self, weak audioSynchronizer] _ in
                guard let self, let audioSynchronizer else { return }
                onEvent(.rateChanged(audioSynchronizer.rate))
            }
    }

    private func cancelRateObservation() {
        audioRendererRateCancellable?.cancel()
        audioRendererRateCancellable = nil
    }

    private func observeTime(_ audioRenderer: AVSampleBufferAudioRenderer) {
        cancelTimeObservation()
        audioRendererTimeCancellable = audioSynchronizer?.periodicTimeObserver(
            interval: timeUpdateInterval,
            queue: queue
        ).sink { [weak self] time in
            guard let self else { return }
            updateCurrentBufferIfNeeded(at: time)
            if let audioBuffersQueue, let audioSynchronizer, time >= audioBuffersQueue.duration {
                audioSynchronizer.setRate(0.0, time: audioBuffersQueue.duration)
                onEvent(.timeChanged(audioBuffersQueue.duration))
                onEvent(.rateChanged(0.0))
                if dataComplete { // finished playback
                    invalidate()
                    onEvent(.stateChanged(.complete))
                } else { // buffering
                    isBuffering = true
                }
            } else {
                onEvent(.timeChanged(time))
            }
        }
    }

    private func updateCurrentBufferIfNeeded(at time: CMTime) {
        guard let audioBuffersQueue,
              let buffer = audioBuffersQueue.buffer(at: time),
              buffer.presentationTimeStamp != currentSampleBufferTime else { return }
        onEvent(.sampleBufferChanged(buffer))
        currentSampleBufferTime = buffer.presentationTimeStamp
    }

    private func cancelTimeObservation() {
        audioRendererTimeCancellable?.cancel()
        audioRendererTimeCancellable = nil
    }

    private func observeError(_ audioRenderer: AVSampleBufferAudioRenderer) {
        cancelErrorObservation()
        audioRendererErrorCancellable = audioRenderer.publisher(for: \.error).sink { [weak self] error in
            guard let self else { return }
            onEvent(.stateChanged(.failed(error.flatMap(AudioPlayerError.init))))
        }
    }

    private func cancelErrorObservation() {
        audioRendererErrorCancellable?.cancel()
        audioRendererErrorCancellable = nil
    }
}
