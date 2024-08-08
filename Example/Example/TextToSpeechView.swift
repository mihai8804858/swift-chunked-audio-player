import SwiftUI
import CoreMedia
import ChunkedAudioPlayer

struct Shake: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translationX = amount * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: translationX, y: 0))
    }
}

struct TextToSpeechView: View {
    private let api = OpenAI()

    @AppStorage("apiKey") private var apiKey: String = ""
    @FocusState private var isFocused: Bool
    @StateObject private var player = AudioPlayer()

    @State private var format = SpeechFormat.mp3
    @State private var voice = SpeechVoice.alloy
    @State private var model = SpeechModel.tts1
    @State private var inputKey = false
    @State private var errorMessage: String?
    @State private var didFail = false
    @State private var attempts = 0
    @State private var text = ""

    private var volumeBinding: Binding<Float> {
        Binding<Float> {
            player.volume
        } set: { volume in
            player.volume = volume
        }
    }

    private var rateBinding: Binding<Float> {
        Binding<Float> {
            player.rate
        } set: { rate in
            player.rate = rate
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            inputTextField
            controlsView
            volumeView
            rateView
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
        .alert("OpenAI API Key", isPresented: $inputKey) {
            SecureField("API Key", text: $apiKey)
            Button("OK") {}
        } message: {
            Text("Please enter your OpenAI API key")
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                apiKeyButton
            }
            ToolbarItem(placement: .navigation) {
                settingsMenu
                    #if !os(macOS)
                    .menuActionDismissBehavior(.disabled)
                    #endif
            }
        }
        .onChange(of: player.currentError) { _, error in
            handleError(error)
            print("Error = \(error.flatMap { $0.debugDescription } ?? "nil")")
        }
        .onChange(of: player.currentTime) { _, time in
            print("Time = \(time.seconds)")
        }
        .onChange(of: player.currentDuration) { _, duration in
            print("Duration = \(duration.seconds)")
        }
        .onChange(of: player.currentRate) { _, rate in
            print("Rate = \(rate)")
        }
        .onChange(of: player.currentState) { _, state in
            print("State = \(state)")
        }
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("OpenAI Text-to-Speech")
    }

    @ViewBuilder
    private var inputTextField: some View {
        TextField("Enter your input", text: $text, axis: .vertical)
            .focused($isFocused, equals: true)
            .font(.title3)
            .fontDesign(.monospaced)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .submitLabel(.return)
            .autocorrectionDisabled()
            .modifier(Shake(animatableData: CGFloat(attempts)))
    }

    @ViewBuilder
    private var controlsView: some View {
        AudioControlsView(player: player) {
            switch player.currentState {
            case .initial, .failed, .completed: performConversion()
            case .playing: player.pause()
            case .paused: player.resume()
            }
        } onStop: {
            player.stop()
        } onRewind: {
            player.rewind(CMTime(seconds: 5.0, preferredTimescale: player.currentTime.timescale))
        } onForward: {
            player.forward(CMTime(seconds: 5.0, preferredTimescale: player.currentTime.timescale))
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

    @ViewBuilder
    private var rateView: some View {
        VStack {
            Text("Rate: \(player.rate.formatted(.number.precision(.fractionLength(2))))")
            Slider(value: rateBinding, in: 0...1, step: 0.01)
        }
        .frame(maxWidth: 200)
    }

    @ViewBuilder
    private var settingsMenu: some View {
        Menu {
            Menu {
                Picker("Format", selection: $format) {
                    ForEach(SpeechFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).id(format)
                    }
                }
            } label: {
                Text("Format")
                Text(format.rawValue)
            }
            Menu {
                Picker("Voice", selection: $voice) {
                    ForEach(SpeechVoice.allCases, id: \.self) { voice in
                        Text(voice.rawValue).id(voice)
                    }
                }
            } label: {
                Text("Voice")
                Text(voice.rawValue)
            }
            Menu {
                Picker("Model", selection: $model) {
                    ForEach(SpeechModel.allCases, id: \.self) { model in
                        Text(model.rawValue).id(model)
                    }
                }
            } label: {
                Text("Model")
                Text(model.rawValue)
            }
        } label: {
            Image(systemName: "gear")
        }
        .tint(.primary)
    }

    @ViewBuilder
    private var apiKeyButton: some View {
        Button {
            inputKey = true
        } label: {
            Image(systemName: "key")
        }
        .tint(.primary)
    }

    private func performConversion() {
        isFocused = false
        if text.isEmpty {
            generateFeedback()
            withAnimation(.default) { attempts += 1 }
        } else if apiKey.isEmpty {
            generateFeedback()
            inputKey = true
        } else {
            player.start(api.textToSpeech(parameters: makeParameters()), type: format.fileType)
        }
    }

    private func makeParameters() -> TextToSpeechParameters {
        TextToSpeechParameters(
            apiKey: apiKey,
            model: model,
            voice: voice,
            format: format,
            stream: true,
            input: text
        )
    }

    private func generateFeedback() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
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
    TextToSpeechView()
}
