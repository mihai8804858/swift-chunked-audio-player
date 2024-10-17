import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
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
            } else {
                NavigationView {
                    TextToSpeechView()
                }.tabItem {
                    Label("Remote", systemImage: "network")
                }
                NavigationView {
                    LocalFileView()
                }.tabItem {
                    Label("Local", systemImage: "doc")
                }
            }
        }
    }
}
