import SwiftUI
import AVFoundation

struct PairingView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var serverHost: String
    @State private var isScanning = true
    @State private var sessionError: String?

    var body: some View {
        NavigationView {
            ZStack {
                QRScannerController(serverHost: $serverHost, isScanning: $isScanning, sessionError: $sessionError, onScan: { code in
                    // Validate and set host
                    // Code format expected: "host:port" or "ws://host:port", etc.
                    // We want to extract just host:port or keep it as is if Settings expects it.
                    // SettingsView uses "host:port" usually, logic adds ws://.
                    // Let's strip protocols.
                    print("Scanned Server QR Code: \(code)")

                    var cleanCode = code
                        .replacingOccurrences(of: "ws://", with: "")
                        .replacingOccurrences(of: "wss://", with: "")
                        .replacingOccurrences(of: "http://", with: "")
                        .replacingOccurrences(of: "https://", with: "")

                    if cleanCode.hasSuffix("/") {
                        cleanCode.removeLast()
                    }

                    if cleanCode.contains(":") {
                        print("Updating server host to: \(cleanCode)")
                        serverHost = cleanCode
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        print("Invalid format (missing port?): \(code)")
                        isScanning = true // Resume
                    }
                })
                .edgesIgnoringSafeArea(.all)

                if let error = sessionError {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                }

                VStack {
                    Spacer()
                    Text("Scan Server QR Code")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                        .padding(.bottom, 50)
                }
            }
            .navigationBarTitle("Pair Server", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct QRScannerController: UIViewControllerRepresentable {
    @Binding var serverHost: String
    @Binding var isScanning: Bool
    @Binding var sessionError: String?
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        if isScanning {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerController

        init(_ parent: QRScannerController) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                parent.isScanning = false
                parent.onScan(stringValue)
            }
        }
    }
}

class ScannerViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var delegate: AVCaptureMetadataOutputObjectsDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Fix preview orientation
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        startScanning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let previewLayer = previewLayer {
            previewLayer.frame = view.layer.bounds

            // Update orientation
            if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
                switch orientation {
                case .portrait: connection.videoOrientation = .portrait
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                default: connection.videoOrientation = .portrait
                }
            }
        }
    }

    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    func startScanning() {
        if (captureSession?.isRunning == false) {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    func stopScanning() {
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
}
