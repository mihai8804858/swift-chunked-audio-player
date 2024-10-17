import SwiftUI
import ChunkedAudioPlayer

struct AudioControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .font(.system(size: 20))
            .frame(width: 48, height: 48)
            .foregroundStyle(.primary.opacity(isEnabled ? 1.0 : 0.3))
    }
}

struct AudioControlButton: View {
    let image: () -> Image
    let onTap: () -> Void

    init(image: @escaping () -> Image, onTap: @escaping () -> Void) {
        self.image = image
        self.onTap = onTap
    }

    init(image: Image, onTap: @escaping () -> Void) {
        self.init(image: { image }, onTap: onTap)
    }

    var body: some View {
        Button {
            withAnimation {
                onTap()
            }
        } label: {
            if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
                image()
                    .contentTransition(.symbolEffect(.replace))
            } else {
                image()
            }
        }
        .buttonStyle(AudioControlButtonStyle())
    }
}

struct AudioControlsView: View {
    @StateObject var player: AudioPlayer
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onRewind: () -> Void
    let onForward: () -> Void

    private var currentTime: TimeInterval {
        player.currentTime.seconds
    }

    private var currentDuration: TimeInterval {
        player.currentDuration.seconds
    }

    private var formattedTime: String {
        if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
            let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2))
            let formattedCurrentTime = Duration.seconds(currentTime).formatted(format)
            let formattedCurrentDuration = Duration.seconds(currentDuration).formatted(format)
            return formattedCurrentTime + " / " + formattedCurrentDuration
        } else {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.zeroFormattingBehavior = .pad
            let formattedCurrentTime = formatter.string(from: currentTime)!
            let formattedCurrentDuration = formatter.string(for: currentDuration)!
            return formattedCurrentTime + " / " + formattedCurrentDuration
        }
    }

    #if os(macOS)
    private let backgroundColor = Color(NSColor.scrubberTexturedBackground)
    #else
    private let backgroundColor = Color(UIColor.secondarySystemBackground)
    #endif

    var body: some View {
        HStack {
            AudioControlButton(image: Image(systemName: "gobackward.5"), onTap: onRewind)
                .disabled(!player.currentState.isActive)
            AudioControlButton(image: {
                switch player.currentState {
                case .initial, .failed, .completed, .paused: Image(systemName: "play.fill")
                case .playing: Image(systemName: "pause.fill")
                }
            }, onTap: onPlayPause)
            Text(formattedTime)
                .padding()
                .font(.headline.monospaced().bold())
                .foregroundStyle(Color.primary.opacity(player.currentState.isActive ? 1.0 : 0.3))
            AudioControlButton(image: Image(systemName: "stop.fill"), onTap: onStop)
                .disabled(!player.currentState.isActive)
            AudioControlButton(image: Image(systemName: "goforward.5"), onTap: onForward)
                .disabled(!player.currentState.isActive)
        }
        .background(backgroundColor)
        .clipShape(Capsule())
    }
}

private extension AudioPlayerState {
    var isActive: Bool {
        switch self {
        case .playing, .paused: true
        case .initial, .completed, .failed: false
        }
    }
}

#Preview {
    AudioControlsView(
        player: AudioPlayer(),
        onPlayPause: {},
        onStop: {},
        onRewind: {},
        onForward: {}
    )
}
