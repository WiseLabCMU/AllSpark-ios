import UIKit
import AVFoundation
import Vision
import CoreImage

class CameraViewController: UIViewController {
    
    // Camera session
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var videoOutput: AVCaptureVideoDataOutput!
    
    // Image processing
    private let context = CIContext()
    private var currentCIImage: CIImage?
    
    // Face detection
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest!
    private var detectedFaces: [VNFaceObservation] = []
    
    // Display layer
    private var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupImageView()
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
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
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
        
        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
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
        
        // Convert to UIImage and display
        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            
            DispatchQueue.main.async { [weak self] in
                self?.imageView.image = uiImage
            }
        }
    }
}
