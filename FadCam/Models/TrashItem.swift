import Foundation

struct TrashItem: Identifiable, Codable, Hashable {
    var id: String
    let originalPath: String
    let trashFilename: String
    let deletedAt: Date
    let fileSize: Int64
    let mediaType: MediaType
    var duration: TimeInterval

    var filename: String { URL(fileURLWithPath: originalPath).lastPathComponent }
    var isVideo: Bool { mediaType == .video }
    var isPhoto: Bool { mediaType == .photo }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedDuration: String {
        guard isVideo else { return "Photo" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var cameraPosition: String {
        let path = originalPath
        if path.contains("/FadShot/Back/") { return "Back" }
        if path.contains("/FadShot/Front/") { return "Front" }
        return "Back"
    }
}
