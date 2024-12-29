import Foundation

public enum AudioPlayerError: Error, Equatable, CustomDebugStringConvertible, Sendable {
    public static func == (lhs: AudioPlayerError, rhs: AudioPlayerError) -> Bool {
        switch (lhs, rhs) {
        case (.status(let lhsStatus), .status(let rhsStatus)):
            return lhsStatus == rhsStatus
        case (.other(let lhsError), .other(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }

    case streamNotOpened
    case status(OSStatus)
    case other(Error)

    public var debugDescription: String {
        switch self {
        case .status(let status): "OSStatus \(status)"
        case .streamNotOpened: "Audio file stream not opened"
        case .other(let error): error.localizedDescription
        }
    }

    public init(error: Error) {
        if let playerError = error as? AudioPlayerError {
            self = playerError
        }

        self = .other(error)
    }
}
