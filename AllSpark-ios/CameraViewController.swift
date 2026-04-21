import UIKit
import AVFoundation
import Vision
import CoreImage
import SwiftUI
import Combine

class CameraViewController: UIViewController, UINavigationControllerDelegate {

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

    // Privacy Filtering
    private var privacyMode: String = "segmentation"
    private var personSegmentationRequest: VNGeneratePersonSegmentationRequest!
    private var personMaskBuffer: CVPixelBuffer?

    // Body Pose Detection
    private var bodyPoseRequest: VNDetectHumanBodyPoseRequest!
    private var detectedBodyPoses: [VNHumanBodyPoseObservation] = []

#if targetEnvironment(simulator)
    private var simulatorPlayer: AVPlayer?
    private var simulatorVideoOutput: AVPlayerItemVideoOutput?
    private var simulatorDisplayLink: CADisplayLink?
#endif

    // Video Recording
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?

    private var adapter: AVAssetWriterInputPixelBufferAdaptor?

    // Add variables for timestamp tracking
    private var frameTimestampsMs: [String] = []
    private var chunkFirstFrameTimestampMs: Int?
    private var frameCount: Int = 0

    private var isRecording = false
    private var sessionAtSourceTime: CMTime?
    private var videoURL: URL?
    private var videoFormat: AVFileType = .mp4 // Default format
    private var recordingDurationMs: Int = AppConstants.Video.defaultChunkDurationMs
    private var autoStopTimer: Timer?
    private var shouldUploadAfterRecording = false
    private let recordingStateLock = NSLock()

    // WebSocket Connection
    private var cancellables = Set<AnyCancellable>()

    // Display layer
    private var imageView: UIImageView!
    private var loadingOverlay: UIView?
    private var activityIndicator: UIActivityIndicatorView?
    private var switchCameraButton: UIButton!
    private var timerLabel: UILabel!
    private var captureModesLabel: UILabel!
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0
    private var connectionHostingController: UIHostingController<ConnectionStatusButton>!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupImageView()
        setupLoadingOverlay()

        setupSwitchCameraButton()
        setupTimerLabel()
        setupConnectionStatusButton()
        setupCamera()
        setupPrivacyFiltering()

        // ConnectionManager is a singleton, so we just ensure it's connected and observe it
        ConnectionManager.shared.connect()
        setupCommandObserver()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Check and request permissions each time the view appears
        // Permissions flow handles initializing camera, and we should start recording if permitted.
        checkAndRequestPermissions()

        // Note: startRecording() will be called from checkAndRequestPermissions completion chain
        // OR we can try to start here if we know we are authorized.
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
             startRecording()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stopRecording()

#if targetEnvironment(simulator)
        simulatorPlayer?.pause()
        simulatorDisplayLink?.isPaused = true
#else
        if let session = captureSession, session.isRunning {
             session.stopRunning()
        }
#endif

