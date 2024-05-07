import SwiftUI
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

struct SpeechToTextView: View {
    private let api = OpenAI()

    @FocusState private var isFocused: Bool
    @AppStorage("apiKey") private var apiKey: String = ""
    @ObservedObject private var player = AudioPlayer()

    @State private var format = SpeechFormat.mp3
    @State private var voice = SpeechVoice.alloy
    @State private var model = SpeechModel.tts1
    @State private var inputKey = false
    @State private var errorMessage: String?
    @State private var didFail = false
    @State private var attempts = 0
    @State private var text = ""

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            inputTextField
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
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
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
    SpeechToTextView()
}
