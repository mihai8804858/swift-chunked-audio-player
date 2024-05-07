import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                SpeechToTextView()
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