        // Close WebSocket connection
        // WebSocket connection is now managed by ConnectionManager (background), so we don't disconnect here.
    }

    private func setupImageView() {
        imageView = UIImageView(frame: view.bounds)
        imageView.contentMode = .scaleAspectFill
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
    }

    private func setupLoadingOverlay() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = AppConstants.Colors.backgroundBaseUI.withAlphaComponent(AppConstants.UI.overlayOpacityDark)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        let label = UILabel()
        label.text = "Initializing Privacy Models..."
        label.textColor = .white
        label.font = .systemFont(ofSize: AppConstants.UI.fontSizeStandard, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.axis = .vertical
        stack.spacing = AppConstants.UI.spacingMedium
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        view.addSubview(overlay)
        self.loadingOverlay = overlay
        self.activityIndicator = indicator
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
        switchCameraButton.backgroundColor = AppConstants.Colors.backgroundBaseUI.withAlphaComponent(AppConstants.UI.buttonBackgroundAlpha)
        switchCameraButton.layer.cornerRadius = AppConstants.UI.cornerRadiusSwitch
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)

        view.addSubview(switchCameraButton)

        NSLayoutConstraint.activate([
            switchCameraButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppConstants.UI.paddingStandard),
            switchCameraButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -AppConstants.UI.paddingStandard),
            switchCameraButton.widthAnchor.constraint(equalToConstant: AppConstants.UI.buttonSizeLarge),
            switchCameraButton.heightAnchor.constraint(equalToConstant: AppConstants.UI.buttonSizeLarge)
        ])

    }

    // Manual upload button removed for security — uploads are server-initiated only

    private var recordingIndicatorContainer: UIView!

    private func setupTimerLabel() {
        // Container for background
        recordingIndicatorContainer = UIView()
        recordingIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        recordingIndicatorContainer.backgroundColor = AppConstants.Colors.backgroundBaseUI.withAlphaComponent(AppConstants.UI.buttonBackgroundAlpha)
        recordingIndicatorContainer.layer.cornerRadius = AppConstants.UI.cornerRadiusSmall
        recordingIndicatorContainer.clipsToBounds = true
        recordingIndicatorContainer.isHidden = true // Initially hidden
        view.addSubview(recordingIndicatorContainer)

        // Stack View
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = AppConstants.UI.spacingSmall
        stackView.alignment = .center
        stackView.distribution = .fill
        recordingIndicatorContainer.addSubview(stackView)

        // Recording Icon (Red Circle)
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let image = UIImage(systemName: "circle.fill") {
            iconView.image = image
        }
        iconView.tintColor = .red
        iconView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(iconView)

        // Text Stack View for Timer and Modes Label
        let textStackView = UIStackView()
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.spacing = AppConstants.UI.spacingTiny
        textStackView.alignment = .leading

        // Timer Label
        timerLabel = UILabel()
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = "00:00"
        timerLabel.textColor = .red // User requested red
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: AppConstants.UI.fontSizeTimer, weight: .bold)
        textStackView.addArrangedSubview(timerLabel)

        captureModesLabel = UILabel()
        captureModesLabel.translatesAutoresizingMaskIntoConstraints = false
        captureModesLabel.text = ""
        captureModesLabel.textColor = .white
        captureModesLabel.font = UIFont.systemFont(ofSize: AppConstants.UI.fontSizeModes, weight: .medium)
        captureModesLabel.numberOfLines = 1
        textStackView.addArrangedSubview(captureModesLabel)

        stackView.addArrangedSubview(textStackView)

        NSLayoutConstraint.activate([
            recordingIndicatorContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppConstants.UI.paddingStandard),
            recordingIndicatorContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // Flex height based on content
            recordingIndicatorContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: AppConstants.UI.indicatorMinHeight),

            // StackView constraints inside container with padding
            stackView.leadingAnchor.constraint(equalTo: recordingIndicatorContainer.leadingAnchor, constant: AppConstants.UI.paddingSmall),
            stackView.trailingAnchor.constraint(equalTo: recordingIndicatorContainer.trailingAnchor, constant: -AppConstants.UI.paddingSmall),
            stackView.topAnchor.constraint(equalTo: recordingIndicatorContainer.topAnchor, constant: AppConstants.UI.paddingTiny),
            stackView.bottomAnchor.constraint(equalTo: recordingIndicatorContainer.bottomAnchor, constant: -AppConstants.UI.paddingTiny),

            // Icon size
            iconView.widthAnchor.constraint(equalToConstant: AppConstants.UI.iconSizeSmall),
            iconView.heightAnchor.constraint(equalToConstant: AppConstants.UI.iconSizeSmall)
        ])
    }

    private func setupConnectionStatusButton() {
        let buttonView = ConnectionStatusButton()
        connectionHostingController = UIHostingController(rootView: buttonView)
        connectionHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        connectionHostingController.view.backgroundColor = .clear

        addChild(connectionHostingController)
        view.addSubview(connectionHostingController.view)
        connectionHostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            connectionHostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppConstants.UI.paddingStandard),
            connectionHostingController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: AppConstants.UI.offsetTrailingStatus)
        ])
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
            case "uploadTimeRange":
                guard let startTime = json["startTime"] as? Double,
                      let endTime = json["endTime"] as? Double else {
                    print("Invalid uploadTimeRange parameters")
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    self.handleUploadTimeRange(startTime: startTime, endTime: endTime)
                }

            default:
                print("Unknown command: \(command)")
            }
        } else if let status = json["status"] as? String {
            // Handle status messages
            if status == "success" {
                // Optional: show a small toast instead of an alert to avoid interrupting
                print("Server confirmed upload success")
            }
        }
    }

    private func handleUploadTimeRange(startTime: Double, endTime: Double) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)

            let recordingFiles = fileURLs.filter { $0.lastPathComponent.hasPrefix("chunk_") && $0.pathExtension == "mp4" }

            print("Found \(recordingFiles.count) recordings. Checking overlap with \(startTime) - \(endTime)")

            for fileURL in recordingFiles {
                // Parse timestamp from filename: chunk_{timestampMs}.mp4
                let parts = fileURL.deletingPathExtension().lastPathComponent.components(separatedBy: "_")
                if let lastPart = parts.last, let parsedTimestamp = Double(lastPart) {
                    let fileTimestamp = parsedTimestamp / 1000.0

                    // We assume the file duration is approximately the chunk duration
                    // For better accuracy, we could use AVAsset, but that's heavier.
                    // Let's rely on the config duration for estimation or just the start time.
                    // A file 'covers' [timestamp, timestamp + chunkDuration]
                    // We upload if there is ANY overlap.

                    // Get current chunk duration from config
                    var chunkDuration = Double(AppConstants.Video.defaultChunkDurationMs) / 1000.0
                    if let config = ConnectionManager.shared.clientConfig,
                       let durationMs = config["videoChunkDurationMs"] as? Int {
                        chunkDuration = Double(durationMs) / 1000.0
                    }

                    let fileEndTime = fileTimestamp + chunkDuration

                    // Check intersection
                    // File Start < Request End AND File End > Request Start
                    if fileTimestamp < endTime && fileEndTime > startTime {
                        print("Uploading file matching range: \(fileURL.lastPathComponent)")
                        uploadVideo(at: fileURL)

                        let urlName = fileURL.deletingPathExtension().lastPathComponent
                        let timestampsFilename = urlName.replacingOccurrences(of: "chunk_", with: "timestamps_") + ".txt"
                        let timestampsURL = fileURL.deletingLastPathComponent().appendingPathComponent(timestampsFilename)
                        if FileManager.default.fileExists(atPath: timestampsURL.path) {
                            uploadVideo(at: timestampsURL)
                        }
                    }
                }
            }
        } catch {
            print("Error scanning recordings: \(error)")
        }
    }

    @objc private func switchCamera() {
        if isRecording {
            // Cancel the automatic chunk timer to prevent race conditions
            autoStopTimer?.invalidate()

            // Stop current chunk
            stopRecordingChunk { [weak self] in
                // Switch camera and restart recording on main thread
                DispatchQueue.main.async {
                    self?.configureCameraSwitch()
                    self?.startRecordingChunk()
                }
            }
        } else {
            configureCameraSwitch()
        }
    }

    private func configureCameraSwitch() {
        guard captureSession != nil else { return }
        captureSession.beginConfiguration()

        // Remove existing video input
        if let currentInput = captureSession.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }) {
            captureSession.removeInput(currentInput)
        }

        // Toggle position
        currentCameraPosition = (currentCameraPosition == .front) ? .back : .front

        // Save preference
        UserDefaults.standard.set(currentCameraPosition == .front ? "front" : "back", forKey: "cameraPosition")

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

    // toggleRecording removed

    private func startRecording() {
        // Start UI Timer Loop
        // Note: recordingDuration is reset in startRecordingChunk

        startRecordingChunk()

        recordingTimer?.invalidate()
        DispatchQueue.main.async {
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.recordingDuration += 1
                self.updateTimerDisplay()
            }
        }
    }

    private func startRecordingChunk() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Load video format preference from UserDefaults
        let formatString = UserDefaults.standard.string(forKey: "videoFormat") ?? "mp4"
        let fileExtension = formatString == "mov" ? "mov" : "mp4"
        let fileType: AVFileType = formatString == "mov" ? .mov : .mp4

        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
        let videoName = "tmp_recording_\(timestampMs).\(fileExtension)"
        videoURL = documentsPath.appendingPathComponent(videoName)

        guard let videoURL = videoURL else { return }

        // Remove existing file if necessary
        try? FileManager.default.removeItem(at: videoURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: fileType)

            var outputWidth = videoRotationAngle == 0 || videoRotationAngle == 180 ? AppConstants.Video.dimensionHigh : AppConstants.Video.dimensionLow
            var outputHeight = videoRotationAngle == 0 || videoRotationAngle == 180 ? AppConstants.Video.dimensionLow : AppConstants.Video.dimensionHigh

