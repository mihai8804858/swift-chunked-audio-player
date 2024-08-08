import Foundation
import Combine
import AVFoundation
import AudioToolbox

public final class AudioPlayer: ObservableObject {
    private let timeUpdateInterval: CMTime
    private var task: Task<Void, Never>?
    private var synchronizer: AudioSynchronizer?
    private let didStartPlaying: @Sendable () -> Void
    private let didFinishPlaying: @Sendable () -> Void

    @Published public private(set) var currentError: AudioPlayerError?
    @Published public private(set) var currentState = AudioPlayerState.initial
    @Published public private(set) var currentRate = Float.zero
    @Published public private(set) var currentTime = CMTime.zero
    @Published public private(set) var currentDuration = CMTime.zero
    @Published public private(set) var currentBuffer: CMSampleBuffer?

    public var volume: Float {
        get { synchronizer?.volume ?? 0 }
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
      didStartPlaying: @escaping @Sendable () -> Void = {},
      didFinishPlaying: @escaping @Sendable () -> Void = {}
    ) {
        self.timeUpdateInterval = timeUpdateInterval
        self.didStartPlaying = didStartPlaying
        self.didFinishPlaying = didFinishPlaying
    }

    deinit {
        stop()
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

    private func prepareSynchronizer(type: AudioFileTypeID?) {
        synchronizer = AudioSynchronizer(timeUpdateInterval: timeUpdateInterval) { [weak self] rate in
            self?.setCurrentRate(rate)
        } onTimeChanged: { [weak self] time in
            self?.setCurrentTime(time)
        } onDurationChanged: { [weak self] duration in
            self?.setCurrentDuration(duration)
        } onError: { [weak self] error in
            self?.setCurrentError(error)
            if error != nil {
              self?.didFinishPlaying()
            }
        } onComplete: { [weak self] in
            self?.setCurrentState(.completed)
            self?.didFinishPlaying()
        } onPlaying: { [weak self] in
            self?.setCurrentState(.playing)
            self?.didStartPlaying()
        } onPaused: { [weak self] in
            self?.setCurrentState(.paused)
        } onSampleBufferChanged: { [weak self] buffer in
            self?.setCurrentBuffer(buffer)
        }
        synchronizer?.prepare(type: type)
    }

    private func setCurrentRate(_ rate: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self, currentRate != rate else { return }
            currentRate = rate
        }
    }

    private func setCurrentState(_ state: AudioPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, currentState != state else { return }
            currentState = state
        }
    }

    private func setCurrentError(_ error: AudioPlayerError?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            currentError = error
            if error != nil { currentState = .failed }
        }
    }

    private func setCurrentTime(_ time: CMTime) {
        DispatchQueue.main.async { [weak self] in
            guard let self, currentTime != time else { return }
            currentTime = time
        }
    }

    private func setCurrentDuration(_ duration: CMTime) {
        DispatchQueue.main.async { [weak self] in
            guard let self, currentDuration != duration else { return }
            currentDuration = duration
        }
    }

    private func setCurrentBuffer(_ buffer: CMSampleBuffer?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            currentBuffer = buffer
        }
    }
}
