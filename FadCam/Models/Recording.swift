import Foundation

enum MediaType: String, Codable {
    case video = "video"
    case photo = "photo"
}

struct Recording: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let filename: String
    let date: Date
    let duration: TimeInterval
    let fileSize: Int64
    let mediaType: MediaType
    var hasBeenViewed: Bool

    init(url: URL, filename: String, date: Date, duration: TimeInterval, fileSize: Int64, mediaType: MediaType, hasBeenViewed: Bool = false) {
        self.url = url
        self.filename = filename
        self.date = date
        self.duration = duration
        self.fileSize = fileSize
        self.mediaType = mediaType
        self.hasBeenViewed = hasBeenViewed
    }

    var isVideo: Bool { mediaType == .video }
    var isPhoto: Bool { mediaType == .photo }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedDuration: String {
        guard isVideo else { return "Photo" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var cameraPosition: String {
        let path = url.path
        if path.contains("/FadShot/Back/") { return "Back" }
        if path.contains("/FadShot/Front/") { return "Front" }
        return "Back"
    }
}