#if targetEnvironment(simulator)
            if let presentationSize = simulatorPlayer?.currentItem?.presentationSize, presentationSize.width > 0 {
                outputWidth = Int(presentationSize.width)
                outputHeight = Int(presentationSize.height)
            }
#endif

            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight
            ]

            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true

            if let input = assetWriterInput, assetWriter!.canAdd(input) {
                assetWriter!.add(input)

                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: outputWidth,
                    kCVPixelBufferHeightKey as String: outputHeight
                ]

                adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)

                // Setup audio writer input
                let audioOutputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: AppConstants.Audio.sampleRate,
                    AVEncoderBitRateKey: AppConstants.Audio.bitRate
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

                recordingStateLock.lock()
                isRecording = true
                sessionAtSourceTime = nil
                chunkFirstFrameTimestampMs = nil
                frameTimestampsMs.removeAll()
                frameCount = 0
                recordingStateLock.unlock()

                print("Started recording chunk: \(videoName)")

                // Check capture modes
                var modes: [String] = []
                if self.assetWriterInput != nil { modes.append("Video") }
                if self.audioWriterInput != nil { modes.append("Audio") }
                let modesText = "Capturing: " + modes.joined(separator: " + ")

                // Reset UI Timer for new chunk
                DispatchQueue.main.async { [weak self] in
                    self?.captureModesLabel.text = modesText
                    self?.recordingDuration = 0
                    self?.updateTimerDisplay()
                    self?.recordingIndicatorContainer.isHidden = false
                }

                // Chunk Timer
                var chunkMs = AppConstants.Video.defaultChunkDurationMs
                if let config = ConnectionManager.shared.clientConfig,
                   let ms = config["videoChunkDurationMs"] as? Int {
                    chunkMs = ms
                }
                let chunkSeconds = Double(chunkMs) / 1000.0

                // Schedule next chunk
                DispatchQueue.main.async { [weak self] in
                    self?.autoStopTimer?.invalidate()
                    print("Scheduling timer for \(chunkSeconds)s on thread: \(Thread.current.description)")
                    self?.autoStopTimer = Timer.scheduledTimer(withTimeInterval: chunkSeconds, repeats: false) { [weak self] _ in
                        print("Timer fired! Chunk complete, cycling...")
                        self?.cycleRecordingChunk()
                    }
                }
            } else {
                print("Failed to add video input to asset writer")
            }
        } catch {
            print("Failed to setup asset writer: \(error)")
        }
    }

    private func cycleRecordingChunk() {
        guard isRecording else { return }

        // Stop current
        stopRecordingChunk { [weak self] in
            // Start next immediately
            self?.startRecordingChunk()
        }
    }

    // User triggered stop
    private func stopRecording() {
        // Cancel the cycling timer
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        recordingStateLock.lock()
        isRecording = false // This prevents cycleRecordingChunk from starting a new one
        recordingStateLock.unlock()

        // Stop UI Timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingIndicatorContainer.isHidden = true
        DispatchQueue.main.async {
            self.captureModesLabel.text = ""
        }

        stopRecordingChunk(completion: nil)
    }

    private func stopRecordingChunk(completion: (() -> Void)? = nil) {
        // If we are already not recording (e.g. user pressed stop), we might still need to close the writer
        // but 'isRecording' is the flag for the *session*.
        // We need to be careful. usage:
        // cycle: isRecording=true. stopChunk -> startChunk.
        // user stop: isRecording=false. stopChunk.

        // Note: isRecording is used in recordVideoFrame guards.
        // If we set isRecording=false in stopRecording, then recordVideoFrame stops sending frames.
        // Then we call stopRecordingChunk to close the writer.

        recordingStateLock.lock()
        // Ensure we stop accepting frames immediately
        isRecording = false

        guard let writer = assetWriter else {
            recordingStateLock.unlock()
            completion?()
            return
        }
        recordingStateLock.unlock()

        // recordingTimer is now managed by stopRecording()

        if writer.status == .failed {
            print("Asset writer status is failed: \(String(describing: writer.error))")
        } else if writer.status == .completed {
             print("Asset writer already completed.")
        } else if writer.status == .cancelled {
             print("Asset writer cancelled.")
        } else {
             print("Finishing asset writer... Status: \(writer.status.rawValue)")
        }

        assetWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()

        // We need to capture the URL locally before nil-ing out
        let savedURL = videoURL

        recordingStateLock.lock()
        let chunkTimeMs = chunkFirstFrameTimestampMs ?? Int(Date().timeIntervalSince1970 * 1000)
        let timestampsData = frameTimestampsMs.joined(separator: "\n")
        recordingStateLock.unlock()

        writer.finishWriting { [weak self] in
            print("Finish writing completion block entered.")
            guard let self = self else {
                print("Self is nil in finishWriting completion.")
                completion?()
                return
            }

            if let url = savedURL {
               // Rename the file to chunk_{timestamp}.mp4
               let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
               let format = url.pathExtension
               let newFilename = "chunk_\(chunkTimeMs).\(format)"
               let finalURL = documentsPath.appendingPathComponent(newFilename)

               try? FileManager.default.removeItem(at: finalURL)
               do {
                   try FileManager.default.moveItem(at: url, to: finalURL)
               } catch {
                   print("Error renaming video chunk: \(error)")
               }

               // Write timestamps file
               let timestampsFilename = "timestamps_\(chunkTimeMs).txt"
               let timestampsURL = documentsPath.appendingPathComponent(timestampsFilename)
               try? timestampsData.write(to: timestampsURL, atomically: true, encoding: .utf8)

               print("Chunk saved: \(newFilename) and \(timestampsFilename)")

               let endTime = Date().timeIntervalSince1970
               let startTime = Double(chunkTimeMs) / 1000.0
               // Determine camera from original name since we drop it in final name
               let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: "_")
               let camera = parts.count > 2 ? parts[parts.count - 2] : "unknown" // "front" or "back"

               let urlToProcess = finalURL

               DispatchQueue.global(qos: .utility).async {
                   var size: Int64 = 0
                   if let attr = try? FileManager.default.attributesOfItem(atPath: urlToProcess.path) {
                       size = attr[.size] as? Int64 ?? 0
                   }

                   let asset = AVURLAsset(url: urlToProcess)
                   var fps: Double = AppConstants.Video.defaultFPS
                   var width: Double = 0
                   var height: Double = 0

                   Task {
                       if let tracks = try? await asset.loadTracks(withMediaType: .video),
                          let track = tracks.first {
                           fps = Double(try await track.load(.nominalFrameRate))
                           let naturalSize = try await track.load(.naturalSize)
                           let preferredTransform = try await track.load(.preferredTransform)
                           let tSize = naturalSize.applying(preferredTransform)
                           width = Double(abs(Int(tSize.width)))
                           height = Double(abs(Int(tSize.height)))
                       }

                       let dimensions: [String: Double] = [
                           "width": width,
                           "height": height
                       ]

                       await ConnectionManager.shared.sendChunkSavedMessage(
                           startTime: startTime,
                           endTime: endTime,
                           camera: camera,
                           size: size,
                           format: format,
                           fps: fps,
                           dimensions: dimensions
                       )
                   }

               }
            }

            self.recordingStateLock.lock()
            self.assetWriter = nil
            self.assetWriterInput = nil
            self.audioWriterInput = nil
            self.adapter = nil
            self.recordingStateLock.unlock()

            completion?()
        }

        // Manage storage after saving
        ConnectionManager.shared.manageVideoStorage()
    }

    private func setupCamera() {
        // Camera initialization will be handled in checkAndRequestPermissions
        setupPrivacyFiltering()
    }

    private func setupAudioInput() {
        guard captureSession != nil else { return }
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
#if targetEnvironment(simulator)
        guard simulatorPlayer == nil else {
            simulatorPlayer?.play()
            simulatorDisplayLink?.isPaused = false
            return
        }
        setupSimulatorVideoLoop()
        return
#else
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

#endif
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
        guard captureSession != nil else { return }
        // Find the video input, not just the first input (which could be audio)
        if let videoCaptureDevice = captureSession.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }) {
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

                    // For now, don't mirror front camera, let's keep each a view accurate to what rthe camera will save.
                    // if connection.isVideoMirroringSupported {
                    //     connection.isVideoMirrored = (currentCameraPosition == .front)
                    // }
                 }
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateVideoOrientation()
        }
    }

    private func setupPrivacyFiltering() {
        self.privacyMode = UserDefaults.standard.string(forKey: "privacyMode") ?? "segmentation"

        let segRequest = VNGeneratePersonSegmentationRequest()
        segRequest.qualityLevel = .balanced // Balanced is much faster for real-time video than .accurate
        self.personSegmentationRequest = segRequest

        self.bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    }

    private func applyPrivacyBlur(to image: CIImage) -> CIImage {
        if privacyMode == "segmentation" {
            guard let maskBuffer = personMaskBuffer else { return image }
            let maskImage = CIImage(cvPixelBuffer: maskBuffer)

            let scaleX = image.extent.width / maskImage.extent.width
            let scaleY = image.extent.height / maskImage.extent.height
            let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            if let pixelateFilter = CIFilter(name: "CIPixellate") {
                pixelateFilter.setValue(image, forKey: kCIInputImageKey)
                pixelateFilter.setValue(NSNumber(value: Float(AppConstants.Privacy.pixelationScale)), forKey: kCIInputScaleKey)
                if let blurredImage = pixelateFilter.outputImage {
                    let clampedBlur = blurredImage.cropped(to: image.extent)
                    if let blendFilter = CIFilter(name: "CIBlendWithRedMask") {
                        blendFilter.setValue(clampedBlur, forKey: kCIInputImageKey)
                        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
                        blendFilter.setValue(scaledMask, forKey: kCIInputMaskImageKey)
                        if let output = blendFilter.outputImage { return output }
                    }
                }
            }
            return image
        } else {
            var outputImage = image
            let imageSize = image.extent.size

            for pose in detectedBodyPoses {
                // Find bounding box for all confident body joints (like ankles, knees)
                guard let points = try? pose.recognizedPoints(.all) else { continue }
                var minX: CGFloat = 1.0, minY: CGFloat = 1.0
                var maxX: CGFloat = 0.0, maxY: CGFloat = 0.0
                var validPoints = 0

                for (_, point) in points where point.confidence > 0.2 {
                    minX = min(minX, point.location.x)
                    minY = min(minY, point.location.y)
                    maxX = max(maxX, point.location.x)
                    maxY = max(maxY, point.location.y)
                    validPoints += 1
                }

                guard validPoints > 0 else { continue }

                let x = minX * imageSize.width
                let y = minY * imageSize.height
                let width = (maxX - minX) * imageSize.width
                let height = (maxY - minY) * imageSize.height

                // Expand the box slightly for full coverage of the limbs
                let expansion: CGFloat = 0.5
                let expandedX = max(0, x - width * expansion)
                let expandedY = max(0, y - height * expansion)
                let expandedWidth = min(imageSize.width - expandedX, width * (1 + 2 * expansion))
                let expandedHeight = min(imageSize.height - expandedY, height * (1 + 2 * expansion))

                let poseRect = CGRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)

                // Pixelate the bounding box
                if let pixelateFilter = CIFilter(name: "CIPixellate") {
                    let poseCrop = outputImage.cropped(to: poseRect)
                    pixelateFilter.setValue(poseCrop, forKey: kCIInputImageKey)
                    // Set center to the middle of the crop to align blocks locally
                    let center = CIVector(x: poseRect.midX, y: poseRect.midY)
                    pixelateFilter.setValue(center, forKey: kCIInputCenterKey)
                    pixelateFilter.setValue(NSNumber(value: Float(AppConstants.Privacy.pixelationScale)), forKey: kCIInputScaleKey)

                    if let blurredOutput = pixelateFilter.outputImage {
                        let croppedBlur = blurredOutput.cropped(to: poseRect)
                        outputImage = croppedBlur.composited(over: outputImage)
                    }
                }
            }

            return outputImage
        }
    }

