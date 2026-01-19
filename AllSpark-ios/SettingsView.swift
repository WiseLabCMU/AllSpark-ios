import SwiftUI

struct SettingsView: View {
    @AppStorage("serverHost") private var serverHost: String = "localhost:8080"
    @AppStorage("videoFormat") private var videoFormat: String = "mp4"
    @AppStorage("verifyCertificate") private var verifyCertificate: Bool = true
    @State private var displayText: String = "Ready."

    var body: some View {
        VStack(alignment: .center) {
            Text("Client Settings")
                .font(.largeTitle)
                .padding(.top, 20)

            Spacer()

            Text("Video Format")
                .font(.headline)
                .padding(.top, 20)

            Picker("Video Format", selection: $videoFormat) {
                Text("MP4 (Default)").tag("mp4")
                Text("MOV").tag("mov")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .padding()

            Text("Server Host")
                .font(.headline)
                .padding(.top, 10)

            TextField("Server Host", text: $serverHost)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 300)
                .multilineTextAlignment(.center)
                .padding()
                .keyboardType(.URL)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)

            Toggle("Verify SSL Certificate", isOn: $verifyCertificate)
                .frame(maxWidth: 300)
                .padding()

            Button(action: {
                testHTTPConnection()
            }) {
                Text("Test HTTP Connection")
            }
            .padding()

            Button(action: {
                testWebSocketConnection()
            }) {
                Text("Test WS Connection")
            }
            .padding()

            Spacer()

            Text(displayText)
                .font(.title)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.2))
    }

    private func testHTTPConnection() {
        displayText = "Testing connection to \(serverHost)..."

        var hostString = serverHost
        // Strip any existing protocol
        if hostString.lowercased().hasPrefix("http://") {
            hostString = String(hostString.dropFirst(7))
        } else if hostString.lowercased().hasPrefix("https://") {
            hostString = String(hostString.dropFirst(8))
        }

        // Try HTTPS first
        testConnectionAttempt(host: hostString, useSecure: true) { success in
            if success {
                return
            }
            // If HTTPS failed, try HTTP
            self.testConnectionAttempt(host: hostString, useSecure: false) { _ in }
        }
    }

    private func testConnectionAttempt(host: String, useSecure: Bool, completion: @escaping (Bool) -> Void) {
        let scheme = useSecure ? "https" : "http"
        let hostString = scheme + "://" + host

        guard let url = URL(string: hostString + "/api/health") else {
            displayText = "Invalid URL: \(hostString)"
            completion(false)
            return
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 10.0

        if !verifyCertificate {
            config.urlCredentialStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
        }

        let delegate = CertificateVerificationDelegate(verifyCertificate: verifyCertificate)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    let nextScheme = useSecure ? "HTTP" : "failed"
                    self.displayText = "Testing \(scheme.uppercased()) failed. Trying \(nextScheme)...\nError: \(error.localizedDescription)"
                    completion(false)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let status = json["status"] as? String ?? "unknown"
                            let timestamp = json["timestamp"] as? String ?? "unknown"
                            let uptime = json["uptime"] as? Double ?? 0

                            self.displayText = "✓ Connection Successful via \(scheme.uppercased())\nStatus: \(status)\nUptime: \(String(format: "%.1f", uptime))s\nTimestamp: \(timestamp)"
                        } else {
                            self.displayText = "✓ Server responded (200) via \(scheme.uppercased())\nBut could not parse response"
                        }
                        completion(true)
                    } else {
                        self.displayText = "Testing \(scheme.uppercased()) failed\nStatus Code: \(httpResponse.statusCode)"
                        completion(false)
                    }
                } else {
                    self.displayText = "Unexpected response type"
                    completion(false)
                }
            }
        }
        task.resume()
    }

    private func testWebSocketConnection() {
        displayText = "Testing WebSocket connection to \(serverHost)..."

        var hostString = serverHost
        // Strip any existing protocol
        if hostString.lowercased().hasPrefix("http://") {
            hostString = String(hostString.dropFirst(7))
        } else if hostString.lowercased().hasPrefix("https://") {
            hostString = String(hostString.dropFirst(8))
        } else if hostString.lowercased().hasPrefix("ws://") {
            hostString = String(hostString.dropFirst(5))
        } else if hostString.lowercased().hasPrefix("wss://") {
            hostString = String(hostString.dropFirst(6))
        }

        // Try WSS first
        testWebSocketAttempt(host: hostString, useSecure: true) { success in
            if success {
                return
            }
            // If WSS failed, try WS
            self.testWebSocketAttempt(host: hostString, useSecure: false) { _ in }
        }
    }

    private func testWebSocketAttempt(host: String, useSecure: Bool, completion: @escaping (Bool) -> Void) {
        let scheme = useSecure ? "wss" : "ws"
        let urlString = scheme + "://" + host

        guard let url = URL(string: urlString) else {
            displayText = "Invalid WebSocket URL: \(urlString)"
            completion(false)
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 10.0

        if !verifyCertificate {
            config.urlCredentialStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
        }

        let delegate = CertificateVerificationDelegate(verifyCertificate: verifyCertificate)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: url)

        task.resume()

        // Try to send a test message to verify connection works
        var connectionVerified = false
        let testMessage = URLSessionWebSocketTask.Message.string("{\"type\": \"test\"}")

        task.send(testMessage) { [weak task] error in
            if let error = error {
                DispatchQueue.main.async {
                    let nextScheme = useSecure ? "WS" : "failed"
                    self.displayText = "Testing \(scheme.uppercased()) failed. Trying \(nextScheme)...\nError: \(error.localizedDescription)"
                }
                completion(false)
                task?.cancel(with: .goingAway, reason: nil)
            } else {
                // Message sent successfully, connection is working
                connectionVerified = true
                DispatchQueue.main.async {
                    self.displayText = "✓ WebSocket Connection Successful via \(scheme.uppercased())"
                }
                completion(true)
                task?.cancel(with: .goingAway, reason: nil)
            }
        }

        // Timeout after 5 seconds if no response
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if !connectionVerified {
                let nextScheme = useSecure ? "WS" : "failed"
                DispatchQueue.main.async {
                    self.displayText = "Testing \(scheme.uppercased()) timed out. Trying \(nextScheme)..."
                }
                completion(false)
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
