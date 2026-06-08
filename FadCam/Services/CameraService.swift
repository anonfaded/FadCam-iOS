import AVFoundation
import Photos
import OSLog

private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "camera")

protocol CameraServiceSampleDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutputVideo sampleBuffer: CMSampleBuffer)
    func cameraService(_ service: CameraService, didOutputAudio sampleBuffer: CMSampleBuffer)
}

class CameraService: NSObject {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let recorder = VideoRecorder()

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?

    private var photoCompletion: ((Result<URL, Error>) -> Void)?

    private(set) var currentCamera: AVCaptureDevice.Position = .back

    override init() {
        super.init()
        session.sessionPreset = .high
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    func setupCamera(position: AVCaptureDevice.Position = .back) throws {
        log.info("Setting up camera — position: \(position == .back ? "back" : "front")")
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.filter { $0 !== photoOutput }.forEach { session.removeOutput($0) }
        videoDeviceInput = nil
        audioDeviceInput = nil
        videoDataOutput = nil
        audioDataOutput = nil

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noCameraAvailable
        }
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(videoInput)
        videoDeviceInput = videoInput
        currentCamera = position

        if let microphone = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                audioDeviceInput = audioInput
            }
        }

        let vDataOutput = AVCaptureVideoDataOutput()
        vDataOutput.alwaysDiscardsLateVideoFrames = true
        vDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        vDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.fadcam.video.samples", qos: .userInitiated))
        if session.canAddOutput(vDataOutput) {
            session.addOutput(vDataOutput)
            videoDataOutput = vDataOutput
        }

        let aDataOutput = AVCaptureAudioDataOutput()
        aDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.fadcam.audio.samples", qos: .userInitiated))
        if session.canAddOutput(aDataOutput) {
            session.addOutput(aDataOutput)
            audioDataOutput = aDataOutput
        }
    }

    func switchCamera() throws {
        let newPosition: AVCaptureDevice.Position = currentCamera == .back ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            throw CameraError.noCameraAvailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let existingInput = videoDeviceInput {
            session.removeInput(existingInput)
        }
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            if let oldInput = videoDeviceInput { session.addInput(oldInput) }
            throw CameraError.cannotAddInput
        }
        session.addInput(videoInput)
        videoDeviceInput = videoInput
        currentCamera = newPosition
    }

    func saveToPhotos(url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { _, error in
            if let error = error { print("Failed to save to Photos: \(error)") }
        }
    }

    var hasTorch: Bool { videoDeviceInput?.device.hasTorch ?? false }
    var isTorchOn: Bool { videoDeviceInput?.device.torchMode == .on }

    func toggleTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        } catch { print("Torch toggle failed: \(error)") }
    }

    func turnOffTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch, device.torchMode == .on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {}
    }

    var minZoomFactor: CGFloat { videoDeviceInput?.device.minAvailableVideoZoomFactor ?? 1.0 }
    var maxZoomFactor: CGFloat { videoDeviceInput?.device.activeFormat.videoMaxZoomFactor ?? 5.0 }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(minZoomFactor, min(maxZoomFactor, factor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
    }

    var currentZoom: CGFloat { videoDeviceInput?.device.videoZoomFactor ?? 1.0 }

    func setVideoMirrored(_ mirrored: Bool) {
        guard let conn = videoDataOutput?.connections.first else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = mirrored
    }

    func capturePhoto(completion: @escaping (Result<URL, Error>) -> Void) {
        photoCompletion = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func fadShotDirectory(for position: AVCaptureDevice.Position) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fadcamDir = documents.appendingPathComponent("FadCam", isDirectory: true)
        let fadshotDir = fadcamDir.appendingPathComponent("FadShot", isDirectory: true)
        let cameraDir = fadshotDir.appendingPathComponent(position == .back ? "Back" : "Front", isDirectory: true)
        try? FileManager.default.createDirectory(at: cameraDir, withIntermediateDirectories: true)
        return cameraDir
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoDataOutput {
            recorder.appendVideo(sampleBuffer)
        } else if output === audioDataOutput {
            recorder.appendAudio(sampleBuffer)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoCompletion?(.failure(error))
            photoCompletion = nil
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            photoCompletion?(.failure(CameraError.cannotAddInput))
            photoCompletion = nil
            return
        }
        let dir = fadShotDirectory(for: currentCamera)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "FadShot_\(formatter.string(from: Date())).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            photoCompletion?(.success(url))
        } catch {
            photoCompletion?(.failure(error))
        }
        photoCompletion = nil
    }
}

enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "No camera available on this device."
        case .cannotAddInput: return "Unable to connect camera to capture session."
        }
    }
}
