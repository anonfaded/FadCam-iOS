import AVFoundation
import Foundation
import Combine

/// Dynamic video recording configuration backed by UserDefaults.
/// Queries real hardware capabilities and lets the user choose.
final class VideoSettings: ObservableObject {
    static let shared = VideoSettings()

    // MARK: - UserDefaults Keys

    private enum Key {
        static let resolution    = "video.resolution"
        static let frameRate     = "video.frameRate"
        static let bitrate       = "video.bitrate"
    }

    // MARK: - Published

    @Published var selectedResolution: Resolution {
        didSet { UserDefaults.standard.set(selectedResolution.rawValue, forKey: Key.resolution) }
    }
    @Published var selectedFrameRate: Int {
        didSet { UserDefaults.standard.set(selectedFrameRate, forKey: Key.frameRate) }
    }
    @Published var selectedBitrate: Bitrate {
        didSet { UserDefaults.standard.set(selectedBitrate.rawValue, forKey: Key.bitrate) }
    }

    // MARK: - Hardware-derived options (populated once per device)

    /// All available resolutions from the camera hardware.
    @Published var availableResolutions: [Resolution] = []
    /// Frame rates available for the currently selected resolution.
    @Published var availableFrameRates: [Int] = []

    // MARK: - Computed

    /// The AVAssetWriter width for the selected preset.
    var videoWidth: Int { selectedResolution.width }
    /// The AVAssetWriter height for the selected preset.
    var videoHeight: Int { selectedResolution.height }
    /// Average bitrate in bps, or 0 for auto (no bitrate cap set).
    var bitrateBps: Int { selectedBitrate.bps }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        self.selectedResolution = Resolution(rawValue: defaults.string(forKey: Key.resolution) ?? "") ?? .hd720
        self.selectedFrameRate  = defaults.integer(forKey: Key.frameRate).nonZeroOrDefault(30)
        self.selectedBitrate    = Bitrate(rawValue: defaults.string(forKey: Key.bitrate) ?? "") ?? .auto
    }

    // MARK: - Queries

    /// Scans the device's camera formats and populates resolution / fps lists.
    func refreshHardwareOptions(for position: AVCaptureDevice.Position = .back) {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return
        }
        var seen = Set<Resolution>()
        let allFormats = camera.formats
        var resList: [Resolution] = []
        for format in allFormats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let w = Int(dims.width)
            let h = Int(dims.height)
            // Only landscape dimensions make sense for our pipeline
            guard w > h else { continue }
            let fpsRanges = format.videoSupportedFrameRateRanges
            let maxFps = fpsRanges.map { Int($0.maxFrameRate) }.max() ?? 30
            let res = Resolution(width: w, height: h, maxFps: maxFps)
            if !seen.contains(res) {
                seen.insert(res)
                resList.append(res)
            }
        }
        // Sort by pixel count descending
        resList.sort { ($0.width * $0.height) > ($1.width * $1.height) }
        availableResolutions = resList

        // If current selection not available, pick a sensible default
        if !resList.contains(selectedResolution) {
            selectedResolution = resList.first { $0.width <= 1920 && $0.height <= 1080 } ?? resList.first ?? .hd720
        }

        refreshFrameRates(for: selectedResolution, from: allFormats)
    }

    /// Updates available frame rates for a given resolution.
    func refreshFrameRates(for resolution: Resolution, from formats: [AVCaptureDevice.Format]? = nil) {
        let allFormats: [AVCaptureDevice.Format]
        if let f = formats {
            allFormats = f
        } else {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            allFormats = camera.formats
        }

        var fpsSet = Set<Int>()
        for format in allFormats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard Int(dims.width) == resolution.width, Int(dims.height) == resolution.height else { continue }
            for range in format.videoSupportedFrameRateRanges {
                // Collect discrete common frame rates
                let rates = [24, 25, 30, 60, 120, 240]
                for r in rates {
                    if Double(r) >= range.minFrameRate && Double(r) <= range.maxFrameRate {
                        fpsSet.insert(r)
                    }
                }
            }
        }
        availableFrameRates = fpsSet.sorted()
        if !availableFrameRates.contains(selectedFrameRate) {
            selectedFrameRate = availableFrameRates.first ?? 30
        }
    }
}

// MARK: - Resolution

extension VideoSettings {
    struct Resolution: Hashable, Identifiable, RawRepresentable {
        let width: Int
        let height: Int
        let maxFps: Int

        var id: String { rawValue }
        var rawValue: String { "\(width)x\(height)" }

        /// Display label: "1080p HD" / "720p HD" / "4K"
        var label: String {
            switch height {
            case 2160: return "4K (\(width)×\(height))"
            case 1080: return "1080p HD (\(width)×\(height))"
            case 720:  return "720p HD (\(width)×\(height))"
            case 540:  return "540p"
            case 480:  return "480p"
            default:   return "\(height)p (\(width)×\(height))"
            }
        }

        var shortLabel: String {
            switch height {
            case 2160: return "4K"
            case 1080: return "1080p"
            case 720:  return "720p"
            default:   return "\(height)p"
            }
        }

        static let hd720  = Resolution(width: 1280, height: 720,  maxFps: 240)
        static let fhd1080 = Resolution(width: 1920, height: 1080, maxFps: 240)
        static let uhd4K  = Resolution(width: 3840, height: 2160, maxFps: 60)

        init?(rawValue: String) {
            let parts = rawValue.split(separator: "x")
            guard parts.count == 2,
                  let w = Int(parts[0]),
                  let h = Int(parts[1]) else { return nil }
            self.width = w; self.height = h; self.maxFps = 240
        }

        init(width: Int, height: Int, maxFps: Int) {
            self.width = width; self.height = height; self.maxFps = maxFps
        }

        func hash(into hasher: inout Hasher) { hasher.combine(width); hasher.combine(height) }
        static func == (lhs: Resolution, rhs: Resolution) -> Bool {
            lhs.width == rhs.width && lhs.height == rhs.height
        }
    }
}

// MARK: - Bitrate

extension VideoSettings {
    enum Bitrate: String, CaseIterable, Identifiable {
        case auto   = "Auto"
        case low    = "Low"
        case medium = "Medium"
        case high   = "High"

        var id: String { rawValue }

        var bps: Int {
            switch self {
            case .auto:   return 0
            case .low:    return 2_000_000
            case .medium: return 5_000_000
            case .high:   return 12_000_000
            }
        }

        var label: String {
            switch self {
            case .auto:   return "Auto"
            case .low:    return "Low (2 Mbps)"
            case .medium: return "Medium (5 Mbps)"
            case .high:   return "High (12 Mbps)"
            }
        }
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ d: Int) -> Int { self == 0 ? d : self }
}
