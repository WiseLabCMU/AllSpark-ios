import SwiftUI
import SwiftyPing

struct SettingsView: View {
    @State private var pingHost: String = "api.chatgpt.com"
    @State private var displayText: String = "Ready."

    var body: some View {
        VStack(alignment: .center) {
            Text("AllSpark Ping Test")
                 .font(.largeTitle)
                 .padding(.top, 20)

            Spacer()

            TextField("Enter text", text: $pingHost)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 300)
                .multilineTextAlignment(.center)
                .padding()
                .keyboardType(.URL)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)

            Button(action: {
                displayText = "pinging \(pingHost)..."
                // Ping once
                let once = try? SwiftyPing(host: pingHost, configuration: PingConfiguration(interval: 0.5, with: 5), queue: DispatchQueue.global())
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
            
            Spacer()

            Text(displayText)
                 .font(.title)
                 .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill the available space
        .background(Color.gray.opacity(0.2)) // Optional: Background color for visibility
    }
    
}

#Preview {
    SettingsView()
}
