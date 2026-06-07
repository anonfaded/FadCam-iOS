import SwiftUI
import AVFoundation
import Combine

@MainActor
final class RecordsViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isLoading = false

    private let recordingsDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("FadCam", isDirectory: true)
    }()

    func loadRecordings() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else {
            recordings = []
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            let videoFiles = files.filter { $0.pathExtension.lowercased() == "mov" || $0.pathExtension.lowercased() == "mp4" }

            var results: [Recording] = []
            for fileURL in videoFiles {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let date = resourceValues?.contentModificationDate ?? Date()
                let fileSize = Int64(resourceValues?.fileSize ?? 0)

                let asset = AVAsset(url: fileURL)
                let duration = asset.duration.seconds.isNaN ? 0 : asset.duration.seconds

                let recording = Recording(
                    url: fileURL,
                    filename: fileURL.lastPathComponent,
                    date: date,
                    duration: duration,
                    fileSize: fileSize
                )
                results.append(recording)
            }

            recordings = results.sorted { $0.date > $1.date }
        } catch {
            recordings = []
        }
    }

    func deleteRecording(_ recording: Recording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            ThumbnailService.shared.invalidateCache(for: recording.url)
            loadRecordings()
        } catch {
            print("Failed to delete recording: \(error)")
        }
    }
}
