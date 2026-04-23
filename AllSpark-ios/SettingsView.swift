import SwiftUI
import Network

struct SettingsView: View {
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @ObservedObject private var commsManager = CommunicationsManager.shared
    @AppStorage("serverHost") private var serverHost: String = ""
    @AppStorage("verifyCertificate") private var verifyCertificate: Bool = true
    @AppStorage("deviceName") private var deviceName: String = ""
    @AppStorage("privacyMode") private var privacyMode: String = "segmentation"
    @State private var selectedEndpoint: NWEndpoint?
    @State private var showingScanner: Bool = false
    @State private var showingStatusInfo: Bool = false

    init() {
        // Set default deviceName from UIDevice if not already set
        let defaultName = UIDevice.current.name
        if UserDefaults.standard.string(forKey: "deviceName") == nil {
            UserDefaults.standard.set(defaultName, forKey: "deviceName")
        } 
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Client Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                ConnectionStatusButton()
                
                Button(action: {
                    showingStatusInfo = true
                }) {
                    Image(systemName: "info")
                        .font(.system(size: AppConstants.UI.iconSizeSecure, weight: .bold))
                        .foregroundColor(AppConstants.Colors.buttonInfo)
                        .frame(width: AppConstants.UI.buttonSizeMedium, height: AppConstants.UI.buttonSizeMedium)
                        .background(Color(AppConstants.Colors.backgroundBaseUI).opacity(AppConstants.UI.buttonBackgroundAlpha))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, AppConstants.UI.paddingStandard)
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

                }

                Section(header: Text("Privacy Filter Mode")) {
                    Picker("Mode", selection: $privacyMode) {
                        Text("Person Segmentation (Default)").tag("segmentation")
                        Text("Body Pose Detection (Limbs)").tag("pose")
                        Text("No Privacy Filter").tag("none")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppConstants.Colors.backgroundGrouped)
        .sheet(isPresented: $showingScanner) {
            PairingView(serverHost: $serverHost)
        }
        .sheet(isPresented: $showingStatusInfo) {
            StatusInfoView()
        }
    }
}

#Preview {
    SettingsView()
}
