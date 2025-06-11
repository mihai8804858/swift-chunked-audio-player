import AVFoundation
import AudioToolbox
import Combine

// MARK: - AudioSynchronizer
// A thin wrapper around AVSampleBufferRenderSynchronizer that
// lets us stream, seek, and change playback rate on the fly.

final class AudioSynchronizer: @unchecked Sendable {

    // MARK: - Callback type-aliases
    typealias RateCallback       = @Sendable (_ rate: Float) -> Void
    typealias TimeCallback       = @Sendable (_ time: CMTime) -> Void
    typealias DurationCallback   = @Sendable (_ duration: CMTime) -> Void
    typealias ErrorCallback      = @Sendable (_ error: AudioPlayerError?) -> Void
    typealias CompleteCallback   = @Sendable () -> Void
    typealias PlayingCallback    = @Sendable () -> Void
    typealias PausedCallback     = @Sendable () -> Void
    typealias SampleBufferCallback = @Sendable (_ buffer: CMSampleBuffer?) -> Void

    // MARK: - Configuration
    private let queue = DispatchQueue(label: "audio.player.queue", qos: .userInitiated)
    private let timeUpdateInterval: CMTime
    private let initialVolume: Float

    // MARK: - Callbacks
    private let onRateChanged: RateCallback
    private let onTimeChanged: TimeCallback
    private let onDurationChanged: DurationCallback
    private let onError: ErrorCallback
    private let onComplete: CompleteCallback
    private let onPlaying: PlayingCallback
    private let onPaused: PausedCallback
    private let onSampleBufferChanged: SampleBufferCallback

    // MARK: - Dynamic state (always accessed on `queue`)
    private nonisolated(unsafe) var receiveComplete                 = false
    private nonisolated(unsafe) var audioBuffersQueue: AudioBuffersQueue?
    private nonisolated(unsafe) var audioFileStream: AudioFileStream?
    private nonisolated(unsafe) var audioRenderer: AVSampleBufferAudioRenderer?
    private nonisolated(unsafe) var audioSynchronizer: AVSampleBufferRenderSynchronizer?
    private nonisolated(unsafe) var currentSampleBufferTime: CMTime?

    // --- NEW: make `finish()` idempotent ---
    // Removed NSLock to avoid crashes; use dispatch queue for synchronization
    private var didFinish = false

    // MARK: - Combine cancellables
    private nonisolated(unsafe) var rateCancellable   : AnyCancellable?
    private nonisolated(unsafe) var timeCancellable   : AnyCancellable?
    private nonisolated(unsafe) var errorCancellable  : AnyCancellable?

    // MARK: - User-controlled properties
    nonisolated(unsafe) var desiredRate: Float = 1.0 {
        didSet { desiredRate == 0 ? pause() : resume(at: desiredRate) }
    }

    var volume: Float {
        get { audioRenderer?.volume ?? initialVolume }
        set { audioRenderer?.volume = newValue }
    }

    var isMuted: Bool {
        get { audioRenderer?.isMuted ?? false }
        set { audioRenderer?.isMuted = newValue }
    }

    // MARK: - Init
    init(
        timeUpdateInterval: CMTime,
        initialVolume: Float = 1.0,
        onRateChanged:       @escaping RateCallback       = { _ in },
        onTimeChanged:       @escaping TimeCallback       = { _ in },
        onDurationChanged:   @escaping DurationCallback   = { _ in },
        onError:             @escaping ErrorCallback      = { _ in },
        onComplete:          @escaping CompleteCallback   = {},
        onPlaying:           @escaping PlayingCallback    = {},
        onPaused:            @escaping PausedCallback     = {},
        onSampleBufferChanged: @escaping SampleBufferCallback = { _ in }
    ) {
        self.timeUpdateInterval    = timeUpdateInterval
        self.initialVolume         = initialVolume
        self.onRateChanged         = onRateChanged
        self.onTimeChanged         = onTimeChanged
        self.onDurationChanged     = onDurationChanged
        self.onError               = onError
        self.onComplete            = onComplete
        self.onPlaying             = onPlaying
        self.onPaused              = onPaused
        self.onSampleBufferChanged = onSampleBufferChanged
    }

