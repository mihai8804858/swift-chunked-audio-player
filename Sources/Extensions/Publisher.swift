@preconcurrency import Combine

extension Publisher where Output: Sendable, Failure == Never {
    func stream() -> AsyncStream<Output> {
        var cancellable: AnyCancellable?

        return AsyncStream<Output> { continuation in
            cancellable = sink { _ in
                continuation.finish()
            } receiveValue: { output in
                continuation.yield(output)
            }
            continuation.onTermination = { [cancellable] _ in
                cancellable?.cancel()
            }
        }
    }
}

extension Publisher where Output: Sendable {
    func stream() -> AsyncThrowingStream<Output, Error> {
        var cancellable: AnyCancellable?

        return AsyncThrowingStream<Output, Error> { continuation in
            cancellable = sink { completion in
                switch completion {
                case .finished: continuation.finish()
                case .failure(let error): continuation.finish(throwing: error)
                }
            } receiveValue: { output in
                continuation.yield(output)
            }
            continuation.onTermination = { [cancellable] _ in
                cancellable?.cancel()
            }
        }
    }
}
