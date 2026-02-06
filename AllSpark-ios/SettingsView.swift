import SwiftUI

struct SettingsView: View {
    @AppStorage("serverHost") private var serverHost: String = "localhost:8080"
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @AppStorage("videoFormat") private var videoFormat: String = "mp4"
    @AppStorage("verifyCertificate") private var verifyCertificate: Bool = true
    @AppStorage("deviceName") private var deviceName: String = ""
    @State private var displayText: String = "Ready to test."

    init() {
        // Set default deviceName from UIDevice if not already set
        let defaultName = UIDevice.current.name
        if UserDefaults.standard.string(forKey: "deviceName") == nil {
            UserDefaults.standard.set(defaultName, forKey: "deviceName")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Client Settings")
                .font(.largeTitle)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Form {
                Section(header: Text("Device")) {
                    HStack {
                        Text("Device Name")
                        Spacer()
                        TextField("Device Name", text: $deviceName)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.words)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section(header: Text("Server")) {
                    HStack {
                        Text("Server Host")
                        Spacer()
                        TextField("Server Host", text: $serverHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                    }

                    Toggle("Verify SSL Certificate", isOn: $verifyCertificate)
                }

                Section(header: Text("Actions")) {
                    HStack {
                        if connectionManager.isConnected {
                            Text("WebSocket ") +
                            Text("(Connected)")
                                .foregroundColor(.green)
                            if connectionManager.isSecureProtocol {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.green)
                            }
                        } else if connectionManager.isAttemptingConnection {
                            Text("WebSocket ") +
                            Text("(Connecting...)")
                                .foregroundColor(.orange)
                        } else {
                            Text("WebSocket ") +
                            Text("(Disconnected)")
                                .foregroundColor(.red)
                        }
                        Spacer()
                        Button(action: {
                            if connectionManager.isConnected {
                                connectionManager.disconnect()
                            } else {
                                connectionManager.connect()
                            }
                        }) {
                            Text(connectionManager.isConnected ? "Disconnect" : "Connect")
                                .foregroundColor(connectionManager.isConnected ? .red : .blue)
                        }
                    }

                    HStack {
                        Text("Permissions: Local Network, Camera, Microphone")
                        Spacer()
                        Button("Edit Permissions") {
                            openAppSettings()
                        }
                    }
                }


            }

            Divider()

            ScrollView {
                Text(displayText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .onReceive(connectionManager.$clientConfig) { config in
            if let config = config,
               let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                displayText = "Received Client Config:\n\(jsonString)"
            }
        }
    }



    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

#Preview {
    SettingsView()
}
