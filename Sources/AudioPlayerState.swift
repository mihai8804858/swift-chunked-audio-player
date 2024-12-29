public enum AudioPlayerState: Equatable, Sendable {
    case initial
    case playing
    case paused
    case completed
    case failed
}
