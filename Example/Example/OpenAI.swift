import Foundation
import AudioToolbox

enum SpeechFormat: String, Encodable, CaseIterable {
    case mp3
    case aac

    var fileType: AudioFileTypeID {
        switch self {
        case .mp3: kAudioFileMP3Type
        case .aac: kAudioFileAAC_ADTSType
        }
    }
}

enum SpeechVoice: String, Encodable, CaseIterable {
    case alloy
    case echo
    case fable
    case onyx
    case nova
    case shimmer
}

enum SpeechModel: String, Encodable, CaseIterable {
    case tts1 = "tts-1"
    case tts1HD = "tts-1-hd"
}

struct TextToSpeechParameters: Equatable, Encodable {
    let apiKey: String
    let model: SpeechModel
    let voice: SpeechVoice
    let format: SpeechFormat
    let stream: Bool
    let input: String

    enum CodingKeys: String, CodingKey {
        case model
        case voice
        case format = "response_format"
        case stream
        case input
    }
}

final class OpenAI {
    private var inProgressDataStreams: Set<ChunkedDataStream> = []

    func textToSpeech(parameters: TextToSpeechParameters) -> AsyncThrowingStream<Data, Error> {
        chunkedStream(request: speechRequest(parameters: parameters))
    }
}

private extension OpenAI {
    func chunkedStream(request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream<Data, Error> { continuation in
            let stream = ChunkedDataStream(request: request, continuation: continuation)
            inProgressDataStreams.insert(stream)
            stream.onComplete { [weak self] in self?.inProgressDataStreams.remove(stream) }
            stream.resume()
        }
    }

    func speechRequest(parameters: TextToSpeechParameters) -> URLRequest {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let body = try? encoder.encode(parameters)
        let headers = [
            "Content-Type": "application/json",
            "Content-Length": String(body?.count ?? 0),
            "Authorization": "Bearer \(parameters.apiKey)"
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = body

        return request
    }
}

private final class ChunkedDataStream: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var response: URLResponse?
    private var onComplete: (() -> Void)?
    private let request: URLRequest
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(request: URLRequest, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.request = request
        self.continuation = continuation
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.continuation.onTermination = { [weak self] _ in self?.cancel() }
    }

    func resume() {
        session?.dataTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
    }

    func onComplete(_ action: @escaping () -> Void) {
        onComplete = action
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.finish(throwing: error)
        onComplete?()
    }
}
