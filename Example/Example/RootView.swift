import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TextToSpeechView()
            }.tabItem {
                Label("Remote", systemImage: "network")
            }
            NavigationStack {
                LocalFileView()
            }.tabItem {
                Label("Local", systemImage: "doc")
            }
        }
    }
}
