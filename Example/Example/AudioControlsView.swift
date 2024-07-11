import SwiftUI
import ChunkedAudioPlayer

struct AudioButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .font(.system(size: 20))
            .frame(width: 48, height: 48)
            .foregroundStyle(.primary)
    }
}

struct AudioPlayPauseButton: View {
    let player: AudioPlayer
    let onTap: () -> Void

    var body: some View {
        Button {
            withAnimation {
                onTap()
            }
        } label: {
            image.contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(AudioButtonStyle())
    }

    private var image: Image {
        switch player.currentState {
        case .initial, .failed, .completed, .paused: Image(systemName: "play.fill")
        case .playing: Image(systemName: "pause.fill")
        }
    }
}

struct AudioStopButton: View {
    let player: AudioPlayer
    let onTap: () -> Void

    var body: some View {
        Button {
            withAnimation {
                onTap()
            }
        } label: {
            Image(systemName: "stop.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(AudioButtonStyle())
    }
}

struct AudioControlsView: View {
    let timeFormat = Duration.UnitsFormatStyle(
        allowedUnits: [.hours, .minutes, .seconds],
        width: .narrow
    )

    let player: AudioPlayer
    let onPlayPause: () -> Void
    let onStop: () -> Void

    var duration: Duration {
        Duration.seconds(player.currentTime.seconds)
    }

    var formattedTime: String {
        duration.formatted(timeFormat)
    }

    var body: some View {
        HStack {
            AudioPlayPauseButton(player: player, onTap: onPlayPause)
            Text(formattedTime)
                .padding()
                .font(.headline.monospaced())
                .fontWeight(.bold)
            switch player.currentState {
            case .initial, .completed, .failed:
                EmptyView()
            case .playing, .paused:
                AudioStopButton(player: player, onTap: onStop)
            }
        }
        .background(Color.gray)
        .clipShape(Capsule())
    }
}

#Preview {
    AudioControlsView(player: AudioPlayer(), onPlayPause: {}, onStop: {})
}
