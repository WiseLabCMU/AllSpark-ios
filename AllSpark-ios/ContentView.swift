import SwiftUI

struct ContentView: View {

    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            CameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
        }
    }
}

#Preview {
    ContentView()
}