    // MARK: - Public API
  func prepare(type: AudioFileTypeID? = nil) {
    invalidate()

    audioFileStream = AudioFileStream(
      type: type,
      queue: queue,
      receiveError: { [weak self] error in          // ← fixed label
        self?.onError(error)
      },
      receiveASBD: { [weak self] asbd in
        self?.onASBD(asbd)
      },
      receivePackets: { [weak self] bytes, ptr, count, desc in
        self?.onPackets(bytes, ptr, count, desc)
      }
    )

    audioFileStream?.open()
  }

    func receive(data: Data) { audioFileStream?.parseData(data) }

    func pause() {
        guard let s = audioSynchronizer, s.rate != .zero else { return }
        s.rate = .zero
        onPaused()
    }

    func resume(at rate: Float? = nil) {
        guard let s = audioSynchronizer else { return }
        let new = rate ?? desiredRate
        guard s.rate != new else { return }
        let wasPaused = s.rate == .zero
        s.rate = new
        if wasPaused { onPlaying() }
    }

    func rewind(_ amount: CMTime)   { seek(to: currentTime - amount) }
    func forward(_ amount: CMTime)  { seek(to: currentTime + amount) }

    func seek(to time: CMTime) {
        guard
            let sync = audioSynchronizer,
            let rend = audioRenderer,
            let bufQ = audioBuffersQueue
        else { return }

        let range       = CMTimeRange(start: .zero, duration: bufQ.duration)
        let clampedTime = time.clamped(to: range)
        let oldRate     = sync.rate

        sync.rate = .zero
        rend.stopRequestingMediaData()
        rend.flush()

        bufQ.flush()
        bufQ.seek(to: clampedTime)
        restartRequestingMediaData(rend, from: clampedTime, rate: oldRate)
    }

    /// Flush any remaining data into the parser.
    /// Safe to call more than once—the first call wins.
    func finish() {
        queue.async { [weak self] in
            guard let self = self, !self.didFinish else { return }
            self.didFinish = true
            self.audioFileStream?.finishDataParsing()
            self.receiveComplete = true
        }
    }

    func invalidate(_ done: @escaping @Sendable () -> Void = {}) {
        removeBuffers()
        closeFileStream()
        cancelObservers()

        receiveComplete         = false
        currentSampleBufferTime = nil
        onSampleBufferChanged(nil)

        // Break any retain cycle *before* telling the AV synchronizer to
        // remove its renderer.
        let sync = audioSynchronizer
        let rend = audioRenderer
        audioSynchronizer = nil
        audioRenderer     = nil

        guard let sync = sync, let rend = rend else {
            done()
            return
        }

        rend.stopRequestingMediaData()
        sync.removeRenderer(rend, at: .zero) { _ in
            done()
        }
    }

    // MARK: - Convenience
    private var currentTime: CMTime {
        audioSynchronizer?.currentTime() ?? .zero
    }

    // MARK: - Private: File stream callbacks
    private func onASBD(_ asbd: AudioStreamBasicDescription) {
        let renderer     = AVSampleBufferAudioRenderer()
        renderer.volume  = initialVolume

        let sync         = AVSampleBufferRenderSynchronizer()
        sync.addRenderer(renderer)

        audioRenderer       = renderer
        audioSynchronizer   = sync
        audioBuffersQueue   = AudioBuffersQueue(audioDescription: asbd)

        observeRenderer(renderer, sync: sync)
        startRequestingMediaData(renderer)
    }

    private func onPackets(
        _ numberOfBytes: UInt32,
        _ bytes: UnsafeRawPointer,
        _ numberOfPackets: UInt32,
        _ packets: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        do {
            try audioBuffersQueue?.enqueue(
                numberOfBytes: numberOfBytes,
                bytes: bytes,
                numberOfPackets: numberOfPackets,
                packets: packets
            )
        } catch { onError(AudioPlayerError(error: error)) }
    }

