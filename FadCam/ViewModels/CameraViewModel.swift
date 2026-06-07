import SwiftUI
import AVFoundation
import Combine
import Photos

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .ready
    @Published var isPaused = false
    @Published var isPermissionGranted = false
    @Published var isAudioPermissionGranted = false
    @Published var isPhotoPermissionGranted = false
    @Published var errorMessage: String?
    @Published var isPreviewActive = false
    @Published var isBatterySaverActive = false
    @Published var currentCamera: AVCaptureDevice.Position = .back
    @Published var isTorchOn = false
    @Published var zoomFactor: CGFloat = 1.0

    let cameraService = CameraService()
    private var recordingStartTime: Date?
    private var timerCancellable: AnyCancellable?

    @Published var elapsedTime: TimeInterval = 0

    var recordingURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fadcamDir = documents.appendingPathComponent("FadCam", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "FadCam_\(formatter.string(from: Date())).mov"
        return fadcamDir.appendingPathComponent(filename)
    }

    var availableStorage: (used: Int64, total: Int64, free: Int64)? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        do {
            let values = try documents.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            if let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
                let used = Int64(total) - Int64(free)
                return (used, Int64(total), Int64(free))
            }
        } catch {}
        return nil
    }

    var estimatedRecordingTime: String {
        guard let storage = availableStorage else { return "Unknown" }
        let freeBytes = storage.free
        let seconds = freeBytes / 1_000_000
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var totalVideos: Int {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FadCam", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return 0 }
        return files.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "mov" || ext == "mp4"
        }.count
    }

    var totalVideosSize: Int64 {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FadCam", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "mov" || ext == "mp4" {
                if let values = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    func checkPermissions() {
        isPermissionGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        isAudioPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        isPhotoPermissionGranted = PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
    }

    func setupCamera() {
        guard isPermissionGranted else { return }
        do {
            try cameraService.setupCamera(position: currentCamera)
        } catch {
            errorMessage = error.localizedDescription
            recordingState = .error(error.localizedDescription)
        }
    }

    func togglePreview() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPreviewActive.toggle()
        }
        if isPreviewActive {
            startSession()
        } else if recordingState != .recording && !isPaused {
            stopSession()
        }
    }

    func startSession() {
        guard isPermissionGranted, isPreviewActive else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.cameraService.session.startRunning()
        }
    }

    func stopSession() {
        cameraService.turnOffTorch()
        isTorchOn = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.cameraService.session.stopRunning()
        }
    }

    func switchCamera() {
        do {
            try cameraService.switchCamera()
            withAnimation { currentCamera = cameraService.currentCamera }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleTorch() {
        cameraService.toggleTorch()
        isTorchOn = cameraService.isTorchOn
    }

    func updateZoom(_ factor: CGFloat) {
        cameraService.setZoom(factor)
        zoomFactor = factor
    }

    func toggleBatterySaver() {
        guard recordingState == .recording else { return }
        withAnimation { isBatterySaverActive.toggle() }
        UIScreen.main.brightness = isBatterySaverActive ? 0.01 : 0.5
    }

    func saveToPhotos(url: URL) {
        guard isPhotoPermissionGranted else { return }
        cameraService.saveToPhotos(url: url)
    }

    func capturePhoto() {
        guard isPreviewActive, isPermissionGranted else { return }
        cameraService.capturePhoto { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let url):
                    if self.isPhotoPermissionGranted {
                        self.cameraService.saveToPhotos(url: url)
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func startRecording() {
        guard recordingState == .ready else { return }
        if !isPreviewActive {
            isPreviewActive = true
            startSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.beginRecording()
            }
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        let url = recordingURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        cameraService.startRecording(to: url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let savedURL):
                    self.recordingState = .ready
                    self.elapsedTime = 0
                    self.isBatterySaverActive = false
                    UIScreen.main.brightness = 0.5
                    if self.isPhotoPermissionGranted { self.cameraService.saveToPhotos(url: savedURL) }
                case .failure(let error):
                    self.recordingState = .error(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        recordingState = .recording
        recordingStartTime = Date()
        startTimer()
    }

    func stopRecording() {
        guard recordingState == .recording else { return }
        cameraService.stopRecording()
        stopTimer()
        isBatterySaverActive = false
        UIScreen.main.brightness = 0.5
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

enum RecordingState: Equatable {
    case ready
    case recording
    case error(String)
}
