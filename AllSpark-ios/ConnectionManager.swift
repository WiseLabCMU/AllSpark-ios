import Foundation
import UIKit
import Combine
import Network

extension Notification.Name {
    static let didReceiveRemoteCommand = Notification.Name("didReceiveRemoteCommand")
}

class ConnectionManager: NSObject, ObservableObject {
    static let shared = ConnectionManager()

    // Published properties for UI binding
    @Published var isConnected = false

    @Published var isAttemptingConnection = false
    @Published var isSecureProtocol = false
    @Published var clientConfig: [String: Any]?
    @Published var discoveredServers: [NWBrowser.Result] = []

    // Internal properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketURL: URL?

    private var connectionAttemptTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let uploadQueue = DispatchQueue(label: "com.allspark.uploadQueue")
    private var browser: NWBrowser?
    private var resolverConnection: NWConnection?
    private var isResolvingEndpoint = false

    private override init() {
        super.init()
        // Observe UserDefaults changes for host or certificate settings
        UserDefaults.standard.addObserver(self, forKeyPath: "serverHost", options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "verifyCertificate", options: .new, context: nil)

        // Initial connection attempt
        connect()
        startBrowsing()
    }

    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: "serverHost")
        UserDefaults.standard.removeObserver(self, forKeyPath: "verifyCertificate")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "serverHost" || keyPath == "verifyCertificate" {
            // Reconnect when settings change
            DispatchQueue.main.async { [weak self] in
                print("Settings changed, reconnecting...")
                self?.disconnect()
                self?.connect()
            }
        }
    }

    func connect() {
        guard !isConnected && !isAttemptingConnection else { return }

        var hostString = UserDefaults.standard.string(forKey: "serverHost") ?? ""

        guard !hostString.isEmpty else {
            print("No server host configured")
            return
        }

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

        guard let wsURLSecure = URL(string: "wss://" + hostString) else {
            print("Invalid WebSocket URL parameters: \(hostString)")
            return
        }

        self.webSocketURL = wsURLSecure
        connectWebSocket()
    }

    private func connectWebSocket() {
        guard let wsURL = webSocketURL else { return }

        DispatchQueue.main.async {
            self.isAttemptingConnection = true
            // Set secure protocol flag based on connection URL
            self.isSecureProtocol = wsURL.absoluteString.lowercased().hasPrefix("wss://")
        }

        let verifyCertificate = UserDefaults.standard.bool(forKey: "verifyCertificate")
        let config = URLSessionConfiguration.default
        let delegate = CertificateVerificationDelegate(verifyCertificate: verifyCertificate)
        let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = urlSession.webSocketTask(with: wsURL)

        self.webSocketTask = task
        task.resume()

        print("Connecting to WebSocket at \(wsURL)")

        sendClientInfo()

        // Start receiving messages
        receiveWebSocketMessage()
    }

    private func sendClientInfo() {
        guard let task = webSocketTask else { return }

        let clientName = getClientDisplayName()
        let clientInfo: [String: Any] = [
            "type": "clientInfo",
            "clientName": clientName
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: clientInfo, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            task.send(message) { [weak self] error in
                if let error = error {
                    print("Failed to send client info: \(error)")
                    DispatchQueue.main.async {
                        // Connection failed
                        if self?.isSecureProtocol == true {
                            self?.attemptWsFallback()
                        } else {
                            self?.isAttemptingConnection = false
                        }
                    }
                } else {
                    print("Client info sent: \(clientName)")
                    DispatchQueue.main.async {
                        self?.isConnected = true
                        self?.isAttemptingConnection = false
                        print("WebSocket connection established")
                    }
                }
            }
        }
    }

    private func attemptWsFallback() {
        guard let wsURL = webSocketURL else { return }
        guard isSecureProtocol else { return }

        var wsURLString = wsURL.absoluteString
        wsURLString = wsURLString.replacingOccurrences(of: "wss://", with: "ws://")

        guard let wsURLFallback = URL(string: wsURLString) else { return }

        disconnect(clearTask: true) // Clear valid task but keep intent to connect if possible? No, standard disconnect

        // Reset state for new attempt
        webSocketURL = wsURLFallback

        print("WSS failed, retrying with WS at \(wsURLFallback)")
        connectWebSocket()
    }

    func disconnect(clearTask: Bool = true) {
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
        }
        if clearTask {
            webSocketTask = nil
        }

        DispatchQueue.main.async {
            self.isConnected = false
            self.isAttemptingConnection = false
        }
        print("WebSocket disconnected")
    }

    private func getClientDisplayName() -> String {
        let deviceName = UIDevice.current.name
        let customDeviceName = UserDefaults.standard.string(forKey: "deviceName") ?? deviceName
        let customName = UserDefaults.standard.string(forKey: "clientDisplayName")

        if let customName = customName, !customName.isEmpty {
            return "\(customName) (\(customDeviceName))"
        } else {
            return customDeviceName
        }
    }

    private func receiveWebSocketMessage() {
        guard let webSocketTask = webSocketTask else { return }

        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleIncomingMessage(text)
                case .data(_):
                    print("Received binary data (ignored)")
                @unknown default:
                    break
                }
                // Continue loop
                self?.receiveWebSocketMessage()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    if self?.isConnected == true {
                        self?.handleServerDisconnection()
                    } else if self?.isSecureProtocol == true {
                        self?.attemptWsFallback()
                    } else {
                         self?.isAttemptingConnection = false
                    }
                }
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        // Broadcast message to listeners (e.g. CameraViewController)
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Broadcast message to listeners (e.g. CameraViewController)
            DispatchQueue.main.async {
                // Check if it's a client config message
                if let type = json["type"] as? String, type == "clientConfig",
                   let config = json["config"] as? [String: Any] {
                    self.clientConfig = config
                    print("Received client config: \(config)")

                    // Update UserDefaults if videoFormat is present
                    if let videoFormat = config["videoFormat"] as? String {
                        UserDefaults.standard.set(videoFormat, forKey: "videoFormat")
                    }
                    return
                }

                NotificationCenter.default.post(name: .didReceiveRemoteCommand, object: nil, userInfo: ["payload": json])
            }
        }
    }

    private func handleServerDisconnection() {
        disconnect()

        // Auto-reconnect after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            if self?.isConnected == false {
                print("Attempting auto-reconnect...")
                self?.connect()
            }
        }
    }

    // MARK: - Service Discovery

    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_allspark._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)

        browser.stateUpdateHandler = { newState in
            print("Browser state: \(newState)")
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.discoveredServers = Array(results)
                print("Discovered servers: \(results.count)")

                // Auto-connect if we found a server and aren't connected
                if let firstResult = results.first,
                   !self.isConnected,
                   !self.isResolvingEndpoint {
                    print("Auto-connecting to discovered server: \(firstResult.endpoint)")
                    self.connectToDiscoveredServer(firstResult)
                }
            }
        }

        browser.start(queue: DispatchQueue.main)
        self.browser = browser
    }

    func connectToDiscoveredServer(_ result: NWBrowser.Result) {
        guard !isResolvingEndpoint else { return }
        isResolvingEndpoint = true

        // Create a temporary connection to resolve the endpoint to a host/port
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        self.resolverConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = innerEndpoint {

                    let hostString: String
                    switch host {
                    case .ipv4(let ip): hostString = "\(ip)"
                    case .ipv6(let ip): hostString = "[\(ip)]"
                    case .name(let name, _): hostString = name
                    @unknown default: hostString = "unknown"
                    }

                    let portString = "\(port.rawValue)"
                    let serverAddress = "\(hostString):\(portString)"

                    DispatchQueue.main.async {
                        print("Resolved service to: \(serverAddress)")
                        if UserDefaults.standard.string(forKey: "serverHost") != serverAddress {
                            UserDefaults.standard.set(serverAddress, forKey: "serverHost")
                            // The observer on UserDefaults will automatically trigger a reconnection
                        } else if !self!.isConnected && !self!.isAttemptingConnection {
                            // If host matches but we aren't connected, trigger connection
                             self?.connect()
                        }

                        // Clean up resolver
                        self?.resolverConnection?.cancel()
                        self?.resolverConnection = nil
                        self?.isResolvingEndpoint = false
                    }
                }
            case .failed(let error):
                print("Failed to resolve service: \(error)")
                self?.resolverConnection?.cancel()
                self?.resolverConnection = nil
                self?.isResolvingEndpoint = false
            default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global())
    }

    // MARK: - Upload Logic

    func uploadVideo(at fileURL: URL, completion: ((Result<Void, Error>) -> Void)? = nil) {
        uploadQueue.async { [weak self] in
            guard let self = self, self.isConnected, let task = self.webSocketTask else {
                completion?(.failure(NSError(domain: "ConnectionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"])))
                return
            }

            let videoData: Data
            do {
                videoData = try Data(contentsOf: fileURL)
            } catch {
                completion?(.failure(error))
                return
            }

            let filename = fileURL.lastPathComponent
            let fileExtension = (filename as NSString).pathExtension.lowercased()
            let mimetype = fileExtension == "mp4" ? "video/mp4" : "video/quicktime"

            let metadata: [String: Any] = [
                "type": "upload",
                "filename": filename,
                "filesize": videoData.count,
                "mimetype": mimetype
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: []),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                completion?(.failure(NSError(domain: "ConnectionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create metadata"])))
                return
            }

            let metadataMessage = URLSessionWebSocketTask.Message.string(jsonString)
            let dataMessage = URLSessionWebSocketTask.Message.data(videoData)

            // Send messages back-to-back to ensure ordering on the socket
            task.send(metadataMessage) { error in
                if let error = error {
                    print("Error sending metadata: \(error)")
                }
            }

            task.send(dataMessage) { error in
                if let error = error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
        }
    }
}
