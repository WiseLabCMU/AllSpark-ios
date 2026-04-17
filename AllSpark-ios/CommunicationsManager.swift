import Foundation
import Network
import CoreBluetooth
import Combine

/// Monitors device radio/transport state, enforces the server-provided
/// communications policy, and gates app interaction when required radios
/// (Bluetooth, AirDrop, NFC, UWB) are still enabled.
/// Note: Satellite (iPhone 14+) is a possible radio but is out of scope.
class CommunicationsManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let shared = CommunicationsManager()

    // MARK: - Published State

    /// Currently active network transport (e.g. "wifi", "cellular", "wiredEthernet")
    @Published var activeTransport: String = "unknown"

    /// True when Bluetooth hardware is powered on
    @Published var isBluetoothOn: Bool = false

    /// Non-empty list blocks app interaction; each entry is a human-readable violation
    @Published var gateViolations: [String] = []

    /// Set when the server policy disables the transport we're actually using
    @Published var transportMismatchWarning: String? = nil

    /// Protocol enforcement alerts pending user action (post-connection)
    @Published var policyEnforcementAlerts: [String] = []

    // MARK: - Internal

    private var pathMonitor: NWPathMonitor?
    private var bluetoothManager: CBCentralManager?
    private var communicationsPolicy: [String: Bool]? = nil
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        startPathMonitor()

        // Re-evaluate gate whenever transport or BT state changes
        $activeTransport
            .combineLatest($isBluetoothOn)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.evaluateGate()
                self?.evaluatePolicy()
            }
            .store(in: &cancellables)
    }

    deinit {
        pathMonitor?.cancel()
    }

    // MARK: - Transport Detection (NWPathMonitor)

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let transport: String
            if path.usesInterfaceType(.wifi) {
                transport = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                transport = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                transport = "ethernet"
            } else if path.usesInterfaceType(.other) {
                // "other" can include USB tethering adapters
                transport = "usb"
            } else {
                transport = "none"
            }
            DispatchQueue.main.async {
                if self?.activeTransport != transport {
                    self?.activeTransport = transport
                    print("Active transport changed: \(transport)")
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        self.pathMonitor = monitor
    }

    // MARK: - Bluetooth Detection (CoreBluetooth)

    private func startBluetoothMonitor() {
        // showPowerAlert: false — we don't want the system prompt, just the state
        if bluetoothManager == nil {
            bluetoothManager = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let btOn = central.state == .poweredOn
        DispatchQueue.main.async { [weak self] in
            self?.isBluetoothOn = btOn
            print("Bluetooth state: \(btOn ? "ON" : "OFF")")
        }
    }

    // MARK: - Gate Evaluation

    /// Update the list of violations that block app interaction.
    /// Gates on: (1) Bluetooth/AirDrop must be OFF, and (2) any protocol
    /// the server policy requires disabled must be confirmed off.
    private func evaluateGate() {
        var violations: [String] = []

        // Static gate: Bluetooth and AirDrop
        if isBluetoothOn {
            violations.append("Bluetooth is ON — please disable it in Settings > Bluetooth")
            violations.append("AirDrop may be active — please disable it in Settings > General > AirDrop")
        }

        // NFC on iOS is session-based; include advisory text only
        // (no runtime check needed — NFC is never ambient)

        // UWB: no public API to query U1/U2 chip state; advisory only
        // Satellite (iPhone 14+): out of scope for communications policy

        // Server policy gate: block if a protocol the server wants disabled is enabled
        if let policy = communicationsPolicy {
            for (proto, shouldBeEnabled) in policy {
                guard !shouldBeEnabled else { continue }

                // Skip transport mismatch — handled separately as a warning
                if proto == activeTransport { continue }

                switch proto {
                case "bluetooth":
                    if isBluetoothOn {
                        // Already covered by static gate above, avoid duplicate
                        break
                    }
                case "airdrop":
                    if isBluetoothOn {
                        // Already covered above
                        break
                    }
                case "wifi":
                    // If we're not on WiFi but the radio could still be on, block with advisory
                    if activeTransport != "wifi" {
                        violations.append("Server policy requires Wi-Fi to be disabled. Please verify in Settings > Wi-Fi.")
                    }
                case "cellular":
                    if activeTransport != "cellular" {
                        violations.append("Server policy requires Cellular to be disabled. Please verify in Settings > Cellular.")
                    }
                case "uwb", "nfc", "satellite":
                    // No public API to verify state; future work
                    break
                default:
                    break
                }
            }
        }

        gateViolations = violations
    }

    // MARK: - Server Policy

    /// Called by ConnectionManager when clientConfig containing
    /// communicationsPolicy is received from the server.
    func applyPolicy(_ policy: [String: Bool]) {
        communicationsPolicy = policy
        
        // Only instantiate CentralManager if server policy explicitly allows/requests checking Bluetooth
        if let btEnabled = policy["bluetooth"], btEnabled {
            startBluetoothMonitor()
        } else {
            // Un-instantiate to ensure no background scanning occurs
            bluetoothManager = nil
        }
        
        evaluatePolicy()
        evaluatePolicyEnforcement()
    }

    /// Check for a mismatch between the active transport and server policy.
    private func evaluatePolicy() {
        guard let policy = communicationsPolicy else {
            transportMismatchWarning = nil
            return
        }

        // Map active transport to policy key
        let policyKey = activeTransport  // "wifi", "cellular", "ethernet", "usb"

        if let allowed = policy[policyKey], !allowed {
            transportMismatchWarning = "Warning: You are connected via \(policyKey.capitalized), but the server policy has \(policyKey.capitalized) disabled."
        } else {
            transportMismatchWarning = nil
        }
    }

    /// After receiving the server policy, prompt the user to disable
    /// any protocol that the policy says should be off — unless it
    /// conflicts with the active transport (which gets a mismatch warning).
    private func evaluatePolicyEnforcement() {
        guard let policy = communicationsPolicy else { return }

        var alerts: [String] = []

        for (protocol_, shouldBeEnabled) in policy {
            guard !shouldBeEnabled else { continue } // only care about disabled protocols

            // Skip if this is our active transport — that's a mismatch, not an enforcement
            if protocol_ == activeTransport { continue }

            // Check if the protocol is currently enabled
            switch protocol_ {
            case "bluetooth":
                if isBluetoothOn {
                    alerts.append("Server policy requires Bluetooth to be disabled. Please turn it off in Settings > Bluetooth.")
                }
            case "airdrop":
                // AirDrop depends on Bluetooth; if BT is on, AirDrop might be active
                if isBluetoothOn {
                    alerts.append("Server policy requires AirDrop to be disabled. Please turn it off in Settings > General > AirDrop.")
                }
            case "wifi":
                if activeTransport != "wifi" {
                    // We can't detect WiFi "radio on" separately from NWPathMonitor easily.
                    // If we're not on WiFi, the radio may still be on but we can't determine
                    // that without private APIs. Include as advisory.
                    alerts.append("Server policy requests Wi-Fi to be disabled. Please verify in Settings > Wi-Fi.")
                }
            case "cellular":
                if activeTransport != "cellular" {
                    alerts.append("Server policy requests Cellular to be disabled. Please verify in Settings > Cellular.")
                }
            case "uwb", "nfc", "satellite":
                // No public API to verify state; future work
                break
            default:
                break
            }
        }

        policyEnforcementAlerts = alerts
    }
}
