import SwiftUI

struct ContentView: View {

    @State private var viewModel = ViewModel()

    var body: some View {
        TabView {
//            HomeView()
//                .tabItem {
//                    Label("Home", systemImage: "house")
//                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            CameraView(image: $viewModel.currentFrame)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
        }
    }
}

#Preview {
    ContentView()
}