    // MARK: - Private: Buffer streaming
    private func startRequestingMediaData(_ renderer: AVSampleBufferAudioRenderer) {
        nonisolated(unsafe) var didStart = false
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.drainBuffers(renderer: renderer, didStart: &didStart)
        }
    }

    private func restartRequestingMediaData(
        _ renderer: AVSampleBufferAudioRenderer,
        from time: CMTime,
        rate: Float
    ) {
        nonisolated(unsafe) var didStart = false
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self else { return }

            drainBuffers(renderer: renderer, didStart: &didStart)
            if !didStart, let s = audioSynchronizer {
                s.setRate(rate, time: time)
                didStart = true
            }
            stopIfRequestComplete()
        }
    }

    private func drainBuffers(
        renderer: AVSampleBufferAudioRenderer,
        didStart: inout Bool
    ) {
        guard
            let bufQ = audioBuffersQueue,
            renderer.isReadyForMoreMediaData
        else { return }

        while
            let buffer = bufQ.peek(),
            renderer.isReadyForMoreMediaData
        {
            renderer.enqueue(buffer)
            bufQ.removeFirst()
            onDurationChanged(bufQ.duration)

            startPlaybackIfNeeded(didStart: &didStart)
        }

        startPlaybackIfNeeded(didStart: &didStart)
        stopIfRequestComplete()
    }

    private func startPlaybackIfNeeded(didStart: inout Bool) {
        guard
            let rend = audioRenderer,
            let sync = audioSynchronizer,
            let stream = audioFileStream,
            sync.rate == 0,                        // paused
            !didStart
        else { return }

        let bufferingOK = rend.hasSufficientMediaDataForReliablePlaybackStart
        let streamDone  = receiveComplete && stream.parsingComplete
        guard bufferingOK || streamDone else { return }

        sync.setRate(desiredRate, time: .zero)
        didStart = true
        onPlaying()
    }

    private func stopIfRequestComplete() {
        guard
            let rend = audioRenderer,
            let bufQ = audioBuffersQueue,
            let stream = audioFileStream
        else { return }

        if bufQ.isEmpty && receiveComplete && stream.parsingComplete {
            rend.stopRequestingMediaData()
        }
    }

    // MARK: - Private: Cleanup
    private func removeBuffers() {
        audioBuffersQueue?.removeAll()
        audioBuffersQueue = nil
        audioRenderer?.flush()
    }

    private func closeFileStream() {
        audioFileStream?.close()
        audioFileStream = nil
    }

    // MARK: - Private: Observation
    private func observeRenderer(
        _ renderer: AVSampleBufferAudioRenderer,
        sync: AVSampleBufferRenderSynchronizer
    ) {
        observeRate(sync)
        observeTime(renderer)
        observeError(renderer)
    }

    private func cancelObservers() {
        rateCancellable?.cancel();   rateCancellable   = nil
        timeCancellable?.cancel();   timeCancellable   = nil
        errorCancellable?.cancel();  errorCancellable  = nil
    }

    private func observeRate(_ sync: AVSampleBufferRenderSynchronizer) {
        rateCancellable = NotificationCenter.default
            .publisher(for: AVSampleBufferRenderSynchronizer.rateDidChangeNotification)
            .sink { [weak self, weak sync] _ in
                guard let self, let sync else { return }
                onRateChanged(sync.rate)
            }
    }

    private func observeTime(_ renderer: AVSampleBufferAudioRenderer) {
        timeCancellable = audioSynchronizer?
            .periodicTimeObserver(interval: timeUpdateInterval, queue: queue)
            .sink { [weak self] time in
                guard let self else { return }
                updateCurrentBufferIfNeeded(at: time)

                if
                    let bufQ = audioBuffersQueue,
                    time >= bufQ.duration,
                    let sync = audioSynchronizer
                {
                    onTimeChanged(bufQ.duration)
                    sync.setRate(0, time: sync.currentTime())
                    onRateChanged(0)
                    onComplete()
                    invalidate()
                } else {
                    onTimeChanged(time)
                }
            }
    }

    private func updateCurrentBufferIfNeeded(at time: CMTime) {
        guard
            let bufQ = audioBuffersQueue,
            let buffer = bufQ.buffer(at: time),
            buffer.presentationTimeStamp != currentSampleBufferTime
        else { return }

        onSampleBufferChanged(buffer)
        currentSampleBufferTime = buffer.presentationTimeStamp
    }

    private func observeError(_ renderer: AVSampleBufferAudioRenderer) {
        errorCancellable = renderer.publisher(for: \.error)
            .sink { [weak self] error in
                guard let self else { return }
                onError(error.flatMap(AudioPlayerError.init))
            }
    }
}
