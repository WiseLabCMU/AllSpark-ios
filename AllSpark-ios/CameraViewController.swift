import UIKit
import AVFoundation
import Vision
import CoreImage

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
        setupWebSocketConnection()
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
            if self?.isConnected ?? false {
                // Connected - green
                if let image = UIImage(systemName: "wifi") {
                    self?.connectionStatusIcon.setImage(image, for: .normal)
                    self?.connectionStatusIcon.tintColor = .systemGreen
                }
                // Show lock icon if using secure protocol
                self?.connectionSecureIcon.isHidden = !(self?.isSecureProtocol ?? false)
            } else if self?.isAttemptingConnection ?? false {
                // Attempting connection - amber/orange
                if let image = UIImage(systemName: "wifi") {
                    self?.connectionStatusIcon.setImage(image, for: .normal)
                    self?.connectionStatusIcon.tintColor = .systemOrange
                }
                // Hide lock icon while attempting
                self?.connectionSecureIcon.isHidden = true
            } else {
                // Disconnected - red
                if let image = UIImage(systemName: "wifi.slash") {
                    self?.connectionStatusIcon.setImage(image, for: .normal)
                    self?.connectionStatusIcon.tintColor = .systemRed
                }
                // Hide lock icon when disconnected
                self?.connectionSecureIcon.isHidden = true
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

        audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))

        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
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
            // Reconnect WebSocket if not connected
            if !isConnected && !isAttemptingConnection {
                setupWebSocketConnection()
            }
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

        // Reconnect WebSocket if not connected
        if !isConnected && !isAttemptingConnection {
            setupWebSocketConnection()
        }
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

    // MARK: - WebSocket Methods

    private func getClientDisplayName() -> String {
        let deviceName = UIDevice.current.name
        let customDeviceName = UserDefaults.standard.string(forKey: "deviceName") ?? deviceName
        let customName = UserDefaults.standard.string(forKey: "clientDisplayName")

        print("UIDevice.current.name: \(UIDevice.current.name)")
        print("Device name: \(deviceName)")
        print("Custom device name from settings: \(customDeviceName)")

        if let customName = customName, !customName.isEmpty {
            print("Custom name: \(customName)")
            return "\(customName) (\(customDeviceName))"
        } else {
            return customDeviceName
        }
    }

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

        // Send client identification message immediately after connection
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
                        // Connection failed, mark as not attempting and try fallback if WSS
                        if self?.isSecureProtocol == true {
                            print("Client info send failed for WSS, attempting WS fallback...")
                            self?.connectionAttemptTimer?.invalidate()
                            self?.connectionAttemptTimer = nil
                            self?.attemptWsFallback()
                        } else {
                            print("Client info send failed for WS")
                            self?.isAttemptingConnection = false
                            self?.updateConnectionStatusIcon()
                        }
                    }
                } else {
                    print("Client info sent: \(clientName)")
                    DispatchQueue.main.async {
                        // Message sent successfully, mark as connected
                        self?.isConnected = true
                        self?.isAttemptingConnection = false
                        self?.connectionAttemptTimer?.invalidate()
                        self?.connectionAttemptTimer = nil
                        self?.updateConnectionStatusIcon()
                        print("WebSocket connection established (client info sent successfully)")
                    }
                }
            }
        }

        // Start receiving messages for incoming commands
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

        webSocketTask.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):

                    switch message {
                    case .string(let text):
                        print("Server response: \(text)")
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                            // Log incoming message payload
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
                                    self?.recordingDurationMs = duration

                                    // Parse optional autoUpload flag, default to false
                                    let autoUpload = (json["autoUpload"] as? NSNumber)?.boolValue ?? false

                                    let durationSeconds = Double(duration) / 1000.0

                                    DispatchQueue.main.async {
                                        // Start recording
                                        self?.startRecording()

                                        // Set auto-stop timer to stop recording and optionally upload after the specified duration
                                        self?.autoStopTimer?.invalidate()
                                        self?.autoStopTimer = Timer.scheduledTimer(withTimeInterval: durationSeconds, repeats: false) { [weak self] _ in
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
                    } else if self?.isConnected == true {
                        // Server was connected but became unavailable - mark as disconnected
                        print("Server disconnected unexpectedly")
                        self?.handleServerDisconnection()
                    }
                }
            }
        }
    }

    private func handleServerDisconnection() {
        isConnected = false
        isAttemptingConnection = false
        connectionAttemptTimer?.invalidate()
        connectionAttemptTimer = nil
        webSocketTask = nil

        print("Updating UI to reflect server disconnection")
        updateConnectionStatusIcon()

        // Optionally show a notification to the user
        let alert = UIAlertController(title: "Server Disconnected", message: "The connection to the server was lost. Please check your network and try reconnecting.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reconnect", style: .default) { [weak self] _ in
            self?.setupWebSocketConnection()
        })
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel))
        self.present(alert, animated: true)

        // Attempt automatic reconnection after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, !self.isConnected && !self.isAttemptingConnection else { return }
            print("Attempting automatic reconnection after server disconnection...")
            self.setupWebSocketConnection()
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
