import SwiftUI
import AVFoundation
import Photos
import Combine

@MainActor
final class RecordsViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isLoading = false
    @Published var totalStorageBytes: Int64 = 0
    @Published var photosPermissionGranted: Bool = false

    private let viewedKey = "FadCam.viewedRecordings"
    private var viewedURLs: Set<String> = []

    private let recordingsDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("FadCam", isDirectory: true)
    }()

    private     let fadShotDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("FadCam/FadShot", isDirectory: true)
    }()

    @Published var trashItemCount: Int = 0

    let trashVM = TrashViewModel()

    init() {
        loadViewedSet()
        checkPhotosPermission()
        NotificationCenter.default.addObserver(
            forName: .fadCamMediaChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.loadRecordings()
            }
        }
    }

    private func loadViewedSet() {
        if let arr = UserDefaults.standard.array(forKey: viewedKey) as? [String] {
            viewedURLs = Set(arr)
        }
    }

    private func persistViewedSet() {
        UserDefaults.standard.set(Array(viewedURLs), forKey: viewedKey)
    }

    func checkPhotosPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        photosPermissionGranted = (status == .authorized || status == .limited)
    }

    func requestPhotosPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        let granted = (status == .authorized || status == .limited)
        photosPermissionGranted = granted
        return granted
    }

    func loadRecordings() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else {
            recordings = []
            totalStorageBytes = 0
            return
        }

        do {
            var results: [Recording] = []
            var totalSize: Int64 = 0

            let videoExtensions = Set(["mov", "mp4"])
            let photoExtensions = Set(["jpg", "jpeg", "png", "heic"])

            let backVideoDir = recordingsDirectory.appendingPathComponent("Back")
            let frontVideoDir = recordingsDirectory.appendingPathComponent("Front")

            for videoDir in [backVideoDir, frontVideoDir] {
                guard FileManager.default.fileExists(atPath: videoDir.path) else { continue }
                let files = try FileManager.default.contentsOfDirectory(
                    at: videoDir,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
                )
                for fileURL in files where videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                    let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                    let date = resourceValues?.creationDate ?? Date()
                    let fileSize = Int64(resourceValues?.fileSize ?? 0)
                    totalSize += fileSize
                    let asset = AVAsset(url: fileURL)
                    let duration = asset.duration.seconds.isNaN ? 0 : asset.duration.seconds
                    results.append(Recording(
                        url: fileURL, filename: fileURL.lastPathComponent,
                        date: date, duration: duration, fileSize: fileSize,
                        mediaType: .video, hasBeenViewed: viewedURLs.contains(fileURL.path)
                    ))
                }
            }

            // Also scan legacy top-level FadCam directory for old videos
            let legacyFiles = try FileManager.default.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
            for fileURL in legacyFiles where videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let date = resourceValues?.creationDate ?? Date()
                let fileSize = Int64(resourceValues?.fileSize ?? 0)
                totalSize += fileSize
                let asset = AVAsset(url: fileURL)
                let duration = asset.duration.seconds.isNaN ? 0 : asset.duration.seconds
                results.append(Recording(
                    url: fileURL, filename: fileURL.lastPathComponent,
                    date: date, duration: duration, fileSize: fileSize,
                    mediaType: .video, hasBeenViewed: viewedURLs.contains(fileURL.path)
                ))
            }

            // FadShot photos (already nested: Back/ and Front/)
            if FileManager.default.fileExists(atPath: fadShotDirectory.path) {
                let subdirs = try FileManager.default.contentsOfDirectory(
                    at: fadShotDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                for subdir in subdirs {
                    let res = try? subdir.resourceValues(forKeys: [.isDirectoryKey])
                    guard res?.isDirectory == true else { continue }
                    let photoFiles = try FileManager.default.contentsOfDirectory(
                        at: subdir,
                        includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
                    )
                    for fileURL in photoFiles where photoExtensions.contains(fileURL.pathExtension.lowercased()) {
                        let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                        let date = resourceValues?.creationDate ?? Date()
                        let fileSize = Int64(resourceValues?.fileSize ?? 0)
                        totalSize += fileSize
                        results.append(Recording(
                            url: fileURL, filename: fileURL.lastPathComponent,
                            date: date, duration: 0, fileSize: fileSize,
                            mediaType: .photo, hasBeenViewed: viewedURLs.contains(fileURL.path)
                        ))
                    }
                }
            }

            recordings = results.sorted { $0.date > $1.date }
            totalStorageBytes = totalSize
        } catch {
            recordings = []
            totalStorageBytes = 0
        }
    }

    func markAsViewed(_ recording: Recording) {
        guard !recording.hasBeenViewed else { return }
        viewedURLs.insert(recording.url.path)
        persistViewedSet()
        if let idx = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[idx].hasBeenViewed = true
        }
    }

    func deleteRecording(_ recording: Recording) {
        trashVM.moveToTrash(recording)
        viewedURLs.remove(recording.url.path)
        persistViewedSet()
        loadRecordings()
    }

    func refreshTrashCount() {
        trashItemCount = trashVM.itemCount
    }

    func duplicateRecording(_ recording: Recording) {
        let fm = FileManager.default
        let original = recording.url
        let ext = original.pathExtension
        let baseName = original.deletingPathExtension().lastPathComponent
        let parent = original.deletingLastPathComponent()

        var counter = 1
        var newURL = original
        while fm.fileExists(atPath: newURL.path) {
            counter += 1
            newURL = parent.appendingPathComponent("\(baseName) (\(counter)).\(ext)")
        }

        do {
            try fm.copyItem(at: original, to: newURL)
            loadRecordings()
        } catch {
            print("Failed to duplicate recording: \(error)")
        }
    }

    func renameRecording(_ recording: Recording, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ext = recording.url.pathExtension
        let parent = recording.url.deletingLastPathComponent()
        let safeName = trimmed.hasSuffix(".\(ext)") ? String(trimmed.dropLast(ext.count + 1)) : trimmed
        guard !safeName.isEmpty else { return false }
        var newURL = parent.appendingPathComponent("\(safeName).\(ext)")
        var counter = 1
        let baseName = safeName
        while FileManager.default.fileExists(atPath: newURL.path) && newURL != recording.url {
            counter += 1
            newURL = parent.appendingPathComponent("\(baseName) (\(counter)).\(ext)")
        }
        do {
            try FileManager.default.moveItem(at: recording.url, to: newURL)
            ThumbnailService.shared.invalidateCache(for: recording.url)
            ThumbnailService.shared.invalidateCache(for: newURL)
            viewedURLs.remove(recording.url.path)
            if viewedURLs.contains(newURL.path) {
                viewedURLs.remove(newURL.path)
            }
            persistViewedSet()
            loadRecordings()
            return true
        } catch {
            print("Failed to rename: \(error)")
            return false
        }
    }

    enum GallerySaveOption {
        case copyOnly
        case move
    }

    func saveToGallery(_ recording: Recording, option: GallerySaveOption) async -> Bool {
        if !photosPermissionGranted {
            let granted = await requestPhotosPermission()
            if !granted { return false }
        }

        let url = recording.url
        let isVideo = recording.isVideo

        let result: Bool = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    let image = UIImage(contentsOfFile: url.path)
                    if let image = image {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
            } completionHandler: { success, error in
                if let error = error {
                    print("Failed to save to gallery: \(error)")
                }
                continuation.resume(returning: success)
            }
        }

        if result && option == .move {
            do {
                try FileManager.default.removeItem(at: url)
                ThumbnailService.shared.invalidateCache(for: url)
                viewedURLs.remove(url.path)
                persistViewedSet()
                loadRecordings()
            } catch {
                print("Failed to remove after move: \(error)")
            }
        }

        return result
    }
}
