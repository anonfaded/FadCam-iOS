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
    private var isFrontRecordingMirrored = true

    // Watermark render pipeline
    private var watermarkBufferPool: CVPixelBufferPool?
    private var watermarkPoolWidth  = 0
    private var watermarkPoolHeight = 0
    private let watermarkContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .highQualityDownsample: true
    ])

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
        watermarkBufferPool = nil  // force re-creation on next frame

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
            configureVideoOutputMirroring()
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
        isFrontRecordingMirrored = true
        configureVideoOutputMirroring()
        watermarkBufferPool = nil  // force re-creation on next frame
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

    /// Controls whether front-camera pixels appear left/right mirrored in the
    /// final portrait recording. The watermark is composited after this mirror.
    func setFrontRecordingMirrored(_ mirrored: Bool) {
        isFrontRecordingMirrored = mirrored
    }

    private func configureVideoOutputMirroring() {
        guard let conn = videoDataOutput?.connections.first,
              conn.isVideoMirroringSupported else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = false
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
        if output !== videoDataOutput {
            if output === audioDataOutput { recorder.appendAudio(sampleBuffer) }
            return
        }

        let shouldMirrorCamera = currentCamera == .front && isFrontRecordingMirrored
        let wmSettings = WatermarkSettings.shared
        guard shouldMirrorCamera || wmSettings.isWatermarkShown else {
            recorder.appendVideo(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            recorder.appendVideo(sampleBuffer)
            return
        }

        guard let composited = WatermarkRenderer.buildOutputImage(
            settings: wmSettings,
            from: pixelBuffer,
            mirrorCameraForPortraitDisplay: shouldMirrorCamera
        ) else {
            log.info("Watermark: buildOutputImage returned nil")
            recorder.appendVideo(sampleBuffer)
            return
        }

        guard let watermarkedBuf = renderToWritableBuffer(composited, template: pixelBuffer) else {
            log.info("Watermark: renderToWritableBuffer returned nil")
            recorder.appendVideo(sampleBuffer)
            return
        }

        guard let newSB = createSampleBuffer(from: watermarkedBuf,
                                              timingFrom: sampleBuffer,
                                              copyExtensionsFrom: sampleBuffer) else {
            log.info("Watermark: createSampleBuffer returned nil")
            recorder.appendVideo(sampleBuffer)
            return
        }

        recorder.appendVideo(newSB)
    }

    // MARK: - Watermark Buffer Pool

    private func renderToWritableBuffer(_ image: CIImage, template: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(template)
        let h = CVPixelBufferGetHeight(template)
        let fmt = CVPixelBufferGetPixelFormatType(template)

        if watermarkBufferPool == nil || w != watermarkPoolWidth || h != watermarkPoolHeight {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: fmt,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                kCVPixelBufferBytesPerRowAlignmentKey as String: 16
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            guard let p = pool else { return nil }
            watermarkBufferPool = p
            watermarkPoolWidth = w
            watermarkPoolHeight = h
        }

        var buf: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, watermarkBufferPool!, &buf)
        guard let buffer = buf else { return nil }

        let cropped = image.cropped(to: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        watermarkContext.render(cropped, to: buffer)
        // Attachments are propagated in createSampleBuffer
        return buffer
    }

    /// Creates a CMSampleBuffer from a watermarked pixel buffer.
    /// Builds a fresh format description from the watermarked buffer —
    /// CVBufferPropagateAttachments already copied extensions from the template.
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer,
                                     timingFrom original: CMSampleBuffer,
                                     copyExtensionsFrom template: CMSampleBuffer) -> CMSampleBuffer? {
        // Propagate pixel-level attachments BEFORE creating format description
        if let templateBuf = CMSampleBufferGetImageBuffer(template) {
            CVBufferPropagateAttachments(templateBuf, pixelBuffer)
        }

        var formatDesc: CMFormatDescription?
        let fStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard fStatus == noErr, let desc = formatDesc else {
            log.error("Watermark: CMVideoFormatDescriptionCreateForImageBuffer failed (\(fStatus))")
            return nil
        }

        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(original, at: 0, timingInfoOut: &timing)

        var newSB: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &newSB
        )
        guard status == noErr, let sb = newSB else {
            log.error("Watermark: CMSampleBufferCreateForImageBuffer failed (\(status))")
            return nil
        }

        CMSetAttachment(sb,
                        key: kCMSampleBufferAttachmentKey_DrainAfterDecoding as CFString,
                        value: kCFBooleanFalse,
                        attachmentMode: kCMAttachmentMode_ShouldPropagate)
        return sb
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

        // Apply watermark if enabled
        let wmSettings = WatermarkSettings.shared
        let outputData = WatermarkRenderer.buildWatermarkedPhoto(jpegData: data, settings: wmSettings) ?? data

        do {
            try outputData.write(to: url)
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
