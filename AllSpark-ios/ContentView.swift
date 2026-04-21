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
            AppConstants.Colors.backgroundBase.opacity(AppConstants.UI.overlayOpacityDark)
                .ignoresSafeArea()

            VStack(spacing: AppConstants.UI.spacingLarge) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: AppConstants.UI.fontSizeGateIcon))
                    .foregroundColor(AppConstants.Colors.statusWarning)

                Text("Communications Check Required")
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.textPrimary)

                Text("Please resolve the following before continuing:")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.textSecondary)

                VStack(alignment: .leading, spacing: AppConstants.UI.spacingMedium) {
                    ForEach(commsManager.gateViolations, id: \.self) { violation in
                        HStack(alignment: .top, spacing: AppConstants.UI.spacingSmall) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppConstants.Colors.statusError)
                            Text(violation)
                                .foregroundColor(AppConstants.Colors.textPrimary)
                                .font(.body)
                        }
                    }
                }
                .padding()
                .background(AppConstants.Colors.overlayBaseLight.opacity(AppConstants.UI.overlayOpacityFaint))
                .cornerRadius(AppConstants.UI.cornerRadiusMedium)

                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppConstants.Colors.buttonPrimary)
                        .foregroundColor(AppConstants.Colors.textPrimary)
                        .cornerRadius(AppConstants.UI.cornerRadiusStandard)
                }
            }
            .padding(AppConstants.UI.paddingHeader)
        }
    }
}

#Preview {
    ContentView()
}
