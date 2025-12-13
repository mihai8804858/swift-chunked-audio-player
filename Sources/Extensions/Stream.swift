import Foundation

extension AsyncThrowingStream where Failure == Error {
    init<S: AsyncSequence & Sendable>(_ sequence: S) where S.Element == Element {
        nonisolated(unsafe) var iterator: S.AsyncIterator?
        let lock = NSLock()
        self.init {
            lock.withLock {
                if iterator == nil {
                    iterator = sequence.makeAsyncIterator()
                }
            }
            return try await iterator?.next()
        }
    }
}

@available(iOS 18, tvOS 18, macOS 15, visionOS 2, *)
extension AsyncSequence where Self: Sendable, Failure == Error {
    func stream() -> AsyncThrowingStream<Element, Failure> {
        AsyncThrowingStream(self)
    }
}
