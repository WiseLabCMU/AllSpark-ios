import UIKit
import AVFoundation
import Vision
import CoreImage

class CameraViewController: UIViewController, UIDocumentPickerDelegate, UINavigationControllerDelegate {

    // Camera session
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    // Orientation management
    private var videoRotationAngle: CGFloat = 90
    private var rotationCoordinator: AnyObject? // Store as AnyObject to avoid availability checks on property decl

    // Image processing
    private let context = CIContext()

    // Face detection
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest!
    private var detectedFaces: [VNFaceObservation] = []

    // Video Recording
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var sessionAtSourceTime: CMTime?
    private var videoURL: URL?
    private var videoFormat: AVFileType = .mp4 // Default format

    // WebSocket Connection
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketURL: URL?
    private var isConnected = false
    private var isSecureProtocol = false
    private var isAttemptingConnection = false
    private var connectionAttemptTimer: Timer?

    // Display layer
    private var imageView: UIImageView!
    private var recordButton: UIButton!
    private var switchCameraButton: UIButton!
    private var uploadButton: UIButton!
    private var timerLabel: UILabel!
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0
    private var connectionStatusIcon: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupImageView()
        setupRecordButton()

        setupSwitchCameraButton()
        setupUploadButton()
        setupTimerLabel()
        setupConnectionStatusIcon()
        setupCamera()
        setupFaceDetection()
        setupWebSocketConnection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }

        // Reconnect WebSocket if not connected
        if !isConnected && !isAttemptingConnection {
            setupWebSocketConnection()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        // Close WebSocket connection
        disconnectWebSocket()
    }

    private func setupImageView() {
        imageView = UIImageView(frame: view.bounds)
        imageView.contentMode = .scaleAspectFill
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
    }

    private func setupRecordButton() {
        recordButton = UIButton(type: .system)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        if let image = UIImage(systemName: "circle.circle.fill") {
            // Using a large circle fill to mimic a record button
            recordButton.setImage(image, for: .normal)
            recordButton.tintColor = .red
            recordButton.backgroundColor = .clear // Remove background if using image
            // Scale up the image
            let config = UIImage.SymbolConfiguration(pointSize: 60, weight: .regular, scale: .default)
            recordButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        } else {
            recordButton.setTitle("Record", for: .normal)
            recordButton.backgroundColor = UIColor.red.withAlphaComponent(0.7)
            recordButton.setTitleColor(.white, for: .normal)
            recordButton.layer.cornerRadius = 25
        }
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)

        view.addSubview(recordButton)

        NSLayoutConstraint.activate([
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 80),
            recordButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupSwitchCameraButton() {
        switchCameraButton = UIButton(type: .system)
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        // Use a standard system image if available, otherwise text
        if let image = UIImage(systemName: "arrow.triangle.2.circlepath") {
            switchCameraButton.setImage(image, for: .normal)
        } else {
            switchCameraButton.setTitle("Flip", for: .normal)
        }
        switchCameraButton.tintColor = .white
        switchCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        switchCameraButton.layer.cornerRadius = 25
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)

        view.addSubview(switchCameraButton)

        NSLayoutConstraint.activate([
            switchCameraButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            switchCameraButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            switchCameraButton.widthAnchor.constraint(equalToConstant: 50),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 50)
        ])

    }

    private func setupUploadButton() {
        uploadButton = UIButton(type: .system)
        uploadButton.translatesAutoresizingMaskIntoConstraints = false
        if let image = UIImage(systemName: "square.and.arrow.up") {
             uploadButton.setImage(image, for: .normal)
        } else {
            uploadButton.setTitle("Upload", for: .normal)
        }
        uploadButton.tintColor = .white
        uploadButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        uploadButton.layer.cornerRadius = 25
        uploadButton.addTarget(self, action: #selector(promptForUpload), for: .touchUpInside)

        view.addSubview(uploadButton)

        NSLayoutConstraint.activate([
            uploadButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            uploadButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            uploadButton.widthAnchor.constraint(equalToConstant: 50),
            uploadButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupTimerLabel() {
        timerLabel = UILabel()
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = "00:00"
        timerLabel.textColor = .white
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        timerLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        timerLabel.layer.cornerRadius = 8
        timerLabel.clipsToBounds = true
        timerLabel.textAlignment = .center
        timerLabel.isHidden = true // Initially hidden

        view.addSubview(timerLabel)

        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.widthAnchor.constraint(equalToConstant: 80),
            timerLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func setupConnectionStatusIcon() {
        connectionStatusIcon = UIButton(type: .system)
        connectionStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        connectionStatusIcon.tintColor = .white
        connectionStatusIcon.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        connectionStatusIcon.layer.cornerRadius = 20
        connectionStatusIcon.isUserInteractionEnabled = false // Disable interaction, just display

        view.addSubview(connectionStatusIcon)

        NSLayoutConstraint.activate([
            connectionStatusIcon.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            connectionStatusIcon.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -80),
            connectionStatusIcon.widthAnchor.constraint(equalToConstant: 40),
            connectionStatusIcon.heightAnchor.constraint(equalToConstant: 40)
        ])

        updateConnectionStatusIcon()
    }



    private func updateConnectionStatusIcon() {
        DispatchQueue.main.async { [weak self] in
            if self?.isConnected ?? false {
                // Connected - green
                if let image = UIImage(systemName: "wifi") {
                    self?.connectionStatusIcon.setImage(image, for: .normal)
                    self?.connectionStatusIcon.tintColor = .systemGreen
                }
            } else if self?.isAttemptingConnection ?? false {
                // Attempting connection - amber/orange
                if let image = UIImage(systemName: "wifi") {
                    self?.connectionStatusIcon.setImage(image, for: .normal)
                    self?.connectionStatusIcon.tintColor = .systemOrange
                }
            } else {
                // Disconnected - red
                if let image = UIImage(systemName: "wifi.slash") {
                    self?.connectionStatusIcon.setImage(image, for: .normal)
                    self?.connectionStatusIcon.tintColor = .systemRed
                }
            }
        }
    }




    @objc private func switchCamera() {
        guard !isRecording else { return } // Disable switching while recording

        captureSession.beginConfiguration()

        // Remove existing input
        if let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput {
            captureSession.removeInput(currentInput)
        }

        // Toggle position
        currentCameraPosition = (currentCameraPosition == .front) ? .back : .front

        // Get new device
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            print("Failed to get camera for position \(currentCameraPosition)")
            captureSession.commitConfiguration()
            return
        }

        // Add new input
        guard let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
            print("Failed to create input for new camera")
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
        }

        // Re-configure orientation
        // Reset coordinator to force re-initialization with new device
        rotationCoordinator = nil

        // Ensure connection orientation is correct
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                 // updateVideoOrientation will handle re-init of coordinator
            } else {
                connection.videoOrientation = .portrait
                // For back camera, we might need to adjust mirroring if we were mirroring front
                if currentCameraPosition == .front {
                    connection.isVideoMirrored = true
                } else {
                    connection.isVideoMirrored = false
                }
            }
        }

        captureSession.commitConfiguration()

        // Update orientation logic (re-inits coordinator)
        DispatchQueue.main.async {
            self.updateVideoOrientation()
        }
    }



    private func updateTimerDisplay() {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
            if let image = UIImage(systemName: "stop.circle.fill") {
                 recordButton.setImage(image, for: .normal)
                 recordButton.tintColor = .gray
            } else {
                recordButton.setTitle("Record", for: .normal)
                recordButton.backgroundColor = UIColor.red.withAlphaComponent(0.7)
            }
        } else {
            startRecording()
            if let image = UIImage(systemName: "record.circle") {
                 recordButton.setImage(image, for: .normal)
                 recordButton.tintColor = .red
            } else {
                recordButton.setTitle("Stop", for: .normal)
                recordButton.backgroundColor = UIColor.gray.withAlphaComponent(0.7)
            }
        }
    }

    private func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Load video format preference from UserDefaults
        let formatString = UserDefaults.standard.string(forKey: "videoFormat") ?? "mp4"
        let fileExtension = formatString == "mov" ? "mov" : "mp4"
        let fileType: AVFileType = formatString == "mov" ? .mov : .mp4

        let videoName = "recording_\(Date().timeIntervalSince1970).\(fileExtension)"
        videoURL = documentsPath.appendingPathComponent(videoName)

        guard let videoURL = videoURL else { return }

        // Remove existing file if necessary
        try? FileManager.default.removeItem(at: videoURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: fileType)

            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoRotationAngle == 0 || videoRotationAngle == 180 ? 1920 : 1080,
                AVVideoHeightKey: videoRotationAngle == 0 || videoRotationAngle == 180 ? 1080 : 1920
            ]

            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true

            if let input = assetWriterInput, assetWriter!.canAdd(input) {
                assetWriter!.add(input)

                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: videoRotationAngle == 0 || videoRotationAngle == 180 ? 1920 : 1080,
                    kCVPixelBufferHeightKey as String: videoRotationAngle == 0 || videoRotationAngle == 180 ? 1080 : 1920
                ]

                adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)

                assetWriter!.startWriting()
                // assetWriter!.startSession(atSourceTime: .zero) // REMOVED: Will start session on first frame

                isRecording = true
                sessionAtSourceTime = nil

                // Start timer
                recordingDuration = 0
                updateTimerDisplay()
                timerLabel.isHidden = false
                DispatchQueue.main.async {
                    self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                        guard let self = self else { return }
                        self.recordingDuration += 1
                        self.updateTimerDisplay()
                    }
                }
            } else {
                print("Failed to add input to asset writer")
            }
        } catch {
            print("Failed to setup asset writer: \(error)")
        }
    }

    private func stopRecording() {
        guard isRecording else { return }

        isRecording = false

        recordingTimer?.invalidate()
        recordingTimer = nil
        timerLabel.isHidden = true

        if assetWriter?.status == .failed {
            print("Asset writer status is failed: \(String(describing: assetWriter?.error))")
        }

        assetWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            guard let self = self, let url = self.videoURL else { return }
            print("Video saved to: \(url.path)")

            let fileExists = FileManager.default.fileExists(atPath: url.path)

            if fileExists {
                 print("File verified to exist at path: \(url.path)")
                 let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                 print("File size: \(attributes?[.size] ?? "unknown") bytes")
            } else {
                 print("ERROR: File does not exist at path: \(url.path)")
            }

            DispatchQueue.main.async {
                if fileExists {
                    let alert = UIAlertController(title: "Saved", message: "Video saved to \(url.lastPathComponent)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                } else {
                    let alert = UIAlertController(title: "Error", message: "Failed to save video: File at \(url.lastPathComponent) not found.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }

            self.assetWriter = nil
            self.assetWriterInput = nil
            self.adapter = nil
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            print("Failed to get camera device")
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            print("Failed to create video input")
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }


        // Set initial video orientation
        updateVideoOrientation()
    }

    private func updateVideoOrientation() {
        if #available(iOS 17.0, *), let videoCaptureDevice = captureSession.inputs.first as? AVCaptureDeviceInput {
            // Initialize RotationCoordinator if needed
            if rotationCoordinator == nil {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: videoCaptureDevice.device, previewLayer: nil)
                self.rotationCoordinator = coordinator

                // Observe changes
                NotificationCenter.default.addObserver(forName: NSNotification.Name("AVCaptureDeviceRotationCoordinatorVideoRotationAngleDidChangeNotification"), object: coordinator, queue: .main) { [weak self] _ in
                    self?.updateVideoOrientation()
                }
            }

            if let coordinator = rotationCoordinator as? AVCaptureDevice.RotationCoordinator {
                self.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                 if let connection = videoOutput.connection(with: .video) {
                    connection.videoRotationAngle = self.videoRotationAngle
                 }
            }
        } else {
             // Fallback for older iOS
             if let connection = videoOutput.connection(with: .video) {
                 connection.videoOrientation = .portrait
             }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateVideoOrientation()
        }
    }

    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let observations = request.results as? [VNFaceObservation] else {
                return
            }

            self?.detectedFaces = observations
        }
    }

    private func blurFaces(in ciImage: CIImage, faces: [VNFaceObservation]) -> CIImage {
        var outputImage = ciImage
        let imageSize = ciImage.extent.size

        for face in faces {
            // Convert normalized coordinates to image coordinates
            // Vision uses normalized coordinates (0-1) with origin at bottom-left
            let boundingBox = face.boundingBox

            // Convert from Vision coordinates to CIImage coordinates
            let x = boundingBox.origin.x * imageSize.width
            let y = boundingBox.origin.y * imageSize.height
            let width = boundingBox.width * imageSize.width
            let height = boundingBox.height * imageSize.height

            // Expand the box slightly for better coverage
            let expansion: CGFloat = 0.3
            let expandedX = max(0, x - width * expansion)
            let expandedY = max(0, y - height * expansion)
            let expandedWidth = min(imageSize.width - expandedX, width * (1 + 2 * expansion))
            let expandedHeight = min(imageSize.height - expandedY, height * (1 + 2 * expansion))

            let faceRect = CGRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)

            // Create blur filter
            if let blurFilter = CIFilter(name: "CIPixellate") {
                // Crop the face region
                let faceCrop = outputImage.cropped(to: faceRect)

                blurFilter.setValue(faceCrop, forKey: kCIInputImageKey)
                blurFilter.setValue(40.0, forKey: kCIInputScaleKey)

                if let blurredOutput = blurFilter.outputImage {
                    // The blur filter expands the image, so we need to crop it back
                    let croppedBlur = blurredOutput.cropped(to: faceRect)

                    // Composite the blurred face back onto the original image
                    outputImage = croppedBlur.composited(over: outputImage)
                }
            }
        }

        return outputImage
    }

    private func recordVideoFrame(_ image: CIImage, timestamp: CMTime) {
        guard isRecording, let adapter = adapter, let input = assetWriterInput, input.isReadyForMoreMediaData else { return }

        if sessionAtSourceTime == nil {
            sessionAtSourceTime = timestamp
            assetWriter?.startSession(atSourceTime: timestamp)
        }

        // Render CIImage to CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        let width = Int(image.extent.width)
        let height = Int(image.extent.height)

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)

        if status == kCVReturnSuccess, let buffer = pixelBuffer {
            context.render(image, to: buffer)

            let success = adapter.append(buffer, withPresentationTime: timestamp)
            if !success {
                print("Failed to append buffer. Writer status: \(String(describing: assetWriter?.status.rawValue)) Error: \(String(describing: assetWriter?.error))")
            }
        } else {
            print("Failed to create CVPixelBuffer")
        }
    }

    // MARK: - WebSocket Methods

    private func setupWebSocketConnection() {
        var hostString = UserDefaults.standard.string(forKey: "serverHost") ?? "localhost:8080"

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
            print("Invalid WebSocket URL: \(hostString)")
            return
        }

        self.webSocketURL = wsURLSecure
        connectWebSocket()
    }

    private func connectWebSocket() {
        guard let wsURL = webSocketURL else { return }
        guard !isAttemptingConnection else { return } // Prevent multiple simultaneous attempts

        isAttemptingConnection = true
        updateConnectionStatusIcon()

        // Set secure protocol flag based on connection URL
        if wsURL.absoluteString.lowercased().hasPrefix("wss://") {
            isSecureProtocol = true
        } else {
            isSecureProtocol = false
        }

        let verifyCertificate = UserDefaults.standard.bool(forKey: "verifyCertificate")
        let config = URLSessionConfiguration.default
        let delegate = CertificateVerificationDelegate(verifyCertificate: verifyCertificate)
        let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = urlSession.webSocketTask(with: wsURL)

        self.webSocketTask = task
        task.resume()

        print("Connecting to WebSocket at \(wsURL)")

        // Start receiving messages - this will detect connection errors and trigger fallback if needed
        receiveWebSocketMessage()
    }

    private func attemptWsFallback() {
        guard let wsURL = webSocketURL else { return }
        guard isSecureProtocol else { return } // Only fallback if we were trying WSS

        // Convert wss:// to ws://
        var wsURLString = wsURL.absoluteString
        wsURLString = wsURLString.replacingOccurrences(of: "wss://", with: "ws://")

        guard let wsURLFallback = URL(string: wsURLString) else {
            print("Invalid WebSocket fallback URL: \(wsURLString)")
            return
        }

        // Disconnect the current failed WSS task
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
        }
        webSocketTask = nil
        isAttemptingConnection = false

        // Update the URL to the fallback WS URL
        webSocketURL = wsURLFallback
        isSecureProtocol = false

        print("WSS connection failed, attempting WS fallback at \(wsURLFallback)")

        // Now connect using WS
        connectWebSocket()
    }

    private func disconnectWebSocket() {
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
        }
        webSocketTask = nil
        isConnected = false
        isAttemptingConnection = false
        connectionAttemptTimer?.invalidate()
        connectionAttemptTimer = nil
        updateConnectionStatusIcon()
        print("WebSocket disconnected")
    }
}



