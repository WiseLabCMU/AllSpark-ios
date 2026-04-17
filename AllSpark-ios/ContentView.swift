import SwiftUI

struct ContentView: View {
    @ObservedObject private var commsManager = CommunicationsManager.shared
    @ObservedObject private var connectionManager = ConnectionManager.shared

    var body: some View {
        ZStack {
            // NOTE: Settings tab intentionally appears first during beta.
            // Setup and pairing remain frequently accessed while the app is
            // under active development. Re-evaluate tab order post-beta.
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

            // Gate overlay — blocks interaction until violations are resolved
            if !commsManager.gateViolations.isEmpty {
                CommunicationsGateView()
            }
        }
        // Policy enforcement alerts — shown after server config is received
        .alert("Communications Policy", isPresented: Binding(
            get: { !commsManager.policyEnforcementAlerts.isEmpty },
            set: { if !$0 { commsManager.policyEnforcementAlerts = [] } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                commsManager.policyEnforcementAlerts = []
            }
            Button("Dismiss", role: .cancel) {
                commsManager.policyEnforcementAlerts = []
            }
        } message: {
            Text(commsManager.policyEnforcementAlerts.joined(separator: "\n\n"))
        }
    }
}

/// Full-screen blocking overlay shown when required radios are enabled.
struct CommunicationsGateView: View {
    @ObservedObject private var commsManager = CommunicationsManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.yellow)

                Text("Communications Check Required")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Please resolve the following before continuing:")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(commsManager.gateViolations, id: \.self) { violation in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(violation)
                                .foregroundColor(.white)
                                .font(.body)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(32)
        }
    }
}

#Preview {
    ContentView()
}
