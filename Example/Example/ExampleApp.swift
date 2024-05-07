import SwiftUI
import AVFoundation

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear(perform: activateAudioSession)
        }
    }

    private func activateAudioSession() {
        #if !os(macOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
          print(error)
        }
        #endif
    }
}
