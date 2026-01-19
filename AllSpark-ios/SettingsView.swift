import SwiftUI
import SwiftyPing

struct SettingsView: View {
    @AppStorage("serverHost") private var serverHost: String = "localhost:8080"
    @AppStorage("videoFormat") private var videoFormat: String = "mp4"
    @State private var displayText: String = "Ready."

    var body: some View {
        VStack(alignment: .center) {
            Text("AllSpark Network")
                .font(.largeTitle)
                .padding(.top, 20)

            Spacer()

            Text("Upload Server Host")
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

            Button(action: {
                displayText = "pinging \(serverHost)..."
                // Ping once
                let once = try? SwiftyPing(host: serverHost, configuration: PingConfiguration(interval: 0.5, with: 5), queue: DispatchQueue.global())
                once?.observer = { (response) in
                    let duration = response.duration
                    let byteCount = response.byteCount
                    // let identifier = response.identifier
                    // let sequenceNumber = response.sequenceNumber
                    // let trueSequenceNumber = response.trueSequenceNumber
                    let error = response.error?.localizedDescription

                    displayText += "\nduration: \(String(format: "%.0f", duration * 1000))ms"
                    if (byteCount != nil){
                        displayText += "\nresponse bytes: \(byteCount ?? 0)"
                    }
                    displayText += "\nerror: \(error ?? "None")"
                }
                once?.targetCount = 1
                try? once?.startPinging()

            }) {
                Text("Ping Once")
            }
            .padding()

            Button(action: {
                testHTTPConnection()
            }) {
                Text("Test HTTP Connection")
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
        displayText = "Testing HTTP connection to \(serverHost)..."

        var hostString = serverHost
        // Ensure it has http:// prefix
        if !hostString.lowercased().hasPrefix("http://") && !hostString.lowercased().hasPrefix("https://") {
            hostString = "http://" + hostString
        }

        guard let url = URL(string: hostString + "/api/health") else {
            displayText = "Invalid URL: \(hostString)"
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    displayText = "HTTP Connection Failed\nError: \(error.localizedDescription)"
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let status = json["status"] as? String ?? "unknown"
                            let timestamp = json["timestamp"] as? String ?? "unknown"
                            let uptime = json["uptime"] as? Double ?? 0

                            displayText = "✓ HTTP Connection Successful\nStatus: \(status)\nUptime: \(String(format: "%.1f", uptime))s\nTimestamp: \(timestamp)"
                        } else {
                            displayText = "✓ Server responded (200)\nBut could not parse response"
                        }
                    } else {
                        displayText = "HTTP Error\nStatus Code: \(httpResponse.statusCode)"
                    }
                } else {
                    displayText = "Unexpected response type"
                }
            }
        }
        task.resume()
    }
}

#Preview {
    SettingsView()
}
