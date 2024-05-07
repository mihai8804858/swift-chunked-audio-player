import AudioToolbox
import Combine
import SwiftUI
import ChunkedAudioPlayer

struct LocalFileView: View {
    private let queue = DispatchQueue(label: "audio.player.read.queue")
    private let samplePath = Bundle.main.path(forResource: "sample", ofType: "mp3")!
    private let chunkSize = 4096

    @ObservedObject private var player = AudioPlayer()

    @State private var errorMessage: String?
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            pathLabel
            AudioControlsView(player: player) {
                switch player.state {
                case .initial, .failed, .completed: performConversion()
                case .playing: player.pause()
                case .paused: player.resume()
                }
            } onStop: {
                player.stop()
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .alert("Error", isPresented: $didFail) {
            Button("Retry") {
                errorMessage = nil
                didFail = false
                performConversion()
            }
            Button("Cancel") {
                errorMessage = nil
                didFail = false
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: player.error) { _, error in
            handleError(error)
            print("Error = \(error.flatMap { $0.debugDescription } ?? "nil")")
        }
        .onChange(of: player.currentTime) { _, time in
            print("Time = \(time.seconds)")
        }
        .onChange(of: player.state) { _, state in
            print("State = \(state)")
        }
        .onChange(of: player.rate) { _, rate in
            print("Rate = \(rate)")
        }
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Local File")
    }

    @ViewBuilder
    private var pathLabel: some View {
        Label {
            Text((samplePath as NSString).lastPathComponent)
        } icon: {
            Image(systemName: "speaker.wave.2.circle.fill")
        }
        .font(.title3)
        .fontDesign(.monospaced)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
    }

    private func performConversion() {
        player.start(makeSampleStream(), type: kAudioFileMP3Type)
    }

    private func makeSampleStream() -> AnyPublisher<Data, Error> {
        let subject = PassthroughSubject<Data, Error>()
        return subject
            .handleEvents(receiveSubscription: { _ in readFile(in: subject, on: queue) })
            .eraseToAnyPublisher()
    }

    private func readFile(in subject: PassthroughSubject<Data, Error>, on queue: DispatchQueue) {
        queue.async {
            guard let stream = InputStream(fileAtPath: samplePath) else {
                subject.send(completion: .finished)
                return
            }
            stream.open()
            defer {
                stream.close()
                subject.send(completion: .finished)
            }
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while case let amount = stream.read(&buffer, maxLength: chunkSize), amount > 0 {
                subject.send(Data(buffer[..<amount]))
            }
        }
    }

    private func handleError(_ error: AudioPlayerError?) {
        if let error {
            errorMessage = String(describing: error)
            didFail = true
        } else {
            errorMessage = nil
            didFail = false
        }
    }
}

#Preview {
    LocalFileView()
}