#if targetEnvironment(simulator)
    private func setupSimulatorVideoLoop() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsPath.appendingPathComponent("demo_video.mp4")

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Simulator Video Missing", message: "Please drag 'demo_video.mp4' into the iOS Simulator's AllSpark-ios folder using the macOS Finder or Simulator Files app.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
            return
        }

        let player = AVPlayer(url: videoURL)
        player.actionAtItemEnd = .none

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        player.currentItem?.add(output)

        simulatorPlayer = player
        simulatorVideoOutput = output

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }

        simulatorDisplayLink = CADisplayLink(target: self, selector: #selector(simulatorDisplayLinkFired))
        simulatorDisplayLink?.add(to: .main, forMode: .common)

        player.play()
    }

    @objc private func simulatorDisplayLinkFired() {
        guard let output = simulatorVideoOutput else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }

        var presentationItemTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &presentationItemTime) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:])
        do {
            if privacyMode == "segmentation" {
                try handler.perform([personSegmentationRequest])
                if let result = personSegmentationRequest.results?.first as? VNPixelBufferObservation {
                    self.personMaskBuffer = result.pixelBuffer
                }
            } else {
                try handler.perform([bodyPoseRequest])
                self.detectedBodyPoses = bodyPoseRequest.results ?? []
            }
        } catch { }

        let processedImage = applyPrivacyBlur(to: ciImage)

        // Use monotonic host clock because video file will randomly jump to 0.0s causing AVAssetWriter to fail
        let currentHostTime = CMClockGetTime(CMClockGetHostTimeClock())
        recordVideoFrame(processedImage, timestamp: currentHostTime)

        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            self.imageView.image = uiImage

            if let overlay = self.loadingOverlay {
                self.loadingOverlay = nil
                UIView.animate(withDuration: 0.3, animations: { [weak overlay] in
                    overlay?.alpha = 0
                }) { [weak overlay] _ in
                    overlay?.removeFromSuperview()
                }
            }
        }
    }
