import SwiftUI
import Network

struct SettingsView: View {
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @ObservedObject private var commsManager = CommunicationsManager.shared
    @AppStorage("serverHost") private var serverHost: String = ""
    @AppStorage("verifyCertificate") private var verifyCertificate: Bool = true
    @AppStorage("deviceName") private var deviceName: String = ""
    @AppStorage("privacyMode") private var privacyMode: String = "segmentation"
    @State private var displayText: String = "Awaiting remote configuration from server..."
    @State private var selectedEndpoint: NWEndpoint?
    @State private var showingInterfaces: Bool = false
    @State private var showingScanner: Bool = false

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
                .padding(.top, AppConstants.UI.paddingStandard)
                .padding(.bottom, AppConstants.UI.paddingSmall)

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

                    if !connectionManager.ipAddresses.isEmpty {
                        HStack {
                            Text("Device Interfaces")
                            Spacer()
                            Button("Interfaces") {
                                showingInterfaces = true
                            }
                        }
                    }

                    HStack {
                        Text("Permissions")
                        Spacer()
                        Button("Edit Permissions") {
                            openAppSettings()
                        }
                    }
                }

                Section(header: Text("Server & Connection")) {
                    HStack {
                        if connectionManager.isConnected {
                            Text("Server Host ") +
                            Text("(Connected)")
                                .foregroundColor(AppConstants.Colors.statusConnected)
                            if connectionManager.isSecureProtocol {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(AppConstants.Colors.statusConnected)
                            }
                        } else if connectionManager.isAttemptingConnection {
                            Text("Server Host ") +
                            Text("(Connecting...)")
                                .foregroundColor(AppConstants.Colors.statusConnecting)
                        } else {
                            Text("Server Host ") +
                            Text("(Disconnected)")
                                .foregroundColor(AppConstants.Colors.statusDisconnected)
                        }
                        Spacer()
                        TextField("Server Host", text: Binding(
                            get: { self.serverHost },
                            set: { self.serverHost = $0.lowercased() }
                        ))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }

                    if !connectionManager.discoveredServers.isEmpty {
                        Picker("Servers Discovered", selection: $selectedEndpoint) {
                             ForEach(connectionManager.discoveredServers, id: \.endpoint) { result in
                                 if case .service(name: let name, type: _, domain: _, interface: _) = result.endpoint {
                                     Text(name).tag(Optional(result.endpoint))
                                 } else {
                                     Text("Unknown").tag(Optional(result.endpoint))
                                 }
                             }
                         }
                         .pickerStyle(.menu)
                         .onChange(of: selectedEndpoint) { _, newEndpoint in
                              if let endpoint = newEndpoint,
                                 let result = connectionManager.discoveredServers.first(where: { $0.endpoint == endpoint }) {
                                  connectionManager.connectToDiscoveredServer(result)
                              }
                         }
                         .onReceive(connectionManager.$discoveredServers) { servers in
                             if selectedEndpoint == nil, let first = servers.first {
                                 selectedEndpoint = first.endpoint
                             }
                         }
                    } else {
                        Button(action: {
                            showingScanner = true
                        }) {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                Text("Scan Server QR Code")
                            }
                        }
                    }

                    Toggle("Verify SSL Certificate", isOn: $verifyCertificate)

                    HStack {
                        Text("WebSocket")
                        Spacer()
                        Button(action: {
                            if connectionManager.isConnected {
                                connectionManager.disconnect()
                            } else {
                                connectionManager.connect()
                            }
                        }) {
                            Text(connectionManager.isConnected ? "Disconnect" : "Connect")
                                .foregroundColor(connectionManager.isConnected ? AppConstants.Colors.actionToggleOff : AppConstants.Colors.actionToggleOn)
                        }
                    }

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

                Section(header: Text("Privacy Filter Mode")) {
                    Picker("Mode", selection: $privacyMode) {
                        Text("Person Segmentation (Default)").tag("segmentation")
                        Text("Body Pose Detection (Limbs)").tag("pose")
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
            .frame(maxHeight: AppConstants.UI.viewMaxHeightMedium)
            .background(AppConstants.Colors.backgroundSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppConstants.Colors.backgroundGrouped)
        .onReceive(connectionManager.$clientConfig) { config in
            if let config = config,
               let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                displayText = "Received Client Config:\n\(jsonString)"
            }
        }
        .sheet(isPresented: $showingInterfaces) {
            NavigationView {
                List {
                    ForEach(connectionManager.ipAddresses.sorted(by: { $0.key < $1.key }), id: \.key) { interface, ip in
                        HStack {
                            Text(interface)
                            Spacer()
                            Text(ip)
                                .foregroundColor(AppConstants.Colors.textSecondary)
                        }
                    }
                }
                .navigationTitle("Device Interfaces")
                .toolbar {
                    Button("Done") {
                        showingInterfaces = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            PairingView(serverHost: $serverHost)
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
