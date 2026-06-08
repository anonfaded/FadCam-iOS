import AVFoundation
import Foundation

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
    private var isPaused = false
    private var hasStartedSession = false
    private var outputURL: URL?
    private let writeQueue = DispatchQueue(label: "com.fadcam.videorecorder.write", qos: .userInitiated)

    var isRecording: Bool { hasStartedSession }
    var isPausedState: Bool { isPaused }

    func start(to url: URL) throws {
        try writeQueue.sync {
            if hasStartedSession { throw RecorderError.alreadyRecording }
            try startWriterSync(url: url)
            hasStartedSession = true
            isPaused = false
            sessionStarted = false
        }
    }

    func pause() {
        writeQueue.async { [weak self] in self?.isPaused = true }
    }

    func resume() {
        writeQueue.async { [weak self] in self?.isPaused = false }
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
            self.isPaused = false
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
                        completion(.success(finalURL))
                    } else {
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
            guard self.hasStartedSession, !self.isPaused,
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
            guard self.hasStartedSession, !self.isPaused, self.sessionStarted,
                  let writer = self.assetWriter,
                  let input = self.audioInput,
                  writer.status == .writing,
                  input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }
        writeQueue.async(execute: workItem)
    }

    private func startWriterSync(url: URL) throws {
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