#endif

    private func recordAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        recordingStateLock.lock()
        defer { recordingStateLock.unlock() }

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
        // 1. Quick check
        recordingStateLock.lock()
        let shouldRecord = isRecording
        recordingStateLock.unlock()

        guard shouldRecord else { return }

        // Use the adapter's pixel buffer pool when available to avoid
        // per-frame heap allocation. Falls back to CVPixelBufferCreate.
        var pixelBuffer: CVPixelBuffer?
        if let pool = adapter?.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        }
        if pixelBuffer == nil {
            let attrs = [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
            ] as CFDictionary

            let width = Int(image.extent.width)
            let height = Int(image.extent.height)

            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        }

        if let buffer = pixelBuffer {
            context.render(image, to: buffer)

            // 2. Append (lock)
            recordingStateLock.lock()
            defer { recordingStateLock.unlock() }

            // Re-check state
            guard isRecording, let adapter = adapter, let input = assetWriterInput, input.isReadyForMoreMediaData else {
                return
            }

            // Calculate wall-clock epoch timestamp in ms for this frame
            let ntpTimeMs = Int((Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime + timestamp.seconds) * 1000)

            if chunkFirstFrameTimestampMs == nil {
                chunkFirstFrameTimestampMs = ntpTimeMs // The exact timestamp of the chunk
            }

            if sessionAtSourceTime == nil {
                print("Starting session at \(timestamp.seconds)")
                sessionAtSourceTime = timestamp
                assetWriter?.startSession(atSourceTime: timestamp)
            }

            let success = adapter.append(buffer, withPresentationTime: timestamp)
            if success {
                frameTimestampsMs.append("\(frameCount) : \(ntpTimeMs)")
                frameCount += 1
            }
            if !success {
                print("Failed to append buffer. Writer status: \(String(describing: assetWriter?.status.rawValue)) Error: \(String(describing: assetWriter?.error))")
            }
        } else {
            print("Failed to create CVPixelBuffer")
        }
    }

    // MARK: - Helper Methods
}

extension CameraViewController {
    // Manual upload (promptForUpload / documentPicker) removed for security.
    // Uploads are server-initiated only via handleUploadTimeRange.

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

        // Perform privacy detection
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:])

        do {
            if privacyMode == "segmentation" {
                try handler.perform([personSegmentationRequest])
                if let result = personSegmentationRequest.results?.first as? VNPixelBufferObservation {
                    self.personMaskBuffer = result.pixelBuffer
                }
            } else {
                try handler.perform([bodyPoseRequest])
                self.detectedBodyPoses = bodyPoseRequest.results ?? []
            }
        } catch {
            print("Failed to perform privacy detection: \(error)")
        }

        // Apply blur to humans
        let processedImage = applyPrivacyBlur(to: ciImage)

        // Record output
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        recordVideoFrame(processedImage, timestamp: timestamp)

        // Convert to UIImage and display
        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.imageView.image = uiImage

                if let overlay = self.loadingOverlay {
                    self.loadingOverlay = nil // Nullify immediately to prevent duplicate animations
                    UIView.animate(withDuration: 0.3, animations: { [weak overlay] in
                        overlay?.alpha = 0
                    }) { [weak overlay] _ in
                        overlay?.removeFromSuperview()
                    }
                }
            }
        }
    }
}
