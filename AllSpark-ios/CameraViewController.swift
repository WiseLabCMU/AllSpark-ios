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

    // Display layer
    private var imageView: UIImageView!
    private var recordButton: UIButton!
    private var switchCameraButton: UIButton!
    private var uploadButton: UIButton!
    private var timerLabel: UILabel!
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        setupImageView()
        setupRecordButton()

        setupSwitchCameraButton()
        setupUploadButton()
        setupTimerLabel()
        setupCamera()
        setupFaceDetection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession.isRunning {
            captureSession.stopRunning()
        }
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
                 recordButton.tintColor = .white
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
        let videoName = "recording_\(Date().timeIntervalSince1970).mov"
        videoURL = documentsPath.appendingPathComponent(videoName)

        guard let videoURL = videoURL else { return }

        // Remove existing file if necessary
        try? FileManager.default.removeItem(at: videoURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mov)

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
        var hostString = UserDefaults.standard.string(forKey: "serverHost") ?? "localhost:3000"

        // Opportunistic protocol handling
        if !hostString.lowercased().hasPrefix("http://") && !hostString.lowercased().hasPrefix("https://") {
            hostString = "http://" + hostString
        }

        guard let serverURL = URL(string: hostString)?.appendingPathComponent("upload") else {
            print("Invalid server URL constructed from: \(hostString)")
            let alert = UIAlertController(title: "Configuration Error", message: "Invalid Server Host: \(hostString)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let videoData: Data
        do {
            videoData = try Data(contentsOf: fileURL)
        } catch {
            print("Failed to load video data: \(error)")
            return
        }

        var body = Data()
        let filename = fileURL.lastPathComponent
        let mimetype = "video/quicktime" // Assuming valid type usually

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    let alert = UIAlertController(title: "Upload Failed", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let alert = UIAlertController(title: "Success", message: "Video uploaded successfully!", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                } else {
                     let alert = UIAlertController(title: "Upload Failed", message: "Server returned an error.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
        task.resume()
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
