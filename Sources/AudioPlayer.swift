import Foundation
import Combine
import AVFoundation
import AudioToolbox

@MainActor
public final class AudioPlayer: ObservableObject, Sendable {
    private let timeUpdateInterval: CMTime
    private let initialVolume: Float
    private nonisolated(unsafe) var task: Task<Void, Never>?
    private nonisolated(unsafe) var synchronizer: AudioSynchronizer?
    private let didStartPlaying: @Sendable () -> Void
    private let didFinishPlaying: @Sendable () -> Void
    private let didUpdateBuffer: @Sendable (CMSampleBuffer) -> Void

    @Published public private(set) var currentError: AudioPlayerError?
    @Published public private(set) var currentState = AudioPlayerState.initial
    @Published public private(set) var currentRate = Float.zero
    @Published public private(set) var currentTime = CMTime.zero
    @Published public private(set) var currentDuration = CMTime.zero
    @Published public private(set) var currentBuffer: CMSampleBuffer?

    public var volume: Float {
        get { synchronizer?.volume ?? initialVolume }
        set { synchronizer?.volume = newValue }
    }

    public var isMuted: Bool {
        get { synchronizer?.isMuted ?? false }
        set { synchronizer?.isMuted = newValue }
    }

    public var rate: Float {
        get { synchronizer?.desiredRate ?? 0 }
        set { synchronizer?.desiredRate = newValue }
    }

    public init(
        timeUpdateInterval: CMTime = CMTime(value: 1, timescale: 10),
        initialVolume: Float = 1.0,
        didStartPlaying: @escaping @Sendable () -> Void = {},
        didFinishPlaying: @escaping @Sendable () -> Void = {},
        didUpdateBuffer: @escaping @Sendable (CMSampleBuffer) -> Void = { _ in }
    ) {
        self.timeUpdateInterval = timeUpdateInterval
        self.initialVolume = initialVolume
        self.didStartPlaying = didStartPlaying
        self.didFinishPlaying = didFinishPlaying
        self.didUpdateBuffer = didUpdateBuffer
    }

    deinit {
        task?.cancel()
        synchronizer?.invalidate()
    }

    public func start(_ stream: AnyPublisher<Data, Error>, type: AudioFileTypeID? = nil) {
        start(stream.stream(), type: type)
    }

    public func start(_ stream: AsyncThrowingStream<Data, Error>, type: AudioFileTypeID? = nil) {
        stop()
        prepareSynchronizer(type: type)
        startReceivingData(from: stream)
    }

    public func stop() {
        cancelDataTask()
        cancelSynchronizer()
        setCurrentTime(.zero)
        setCurrentDuration(.zero)
        setCurrentRate(.zero)
        setCurrentError(nil)
        setCurrentState(.initial)
        setCurrentBuffer(nil)
    }

    public func pause() {
        synchronizer?.pause()
    }

    public func resume() {
        synchronizer?.resume()
    }

    public func rewind(_ time: CMTime) {
        synchronizer?.rewind(time)
    }

    public func forward(_ time: CMTime) {
        synchronizer?.forward(time)
    }

    public func seek(to time: CMTime) {
        synchronizer?.seek(to: time)
    }

    // MARK: - Private

    private func cancelDataTask() {
        task?.cancel()
        task = nil
    }

    private func startReceivingData(from stream: AsyncThrowingStream<Data, Error>) {
        cancelDataTask()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await data in stream {
                    synchronizer?.receive(data: data)
                }
                synchronizer?.finish()
            } catch {
                setCurrentError(AudioPlayerError(error: error))
            }
        }
    }

    private func cancelSynchronizer() {
        synchronizer?.invalidate()
        synchronizer = nil
    }

    // swiftlint:disable:next function_body_length
    private func prepareSynchronizer(type: AudioFileTypeID?) {
        synchronizer = AudioSynchronizer(
            timeUpdateInterval: timeUpdateInterval,
            initialVolume: initialVolume
        ) { [weak self] rate in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentRate(rate)
                }
            }
        } onTimeChanged: { [weak self] time in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentTime(time)
                }
            }
        } onDurationChanged: { [weak self] duration in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentDuration(duration)
                }
            }
        } onError: { [weak self] error in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentError(error)
                    if error != nil {
                        self?.didFinishPlaying()
                    }
                }
            }
        } onComplete: { [weak self] in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentState(.completed)
                    self?.didFinishPlaying()
                }
            }
        } onPlaying: { [weak self] in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentState(.playing)
                    self?.didStartPlaying()
                }
            }
        } onPaused: { [weak self] in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentState(.paused)
                }
            }
        } onSampleBufferChanged: { [weak self] buffer in
            Task {
                await MainActor.run { [weak self] in
                    self?.setCurrentBuffer(buffer)
                }
            }
        }
        synchronizer?.prepare(type: type)
    }

    private func setCurrentRate(_ rate: Float) {
        guard currentRate != rate else { return }
        currentRate = rate
    }

    private func setCurrentState(_ state: AudioPlayerState) {
        guard currentState != state else { return }
        currentState = state
    }

    private func setCurrentError(_ error: AudioPlayerError?) {
        currentError = error
        if error != nil { currentState = .failed }
    }

    private func setCurrentTime(_ time: CMTime) {
        guard currentTime != time else { return }
        currentTime = time
    }

    private func setCurrentDuration(_ duration: CMTime) {
        guard currentDuration != duration else { return }
        currentDuration = duration
    }

    private func setCurrentBuffer(_ buffer: CMSampleBuffer?) {
        currentBuffer = buffer
        buffer.flatMap(didUpdateBuffer)
    }
}
