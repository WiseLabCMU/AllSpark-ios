import UIKit
import AVFoundation
import Vision
import CoreImage
import Combine

class CameraViewController: UIViewController, UIDocumentPickerDelegate, UINavigationControllerDelegate {

    // Camera session
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var audioOutput: AVCaptureAudioDataOutput!
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
    private var audioWriterInput: AVAssetWriterInput?
    private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var sessionAtSourceTime: CMTime?
    private var videoURL: URL?
    private var videoFormat: AVFileType = .mp4 // Default format
    private var recordingDurationMs: Int = 30000 // Default 30 seconds in milliseconds
    private var autoStopTimer: Timer?
    private var shouldUploadAfterRecording = false

    // WebSocket Connection
    private var cancellables = Set<AnyCancellable>()

    // Display layer
    private var imageView: UIImageView!
    private var recordButton: UIButton!
    private var switchCameraButton: UIButton!
    private var uploadButton: UIButton!
    private var timerLabel: UILabel!
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0
    private var connectionStatusIcon: UIButton!
    private var connectionSecureIcon: UIButton!

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
        setupFaceDetection()

        // ConnectionManager is a singleton, so we just ensure it's connected and observe it
        ConnectionManager.shared.connect()
        setupConnectionObserver()
        setupCommandObserver()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Check and request permissions each time the view appears
        checkAndRequestPermissions()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }

        // Close WebSocket connection
        // WebSocket connection is now managed by ConnectionManager (background), so we don't disconnect here.
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
            recordButton.heightAnchor.constraint(equalToConstant: 80)
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

        // Setup lock icon overlay for secure connection indicator
        connectionSecureIcon = UIButton(type: .system)
        connectionSecureIcon.translatesAutoresizingMaskIntoConstraints = false
        connectionSecureIcon.tintColor = .systemGreen
        connectionSecureIcon.isUserInteractionEnabled = false // Disable interaction, just display
        connectionSecureIcon.isHidden = true // Initially hidden

        if let lockImage = UIImage(systemName: "lock.fill") {
            let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold, scale: .default)
            connectionSecureIcon.setImage(lockImage.withConfiguration(config), for: .normal)
        }

        view.addSubview(connectionSecureIcon)

        NSLayoutConstraint.activate([
            connectionSecureIcon.bottomAnchor.constraint(equalTo: connectionStatusIcon.bottomAnchor, constant: 2),
            connectionSecureIcon.trailingAnchor.constraint(equalTo: connectionStatusIcon.trailingAnchor, constant: 2),
            connectionSecureIcon.widthAnchor.constraint(equalToConstant: 20),
            connectionSecureIcon.heightAnchor.constraint(equalToConstant: 20)
        ])

        updateConnectionStatusIcon()
    }

    private func updateConnectionStatusIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if ConnectionManager.shared.isConnected {
                // Connected - green
                if let image = UIImage(systemName: "wifi") {
                    self.connectionStatusIcon.setImage(image, for: .normal)
                    self.connectionStatusIcon.tintColor = .systemGreen
                }
                // Show lock icon if using secure protocol
                self.connectionSecureIcon.isHidden = !ConnectionManager.shared.isSecureProtocol
            } else if ConnectionManager.shared.isAttemptingConnection {
                // Attempting connection - amber/orange
                if let image = UIImage(systemName: "wifi") {
                    self.connectionStatusIcon.setImage(image, for: .normal)
                    self.connectionStatusIcon.tintColor = .systemOrange
                }
                // Hide lock icon while attempting
                self.connectionSecureIcon.isHidden = true
            } else {
                // Disconnected - red
                if let image = UIImage(systemName: "wifi.slash") {
                    self.connectionStatusIcon.setImage(image, for: .normal)
                    self.connectionStatusIcon.tintColor = .systemRed
                }
                // Hide lock icon when disconnected
                self.connectionSecureIcon.isHidden = true
            }
        }
    }

    private func setupConnectionObserver() {
        // Observe connection state changes
        ConnectionManager.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateConnectionStatusIcon()
            }
            .store(in: &cancellables)

        ConnectionManager.shared.$isAttemptingConnection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateConnectionStatusIcon()
            }
            .store(in: &cancellables)
    }

    private func setupCommandObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteCommand(_:)), name: .didReceiveRemoteCommand, object: nil)
    }

    @objc private func handleRemoteCommand(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let json = userInfo["payload"] as? [String: Any] else { return }

        print("Incoming message payload: \(json)")

        // Handle command messages
        if let command = json["command"] as? String {
            switch command {
            case "record":
                // Parse optional duration parameter (in milliseconds), default to 30 seconds
                var duration = 30000 // 30 seconds default
                if let durationValue = json["duration"] as? Int {
                    duration = durationValue
                }
                self.recordingDurationMs = duration

                // Parse optional autoUpload flag, default to false
                let autoUpload = (json["autoUpload"] as? NSNumber)?.boolValue ?? false

                // Parse optional camera parameter
                let requestedCamera = json["camera"] as? String

                DispatchQueue.main.async {
                    // content of durationSeconds
                    let durationSeconds = Double(duration) / 1000.0

                    // Switch camera if needed
                    if let cameraType = requestedCamera {
                        let targetPosition: AVCaptureDevice.Position = (cameraType.lowercased() == "back") ? .back : .front
                        if self.currentCameraPosition != targetPosition {
                            self.switchCamera()
                        }
                    }

                    // Start recording
                    self.startRecording()

                    // Set auto-stop timer to stop recording and optionally upload after the specified duration
                    self.autoStopTimer?.invalidate()
                    self.autoStopTimer = Timer.scheduledTimer(withTimeInterval: durationSeconds, repeats: false) { [weak self] _ in
                        print("Auto-stopping recording after \(durationSeconds)s")
                        self?.stopRecording(autoUpload: autoUpload) {
                            print("Recording and upload workflow completed")
                        }
                    }
                }
            default:
                print("Unknown command: \(command)")
            }
        } else if let status = json["status"] as? String {
            // Handle status messages
            if status == "success" {
                let alert = UIAlertController(title: "Upload Successful", message: "Video uploaded successfully", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
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

        // Get device name for filename
        let deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? UIDevice.current.name
        let deviceNameForFilename = formatDeviceNameForFilename(deviceName)

        // Get camera position for filename
        let cameraPosition = currentCameraPosition == .front ? "front" : "back"

        let timestamp = Date().timeIntervalSince1970
        let videoName = "recording_\(deviceNameForFilename)_\(cameraPosition)_\(timestamp).\(fileExtension)"
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

                // Setup audio writer input
                let audioOutputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44100.0,
                    AVEncoderBitRateKey: 128000
                ]

                audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
                audioWriterInput?.expectsMediaDataInRealTime = true

                if let audioInput = audioWriterInput, assetWriter!.canAdd(audioInput) {
                    assetWriter!.add(audioInput)
                } else {
                    print("Failed to add audio input to asset writer")
                }

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
                print("Failed to add video input to asset writer")
            }
        } catch {
            print("Failed to setup asset writer: \(error)")
        }
    }

    private func stopRecording(autoUpload: Bool = false, completion: (() -> Void)? = nil) {
        guard isRecording else { return }

        isRecording = false
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        recordingTimer?.invalidate()
        recordingTimer = nil
        timerLabel.isHidden = true

        if assetWriter?.status == .failed {
            print("Asset writer status is failed: \(String(describing: assetWriter?.error))")
        }

        assetWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            guard let self = self, let url = self.videoURL else {
                completion?()
                return
            }
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
                // Only show alert if this is a user-initiated stop (not auto-upload)
                if !autoUpload && fileExists {
                    let alert = UIAlertController(title: "Saved", message: "Video saved to \(url.lastPathComponent)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                } else if !autoUpload && !fileExists {
                    let alert = UIAlertController(title: "Error", message: "Failed to save video: File at \(url.lastPathComponent) not found.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }

                // If autoUpload is enabled and file exists, trigger upload
                if autoUpload && fileExists {
                    print("Auto-uploading recorded video: \(url.lastPathComponent)")
                    self.uploadVideo(at: url)
                }

                completion?()
            }

            self.assetWriter = nil
            self.assetWriterInput = nil
            self.audioWriterInput = nil
            self.adapter = nil
        }
    }

    private func setupCamera() {
        // Camera initialization will be handled in checkAndRequestPermissions
        setupFaceDetection()
    }

    private func setupAudioInput() {
        // Check if audio input already exists
        let audioInputExists = captureSession.inputs.contains { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.audio)
        }

        if !audioInputExists {
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                print("Failed to get audio device")
                return
            }

            guard let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
                print("Failed to create audio input")
                return
            }

            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        }

        // Check if audio output already exists
        let audioOutputExists = captureSession.outputs.contains { output in
            return output is AVCaptureAudioDataOutput
        }

        if !audioOutputExists {
            audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))

            if captureSession.canAddOutput(audioOutput) {
                captureSession.addOutput(audioOutput)
            }
        }
    }

    private func checkAndRequestPermissions() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraStatus {
        case .authorized:
            // Camera permission already granted
            initializeCameraIfNeeded()
            requestMicrophonePermission()
        case .denied, .restricted:
            // Permission was denied or restricted
            showPermissionDeniedAlert(permissionType: "Camera")
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.initializeCameraIfNeeded()
                        self?.requestMicrophonePermission()
                    } else {
                        self?.showPermissionDeniedAlert(permissionType: "Camera")
                    }
                }
            }
        @unknown default:
            print("Unknown camera permission status")
        }
    }

    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.setupAudioInput()
                }
            } else {
                print("Microphone permission denied")
                DispatchQueue.main.async {
                    self?.showPermissionDeniedAlert(permissionType: "Microphone")
                }
            }
        }
    }

    private func initializeCameraIfNeeded() {
        guard captureSession == nil else {
            // Camera already initialized, just start running
            if !captureSession.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.captureSession?.startRunning()
                }
            }
            // Reconnect WebSocket logic is now handled by ConnectionManager

            return
        }

        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        // Load saved camera position preference
        let savedCameraPosition = UserDefaults.standard.string(forKey: "cameraPosition") ?? "front"
        currentCameraPosition = savedCameraPosition == "back" ? .back : .front

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

        // Start running
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }

        // Reconnect WebSocket logic is now handled by ConnectionManager

    }

    private func showPermissionDeniedAlert(permissionType: String) {
        let alert = UIAlertController(title: "\(permissionType) Permission Required", message: "This app needs \(permissionType.lowercased()) access to function properly. Please enable it in Settings.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Go to Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(alert, animated: true)
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

    private func recordAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData else { return }

        if sessionAtSourceTime == nil {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            sessionAtSourceTime = timestamp
            assetWriter?.startSession(atSourceTime: timestamp)
        }

        let success = audioInput.append(sampleBuffer)
        if !success {
            print("Failed to append audio buffer. Writer status: \(String(describing: assetWriter?.status.rawValue)) Error: \(String(describing: assetWriter?.error))")
        }
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

    // MARK: - Helper Methods

    private func formatDeviceNameForFilename(_ name: String) -> String {
        // Remove non-ASCII characters
        let ascii = name.filter { $0.isASCII }

        // Split on non-alphanumeric characters and filter empty components
        let components = ascii.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Build title-case: capitalize first letter of each word
        guard !components.isEmpty else { return "Device" }

        let result = components.map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined()

        return result.isEmpty ? "Device" : result
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
        ConnectionManager.shared.uploadVideo(at: fileURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                     print("Video upload initiated/completed successfully")
                case .failure(let error):
                    let alert = UIAlertController(title: "Upload Failed", message: "Failed to upload video: \(error.localizedDescription)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle audio output
        if output == audioOutput {
            recordAudioFrame(sampleBuffer)
            return
        }

        // Handle video output
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
