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

    @Published public private(set) var error: AudioPlayerError?
    @Published public private(set) var state = AudioPlayerState.initial
    @Published public private(set) var rate = Float.zero
    @Published public private(set) var currentTime = CMTime.zero
    @Published public private(set) var currentBuffer: CMSampleBuffer?

    public var volume: Float {
        get { synchronizer?.volume ?? 0 }
        set { synchronizer?.volume = newValue }
    }

    public var isMuted: Bool {
        get { synchronizer?.isMuted ?? false }
        set { synchronizer?.isMuted = newValue }
    }

    public init(
      timeUpdateInterval: CMTime = CMTime(value: 1, timescale: 10),
      didStartPlaying: @escaping @Sendable () -> Void,
      didFinishPlaying: @escaping @Sendable () -> Void
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
        setTime(.zero)
        setRate(.zero)
        setError(nil)
        setState(.initial)
        setCurrentBuffer(nil)
    }

    public func pause() {
        synchronizer?.pause()
    }

    public func resume() {
        synchronizer?.resume()
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
                setError(AudioPlayerError(error: error))
            }
        }
    }

    private func cancelSynchronizer() {
        synchronizer?.invalidate()
        synchronizer = nil
    }

    private func prepareSynchronizer(type: AudioFileTypeID?) {
        synchronizer = AudioSynchronizer(timeUpdateInterval: timeUpdateInterval) { [weak self] rate in
            self?.setRate(rate)
        } onTimeChanged: { [weak self] time in
            self?.setTime(time)
        } onError: { [weak self] error in
            self?.setError(error)
        } onComplete: { [weak self] in
            self?.setState(.completed)
            self?.didFinishPlaying()
        } onPlaying: { [weak self] in
            self?.setState(.playing)
            self?.didStartPlaying()
        } onPaused: { [weak self] in
            self?.setState(.paused)
        } onSampleBufferChanged: { [weak self] buffer in
            self?.setCurrentBuffer(buffer)
        }
        synchronizer?.prepare(type: type)
    }

    private func setRate(_ rate: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.rate = rate
        }
    }

    private func setState(_ state: AudioPlayerState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = state
        }
    }

    private func setError(_ error: AudioPlayerError?) {
        DispatchQueue.main.async { [weak self] in
            self?.error = error
            if error != nil {
                self?.state = .failed
            }
        }
    }

    private func setTime(_ time: CMTime) {
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = time
        }
    }

    private func setCurrentBuffer(_ buffer: CMSampleBuffer?) {
        DispatchQueue.main.async { [weak self] in
            self?.currentBuffer = buffer
        }
    }
}
