import SwiftUI

@main
struct AllSpark_iosApp: App {
    init() {
        print("Application directory: \(NSHomeDirectory())")
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
