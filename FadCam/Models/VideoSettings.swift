import AVFoundation
import Foundation
import Combine

/// Dynamic video recording configuration backed by UserDefaults.
/// Queries real hardware capabilities and lets the user choose.
final class VideoSettings: ObservableObject {
    static let shared = VideoSettings()

    // MARK: - UserDefaults Keys

    private enum Key {
        static let resolution     = "video.resolution"
        static let frameRate      = "video.frameRate"
        static let bitrateMode    = "video.bitrateMode"
        static let customBitrate  = "video.customBitrateMbps"
    }

    // MARK: - Published

    @Published var selectedResolution: Resolution {
        didSet { UserDefaults.standard.set(selectedResolution.rawValue, forKey: Key.resolution) }
    }
    @Published var selectedFrameRate: Int {
        didSet { UserDefaults.standard.set(selectedFrameRate, forKey: Key.frameRate) }
    }
    @Published var bitrateMode: BitrateMode {
        didSet { UserDefaults.standard.set(bitrateMode.rawValue, forKey: Key.bitrateMode) }
    }
    /// Custom bitrate in Mbps (stored as Int for simplicity).
    @Published var customBitrateMbps: Int {
        didSet { UserDefaults.standard.set(customBitrateMbps, forKey: Key.customBitrate) }
    }

    // MARK: - Hardware-derived options (populated once per device)

    @Published var availableResolutions: [Resolution] = []
    @Published var availableFrameRates: [Int] = []

    // MARK: - Computed

    var videoWidth: Int { selectedResolution.width }
    var videoHeight: Int { selectedResolution.height }

    /// Returns the recommended bitrate based on resolution and fps,
    /// using standard H.264 encoding guidelines.
    var recommendedBitrateMbps: Int {
        let pixels = selectedResolution.width * selectedResolution.height
        let fps = selectedFrameRate
        // Standard H.264 bitrate guidelines per megapixel at 30fps:
        // ~5 Mbps for 1080p, ~3 Mbps for 720p, ~15 Mbps for 4K
        // Scale linearly with resolution and fps
        let baseMbps: Double
        switch pixels {
        case 0...500_000:       baseMbps = 1.5   // SD
        case 500_001...1_000_000: baseMbps = 3.0  // 720p
        case 1_000_001...2_500_000: baseMbps = 5.0 // 1080p
        default:                 baseMbps = Double(pixels) / 2_073_600 * 5.0 // scale from 1080p
        }
        let scaledMbps = baseMbps * Double(fps) / 30.0
        return max(1, Int(scaledMbps.rounded()))
    }

    /// Actual bitrate in bps to use for encoding. 0 = auto (system decides).
    var bitrateBps: Int {
        switch bitrateMode {
        case .auto:   return 0
        case .custom: return customBitrateMbps * 1_000_000
        }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        self.selectedResolution = Resolution(rawValue: defaults.string(forKey: Key.resolution) ?? "") ?? .hd720
        self.selectedFrameRate  = defaults.integer(forKey: Key.frameRate).nonZeroOrDefault(30)
        self.bitrateMode       = BitrateMode(rawValue: defaults.string(forKey: Key.bitrateMode) ?? "") ?? .auto
        let savedCustom = defaults.integer(forKey: Key.customBitrate)
        self.customBitrateMbps  = savedCustom > 0 ? savedCustom : 5
    }

    // MARK: - Queries (unchanged from prior implementation)

    func refreshHardwareOptions(for position: AVCaptureDevice.Position = .back) {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
        var seen = Set<Resolution>()
        let allFormats = camera.formats
        var resList: [Resolution] = []
        for format in allFormats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let w = Int(dims.width), h = Int(dims.height)
            guard w > h else { continue }
            let maxFps = format.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate) }.max() ?? 30
            let res = Resolution(width: w, height: h, maxFps: maxFps)
            if !seen.contains(res) { seen.insert(res); resList.append(res) }
        }
        resList.sort { ($0.width * $0.height) > ($1.width * $1.height) }
        availableResolutions = resList
        if !resList.contains(selectedResolution) {
            selectedResolution = resList.first { $0.width <= 1920 && $0.height <= 1080 } ?? resList.first ?? .hd720
        }
        refreshFrameRates(for: selectedResolution, from: allFormats)
    }

    func refreshFrameRates(for resolution: Resolution, from formats: [AVCaptureDevice.Format]? = nil) {
        let allFormats: [AVCaptureDevice.Format]
        if let f = formats { allFormats = f }
        else {
            guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            allFormats = cam.formats
        }
        var fpsSet = Set<Int>()
        for format in allFormats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard Int(dims.width) == resolution.width, Int(dims.height) == resolution.height else { continue }
            for range in format.videoSupportedFrameRateRanges {
                for r in [24, 25, 30, 60, 120, 240] {
                    if Double(r) >= range.minFrameRate && Double(r) <= range.maxFrameRate { fpsSet.insert(r) }
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
        let width: Int; let height: Int; let maxFps: Int
        var id: String { rawValue }
        var rawValue: String { "\(width)x\(height)" }
        var shortLabel: String {
            switch height {
            case 2160: return "4K"
            case 1080: return "1080p"
            case 720:  return "720p"
            default:   return "\(height)p"
            }
        }
        var label: String { "\(shortLabel) (\(width)×\(height))" }

        static let hd720  = Resolution(width: 1280, height: 720,  maxFps: 240)
        static let fhd1080 = Resolution(width: 1920, height: 1080, maxFps: 240)
        static let uhd4K  = Resolution(width: 3840, height: 2160, maxFps: 60)

        init?(rawValue: String) {
            let parts = rawValue.split(separator: "x")
            guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
            self.width = w; self.height = h; self.maxFps = 240
        }
        init(width: Int, height: Int, maxFps: Int) { self.width = width; self.height = height; self.maxFps = maxFps }
        func hash(into hasher: inout Hasher) { hasher.combine(width); hasher.combine(height) }
        static func == (lhs: Resolution, rhs: Resolution) -> Bool { lhs.width == rhs.width && lhs.height == rhs.height }
    }
}

// MARK: - BitrateMode

extension VideoSettings {
    enum BitrateMode: String, CaseIterable, Identifiable {
        case auto   = "Auto"
        case custom = "Custom"

        var id: String { rawValue }
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ d: Int) -> Int { self == 0 ? d : self }
}