extension CameraViewController {
    @objc private func promptForUpload() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false

        // Set default directory to Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        documentPicker.directoryURL = documentsPath

        present(documentPicker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else { return }
        uploadVideo(at: selectedFileURL)
    }

    private func uploadVideo(at fileURL: URL) {
        guard isConnected, let webSocketTask = webSocketTask else {
            let alert = UIAlertController(title: "Connection Error", message: "WebSocket not connected. Please try again.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }

        let videoData: Data
        do {
            videoData = try Data(contentsOf: fileURL)
        } catch {
            print("Failed to load video data: \(error)")
            return
        }

        let filename = fileURL.lastPathComponent

        // Determine mimetype based on file extension
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        let mimetype = fileExtension == "mp4" ? "video/mp4" : "video/quicktime"

        // Send video metadata first
        let metadata: [String: Any] = [
            "type": "upload",
            "filename": filename,
            "filesize": videoData.count,
            "mimetype": mimetype
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let metadataMessage = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask.send(metadataMessage) { [weak self] error in
                if let error = error {
                    print("Failed to send metadata: \(error)")
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Upload Failed", message: "Failed to send metadata: \(error.localizedDescription)", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(alert, animated: true)
                    }
                    return
                }

                // Send video data as binary message
                let dataMessage = URLSessionWebSocketTask.Message.data(videoData)
                webSocketTask.send(dataMessage) { [weak self] error in
                    DispatchQueue.main.async {
                        if let error = error {
                            let alert = UIAlertController(title: "Upload Failed", message: "Failed to send video: \(error.localizedDescription)", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            self?.present(alert, animated: true)
                            return
                        }

                        // Listen for server response
                        self?.receiveWebSocketMessage()
                    }
                }
            }
        }
    }

    private func receiveWebSocketMessage() {
        guard let webSocketTask = webSocketTask else { return }

        // Set a flag to track if this is the first receive attempt for this connection
        let isFirstReceive = !isConnected && isAttemptingConnection

        webSocketTask.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    // Mark as connected on first successful receive (connection is established)
                    if self?.isConnected == false && self?.isAttemptingConnection == true {
                        self?.isConnected = true
                        self?.isAttemptingConnection = false
                        self?.connectionAttemptTimer?.invalidate()
                        self?.connectionAttemptTimer = nil
                        self?.updateConnectionStatusIcon()

                        print("WebSocket connection established")
                    }

                    switch message {
                    case .string(let text):
                        print("Server response: \(text)")
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                            // Handle command messages
                            if let command = json["command"] as? String {
                                switch command {
                                case "record":
                                    let commandMessage = json["message"] as? String ?? "Record command received from server"
                                    let alert = UIAlertController(title: "Record Command", message: commandMessage, preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self?.present(alert, animated: true)
                                default:
                                    print("Unknown command: \(command)")
                                }
                            } else if let status = json["status"] as? String {
                                // Handle status messages
                                if status == "success" {
                                    let alert = UIAlertController(title: "Upload Successful", message: "Video uploaded successfully", preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self?.present(alert, animated: true)
                                }
                            }
                        }
                        // Continue listening for more messages
                        self?.receiveWebSocketMessage()
                    case .data(let data):
                        print("Received binary data from server")
                        self?.receiveWebSocketMessage()
                    @unknown default:
                        break
                    }
                case .failure(let error):
                    print("WebSocket receive error: \(error)")

                    // If we haven't connected yet and were using WSS, try the WS fallback
                    if self?.isConnected == false && self?.isSecureProtocol == true {
                        let errorString = error.localizedDescription.lowercased()
                        // Check for common secure connection errors
                        if errorString.contains("tls") || errorString.contains("certificate") || errorString.contains("refused") || errorString.contains("connection") {
                            print("WSS connection failed, attempting WS fallback...")
                            self?.connectionAttemptTimer?.invalidate()
                            self?.connectionAttemptTimer = nil
                            self?.attemptWsFallback()
                        }
                    } else if self?.isConnected == false {
                        // WS fallback also failed
                        print("WS fallback connection failed")
                        self?.connectionAttemptTimer?.invalidate()
                        self?.connectionAttemptTimer = nil
                        self?.isAttemptingConnection = false
                        self?.updateConnectionStatusIcon()
                    }
                }
            }
        }

        // On first receive, set a short timeout to mark connection as established if no early error
        if isFirstReceive {
            connectionAttemptTimer?.invalidate()
            connectionAttemptTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                // If we still haven't connected after 0.5s but no error occurred, mark as connected
                if self?.isConnected == false && self?.isAttemptingConnection == true {
                    DispatchQueue.main.async {
                        self?.isConnected = true
                        self?.isAttemptingConnection = false
                        self?.connectionAttemptTimer = nil
                        self?.updateConnectionStatusIcon()
                        print("WebSocket connection established (timeout)")
                    }
                }
            }
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Perform face detection
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:])

        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Failed to perform face detection: \(error)")
        }

        // Apply blur to detected faces
        let processedImage = blurFaces(in: ciImage, faces: detectedFaces)

        // Record output
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        recordVideoFrame(processedImage, timestamp: timestamp)

        // Convert to UIImage and display
        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)

            DispatchQueue.main.async { [weak self] in
                self?.imageView.image = uiImage
            }
        }
    }
}
