import AudioToolbox
import Combine
import SwiftUI
import ChunkedAudioPlayer

struct LocalFileView: View {
    private let queue = DispatchQueue(label: "audio.player.read.queue")
    private let samplePath = Bundle.main.path(forResource: "sample", ofType: "mp3")!
    private let chunkSize = 4096

    @StateObject private var player = AudioPlayer()

    @State private var errorMessage: String?
    @State private var didFail = false

    private var volumeBinding: Binding<Float> {
        Binding<Float> {
            player.volume
        } set: { volume in
            player.volume = volume
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            pathLabel
            controlsView
            volumeView
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

    @ViewBuilder
    private var controlsView: some View {
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

    @ViewBuilder
    private var volumeView: some View {
        VStack {
            Text("Volume: \(Int(player.volume * 100))")
            Slider(value: volumeBinding, in: 0...1, step: 0.01)
        }
        .frame(maxWidth: 200)
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
