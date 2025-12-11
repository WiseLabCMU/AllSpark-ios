import SwiftUI
import SwiftyPing

struct SettingsView: View {
    @AppStorage("serverHost") private var serverHost: String = "localhost:3000"
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

            Spacer()

            Text(displayText)
                 .font(.title)
                 .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.2))
    }

}

#Preview {
    SettingsView()
}
