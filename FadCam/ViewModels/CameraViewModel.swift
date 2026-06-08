import SwiftUI
import AVFoundation
import Combine
import Photos
import OSLog

private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "camera")

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .ready
    @Published var isPermissionGranted = false
    @Published var isAudioPermissionGranted = false
    @Published var isPhotoPermissionGranted = false
    @Published var errorMessage: String?
    @Published var isPreviewActive = false
    @Published var isBatterySaverActive = false
    @Published var currentCamera: AVCaptureDevice.Position = .back
    @Published var isFrontFlipped = false
    @Published var isTorchOn = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isCameraReady = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var fadCamStorageBytes: Int64 = 0

    let cameraService = CameraService()
    private var recordingStartTime: Date?
    private var timerCancellable: AnyCancellable?
    private var storageRefreshTimer: AnyCancellable?
    private var previewAutoStarted = false

    var recordingURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fadcamDir = documents.appendingPathComponent("FadCam", isDirectory: true)
        let cameraDir = fadcamDir.appendingPathComponent(currentCamera == .back ? "Back" : "Front", isDirectory: true)
        try? FileManager.default.createDirectory(at: cameraDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "FadCam_\(formatter.string(from: Date())).mp4"
        return cameraDir.appendingPathComponent(filename)
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

    var totalMediaCount: Int {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FadCam", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path),
              let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return 0 }
        let trashPath = dir.appendingPathComponent("Trash").path
        var count = 0
        for case let fileURL as URL in enumerator {
            if fileURL.path.hasPrefix(trashPath) { enumerator.skipDescendants(); continue }
            let ext = fileURL.pathExtension.lowercased()
            if ["mov", "mp4", "jpg", "jpeg", "png", "heic"].contains(ext) { count += 1 }
        }
        return count
    }

    var estimatedRecordingTime: String {
        guard let storage = availableStorage else { return "Unknown" }
        let totalSec = storage.free / 1_000_000
        if totalSec >= 86400 {
            let days = totalSec / 86400
            let hrs = (totalSec % 86400) / 3600
            let mins = (totalSec % 3600) / 60
            if hrs > 0 { return "\(days)d \(hrs)h \(mins)m" }
            return "\(days)d \(mins)m"
        }
        let hours = totalSec / 3600
        let mins = (totalSec % 3600) / 60
        let secs = totalSec % 60
        if hours >= 1 { return "\(hours)h \(mins)m \(secs)s" }
        return "\(mins)m \(secs)s"
    }

    override init() {
        super.init()
        startStorageRefreshTimer()
        refreshStorage()
        NotificationCenter.default.addObserver(
            forName: .fadCamMediaChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshStorage()
            }
        }
    }

    deinit {
        storageRefreshTimer?.cancel()
    }

    func refreshStorage() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FadCam", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            fadCamStorageBytes = 0
            return
        }
        var total: Int64 = 0
        let trashPath = dir.appendingPathComponent("Trash").path
        if let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.path.hasPrefix(trashPath) { enumerator.skipDescendants() }
                guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let size = values.fileSize else { continue }
                total += Int64(size)
            }
        }
        fadCamStorageBytes = total
    }

    private func startStorageRefreshTimer() {
        storageRefreshTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStorage()
            }
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
            isCameraReady = true
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
        } else if recordingState != .recording {
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
            isFrontFlipped = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFlip() {
        isFrontFlipped.toggle()
        cameraService.setVideoMirrored(isFrontFlipped ? false : true)
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
                    self.refreshStorage()
                    NotificationCenter.default.post(name: .fadCamMediaChanged, object: nil)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func startRecording() {
        guard recordingState == .ready else { return }
        if !isPreviewActive {
            previewAutoStarted = true
            isPreviewActive = true
            startSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.beginRecording()
            }
            return
        }
        previewAutoStarted = false
        beginRecording()
    }

    private func beginRecording() {
        let url = recordingURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try cameraService.recorder.start(to: url, cameraPosition: currentCamera)
        } catch {
            log.error("Failed to start recorder: \(error.localizedDescription)")
            errorMessage = "Failed to start recorder: \(error.localizedDescription)"
            return
        }
        recordingState = .recording
        if recordingStartTime == nil {
            recordingStartTime = Date()
        }
        elapsedTime = 0
        startTimer()
        log.info("beginRecording — url: \(url.lastPathComponent)")
    }

    func stopRecording() {
        guard recordingState == .recording else { return }
        log.info("Stopping recording...")
        recordingStartTime = nil
        stopTimer()
        isBatterySaverActive = false
        UIScreen.main.brightness = 0.5
        cameraService.recorder.stop { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let savedURL):
                    self.recordingState = .ready
                    self.elapsedTime = 0
                    if self.previewAutoStarted {
                        self.isPreviewActive = false
                        self.stopSession()
                        self.previewAutoStarted = false
                    }
                    if self.isPhotoPermissionGranted {
                        self.cameraService.saveToPhotos(url: savedURL)
                    }
                    self.refreshStorage()
                    NotificationCenter.default.post(name: .fadCamMediaChanged, object: nil)
                case .failure(let error):
                    log.error("Stop failed: \(error.localizedDescription)")
                    self.recordingState = .error(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.elapsedTime = max(0, Date().timeIntervalSince(start))
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
