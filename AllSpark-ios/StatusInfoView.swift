import SwiftUI
import AVFoundation

struct StatusInfoView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @ObservedObject private var commsManager = CommunicationsManager.shared

    @State private var cameraPermission: String = "Unknown"
    @State private var micPermission: String = "Unknown"
    @State private var configText: String = "None"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Interfaces")) {
                    if connectionManager.ipAddresses.isEmpty {
                        Text("No active interfaces")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    } else {
                        ForEach(connectionManager.ipAddresses.sorted(by: { $0.key < $1.key }), id: \.key) { interface, ip in
                            HStack {
                                Text(interface)
                                Spacer()
                                Text(ip)
                                    .foregroundColor(AppConstants.Colors.textSecondary)
                            }
                        }
                    }
                }

                Section(header: Text("Permissions")) {
                    HStack {
                        Text("Camera")
                        Spacer()
                        Text(cameraPermission)
                            .foregroundColor(permissionColor(for: cameraPermission))
                    }
                    HStack {
                        Text("Microphone")
                        Spacer()
                        Text(micPermission)
                            .foregroundColor(permissionColor(for: micPermission))
                    }
                    Button("Open System Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section(header: Text("Transport")) {
                    HStack {
                        Text("Active Transport")
                        Spacer()
                        Text(commsManager.activeTransport.capitalized)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                    if let warning = commsManager.transportMismatchWarning {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppConstants.Colors.statusConnecting)
                            Text(warning)
                                .font(.footnote)
                                .foregroundColor(AppConstants.Colors.statusConnecting)
                        }
                    }
                }

                Section(header: Text("Received Client Config")) {
                    Text(configText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Status Info")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                checkPermissions()

                // Initialize config text if already available
                if let config = connectionManager.clientConfig,
                   let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    configText = jsonString
                }
            }
            .onReceive(connectionManager.$clientConfig) { config in
                if let config = config,
                   let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    configText = jsonString
                } else {
                    configText = "None"
                }
            }
        }
    }

    private func checkPermissions() {
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermission = statusString(for: camStatus)

        if #available(iOS 17.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            switch status {
            case .granted: micPermission = "Granted"
            case .denied: micPermission = "Denied"
            case .undetermined: micPermission = "Not Determined"
            @unknown default: micPermission = "Unknown"
            }
        } else {
            let status = AVAudioSession.sharedInstance().recordPermission
            switch status {
            case .granted: micPermission = "Granted"
            case .denied: micPermission = "Denied"
            case .undetermined: micPermission = "Not Determined"
            @unknown default: micPermission = "Unknown"
            }
        }
    }

    private func statusString(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    private func permissionColor(for statusString: String) -> Color {
        return statusString == "Granted" ? AppConstants.Colors.statusConnected : AppConstants.Colors.statusDisconnected
    }
}

#Preview {
    StatusInfoView()
}
