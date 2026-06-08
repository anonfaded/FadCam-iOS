import SwiftUI
import AVFoundation
import Combine

@MainActor
final class TrashViewModel: ObservableObject {
    @Published var items: [TrashItem] = []
    @Published var isLoading = false
    @Published var totalBytes: Int64 = 0

    private var trashAutoDeleteSeconds: Int {
        let raw = UserDefaults.standard.integer(forKey: autoDeleteKey)
        let hasKey = UserDefaults.standard.object(forKey: autoDeleteKey) != nil
        return hasKey ? raw : 2592000
    }

    private let autoDeleteKey = "FadCam.trashAutoDeleteSeconds"

    private let trashDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("FadCam/Trash", isDirectory: true)
    }()

    private var trashMetadataURL: URL {
        trashDirectory.appendingPathComponent("trash.json")
    }

    func loadItems() {
        isLoading = true
        defer { isLoading = false }

        autoCleanup()

        guard FileManager.default.fileExists(atPath: trashDirectory.path),
              let data = try? Data(contentsOf: trashMetadataURL),
              let items = try? JSONDecoder().decode([TrashItem].self, from: data) else {
            self.items = []
            self.totalBytes = 0
            return
        }

        let existing = items.filter {
            FileManager.default.fileExists(atPath: trashDirectory.appendingPathComponent($0.trashFilename).path)
        }

        if existing.count != items.count {
            saveItems(existing)
        }

        self.items = existing.sorted { $0.deletedAt > $1.deletedAt }
        self.totalBytes = existing.reduce(0) { $0 + $1.fileSize }
    }

    func moveToTrash(_ recording: Recording) {
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

        let uuid = UUID().uuidString
        let ext = recording.url.pathExtension
        let trashFilename = "\(uuid).\(ext)"
        let trashURL = trashDirectory.appendingPathComponent(trashFilename)

        do {
            try fm.moveItem(at: recording.url, to: trashURL)
        } catch {
            print("Failed to move to trash: \(error)")
            return
        }

        let item = TrashItem(
            id: uuid,
            originalPath: recording.url.path,
            trashFilename: trashFilename,
            deletedAt: Date(),
            fileSize: recording.fileSize,
            mediaType: recording.mediaType,
            duration: recording.duration
        )

        var current = loadRawItems()
        current.append(item)
        saveItems(current)

        ThumbnailService.shared.invalidateCache(for: recording.url)
        loadItems()
        NotificationCenter.default.post(name: .fadCamMediaChanged, object: nil)
    }

    func restoreItem(_ item: TrashItem) {
        let trashURL = trashDirectory.appendingPathComponent(item.trashFilename)
        let originalURL = URL(fileURLWithPath: item.originalPath)

        try? FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try FileManager.default.moveItem(at: trashURL, to: originalURL)
        } catch {
            print("Failed to restore: \(error)")
            return
        }

        var current = loadRawItems()
        current.removeAll { $0.id == item.id }
        saveItems(current)
        loadItems()
        postChange()
    }

    func permanentlyDelete(_ item: TrashItem) {
        let trashURL = trashDirectory.appendingPathComponent(item.trashFilename)
        try? FileManager.default.removeItem(at: trashURL)
        ThumbnailService.shared.invalidateCache(for: trashURL)

        var current = loadRawItems()
        current.removeAll { $0.id == item.id }
        saveItems(current)
        loadItems()
        postChange()
    }

    func emptyTrash() {
        for item in items {
            let trashURL = trashDirectory.appendingPathComponent(item.trashFilename)
            try? FileManager.default.removeItem(at: trashURL)
            ThumbnailService.shared.invalidateCache(for: trashURL)
        }
        saveItems([])
        loadItems()
        postChange()
    }

    func autoCleanup() {
        let autoSeconds = trashAutoDeleteSeconds
        guard autoSeconds >= 0 else { return }

        let cutoff = Date().addingTimeInterval(-TimeInterval(autoSeconds))
        let allItems = loadRawItems()
        let expired = allItems.filter { $0.deletedAt <= cutoff }

        for item in expired {
            let trashURL = trashDirectory.appendingPathComponent(item.trashFilename)
            try? FileManager.default.removeItem(at: trashURL)
            ThumbnailService.shared.invalidateCache(for: trashURL)
        }

        let remaining = allItems.filter { $0.deletedAt > cutoff }
        saveItems(remaining)
        self.items = remaining.sorted { $0.deletedAt > $1.deletedAt }
        self.totalBytes = remaining.reduce(0) { $0 + $1.fileSize }
    }

    var itemCount: Int {
        loadRawItems().count
    }

    private func loadRawItems() -> [TrashItem] {
        guard let data = try? Data(contentsOf: trashMetadataURL),
              let items = try? JSONDecoder().decode([TrashItem].self, from: data) else {
            return []
        }
        return items
    }

    private func saveItems(_ items: [TrashItem]) {
        try? FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: trashMetadataURL)
        }
    }

    private func postChange() {
        NotificationCenter.default.post(name: .fadCamMediaChanged, object: nil)
    }
}
