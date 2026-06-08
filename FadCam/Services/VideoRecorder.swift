import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "recorder")

final class VideoRecorder: @unchecked Sendable {
    enum RecorderError: Error {
        case writerCreationFailed
        case writerNotStarted
        case alreadyRecording
        case notRecording
    }

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var hasStartedSession = false
    private var outputURL: URL?
    private let writeQueue = DispatchQueue(label: "com.fadcam.videorecorder.write", qos: .userInitiated)

    var isRecording: Bool { hasStartedSession }

    func start(to url: URL, cameraPosition: AVCaptureDevice.Position = .back) throws {
        try writeQueue.sync {
            if hasStartedSession { throw RecorderError.alreadyRecording }
            try startWriterSync(url: url, cameraPosition: cameraPosition)
            hasStartedSession = true
            sessionStarted = false
            log.info("Recording started to \(url.lastPathComponent)")
        }
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            guard self.hasStartedSession, let writer = self.assetWriter else {
                completion(.failure(RecorderError.notRecording))
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            let url = self.outputURL
            self.hasStartedSession = false
            writer.finishWriting { [weak self] in
                guard let self else { return }
                let finalURL = url
                let finalStatus = writer.status
                let finalError = writer.error
                self.writeQueue.async {
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    self.sessionStarted = false
                    if finalStatus == .completed, let finalURL {
                        log.info("Recording stopped successfully: \(finalURL.lastPathComponent)")
                        completion(.success(finalURL))
                    } else {
                        log.error("Recording stop failed — status: \(String(describing: finalStatus)), error: \(String(describing: finalError))")
                        completion(.failure(finalError ?? RecorderError.writerNotStarted))
                    }
                }
            }
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.hasStartedSession,
                  let writer = self.assetWriter,
                  let input = self.videoInput,
                  writer.status == .writing,
                  input.isReadyForMoreMediaData else { return }
            if !self.sessionStarted {
                writer.startSession(atSourceTime: pts)
                self.sessionStarted = true
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
        writeQueue.async(execute: workItem)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.hasStartedSession, self.sessionStarted,
                  let writer = self.assetWriter,
                  let input = self.audioInput,
                  writer.status == .writing,
                  input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }
        writeQueue.async(execute: workItem)
    }

    private func startWriterSync(url: URL, cameraPosition: AVCaptureDevice.Position) throws {
        outputURL = url
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mp4) }
        catch { throw RecorderError.writerCreationFailed }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        let rotationAngle: CGFloat = cameraPosition == .front ? -.pi / 2 : .pi / 2
        var t = CGAffineTransform(rotationAngle: rotationAngle)
        if cameraPosition == .front {
            t = CGAffineTransform(scaleX: -1, y: 1).rotated(by: rotationAngle)
        }
        vInput.transform = t
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vInput) { writer.add(vInput) }
        if writer.canAdd(aInput) { writer.add(aInput) }
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerCreationFailed
        }
        assetWriter = writer
        videoInput = vInput
        audioInput = aInput
    }
}
