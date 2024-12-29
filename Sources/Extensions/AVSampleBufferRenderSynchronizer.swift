import AVFoundation
@preconcurrency import Combine

extension AVSampleBufferRenderSynchronizer {
    func periodicTimeObserver(interval: CMTime, queue: DispatchQueue = .main) -> AnyPublisher<CMTime, Never> {
        let subject = PassthroughSubject<CMTime, Never>()
        let observer = addPeriodicTimeObserver(forInterval: interval, queue: queue) { subject.send($0) }

        return subject
            .handleEvents(receiveCancel: { [weak self] in self?.removeTimeObserver(observer) })
            .eraseToAnyPublisher()
    }
}
