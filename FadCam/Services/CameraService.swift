import AVFoundation
import Photos

class CameraService: NSObject {
    let session = AVCaptureSession()
    let movieFileOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    private(set) var currentCamera: AVCaptureDevice.Position = .back

    override init() {
        super.init()
        session.sessionPreset = .high
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
        }
    }

    func setupCamera(position: AVCaptureDevice.Position = .back) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        videoDeviceInput = nil
        audioDeviceInput = nil

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
            if let oldInput = videoDeviceInput {
                session.addInput(oldInput)
            }
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
            if let error = error {
                print("Failed to save to Photos: \(error)")
            }
        }
    }

    var hasTorch: Bool {
        videoDeviceInput?.device.hasTorch ?? false
    }

    var isTorchOn: Bool {
        videoDeviceInput?.device.torchMode == .on
    }

    func toggleTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        } catch {
            print("Torch toggle failed: \(error)")
        }
    }

    func turnOffTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch, device.torchMode == .on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {}
    }

    var minZoomFactor: CGFloat {
        videoDeviceInput?.device.minAvailableVideoZoomFactor ?? 1.0
    }

    var maxZoomFactor: CGFloat {
        videoDeviceInput?.device.activeFormat.videoMaxZoomFactor ?? 5.0
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(minZoomFactor, min(maxZoomFactor, factor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
    }

    var currentZoom: CGFloat {
        videoDeviceInput?.device.videoZoomFactor ?? 1.0
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        recordingCompletion = completion
        movieFileOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() {
        movieFileOutput.stopRecording()
    }

    var isRecording: Bool {
        movieFileOutput.isRecording
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            recordingCompletion?(.failure(error))
        } else {
            recordingCompletion?(.success(outputFileURL))
        }
        recordingCompletion = nil
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
