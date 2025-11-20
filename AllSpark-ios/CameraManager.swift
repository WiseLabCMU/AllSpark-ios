import AVFoundation
import Foundation

// https://www.createwithswift.com/camera-capture-setup-in-a-swiftui-app/

class CameraManager: NSObject {
    private let captureSession: AVCaptureSession = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?

    private lazy var systemPreferredCamera: AVCaptureDevice? = {
        return AVCaptureDevice.default(for: .video)
    }()

    private lazy var sessionQueue: DispatchQueue = DispatchQueue(label: "video.preview.session")

    // 1.
    override init() {
        super.init()

        Task {
            await configureSession()
            await startSession()
        }
    }

    // 2.
    private func configureSession() async {
        // 1.
        guard await isAuthorized,
            let systemPreferredCamera,
            let deviceInput = try? AVCaptureDeviceInput(device: systemPreferredCamera)
        else { return }

        // 2.
        captureSession.beginConfiguration()

        // 3.
        defer {
            self.captureSession.commitConfiguration()
        }

        // 4.
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        // 5.
        guard captureSession.canAddInput(deviceInput) else {
            print("Unable to add device input to capture session.")
            return
        }

        // 6.
        guard captureSession.canAddOutput(videoOutput) else {
            print("Unable to add video output to capture session.")
            return
        }

        // 7.
        captureSession.addInput(deviceInput)
        captureSession.addOutput(videoOutput)

    }
    // 3.
    private func startSession() async {
        /// Checking authorization
        guard await isAuthorized else { return }
        /// Start the capture session flow of data
        captureSession.startRunning()
    }

    private var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)

            // Determine if the user previously authorized camera access.
            var isAuthorized = status == .authorized

            // If the system hasn't determined the user's authorization status,
            // explicitly prompt them for approval.
            if status == .notDetermined {
                isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            }

            return isAuthorized
        }
    }

    private var addToPreviewStream: ((CGImage) -> Void)?

    lazy var previewStream: AsyncStream<CGImage> = {
        AsyncStream { continuation in
            addToPreviewStream = { cgImage in
                continuation.yield(cgImage)
            }
        }
    }()

}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let currentFrame = sampleBuffer.cgImage else { return }
        addToPreviewStream?(currentFrame)
    }

}
