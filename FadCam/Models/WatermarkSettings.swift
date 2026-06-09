import SwiftUI
import Combine
import Foundation

/// Persisted watermark configuration. Backed by UserDefaults.
final class WatermarkSettings: ObservableObject {
    // MARK: - Singleton

    static let shared = WatermarkSettings()

    // MARK: - Keys

    private enum Key {
        static let mode          = "watermark.mode"
        static let fontSize      = "watermark.fontSize"
        static let opacity       = "watermark.opacity"
        static let corner        = "watermark.corner"
        static let shadowEnabled = "watermark.shadow"
    }

    // MARK: - Defaults

    /// Resettable defaults used by the undo buttons in settings.
    static let defaultFontSize: CGFloat = 24
    static let defaultOpacity: Double   = 1.0
    static let defaultCorner: Corner    = .topLeading
    static let defaultShadow: Bool      = true

    /// The fixed watermark label text (logo gets inserted after this).
    static let brandPrefix = "Captured by "

    /// Human-readable timestamp format: "9 June 2026, 11:45:30 AM"
    static let timestampFormat = "d MMMM yyyy, h:mm:ss a"

    // MARK: - Published Properties

    /// Watermark display mode.
    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Key.mode) }
    }

    /// Font size in points. Default 48.
    @Published var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(fontSize, forKey: Key.fontSize) }
    }

    /// Opacity 0.0–1.0. Default 1.0 (100%).
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Key.opacity) }
    }

    /// Which corner the watermark appears in.
    @Published var corner: Corner {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: Key.corner) }
    }

    /// Render a soft drop-shadow behind the watermark text for readability.
    @Published var shadowEnabled: Bool {
        didSet { UserDefaults.standard.set(shadowEnabled, forKey: Key.shadowEnabled) }
    }

    // MARK: - Computed

    /// Whether any watermark should be rendered.
    var isWatermarkShown: Bool { mode != .none }

    /// Whether a live timestamp should be appended (derived from mode).
    var showTimestamp: Bool { mode == .textWithTimestamp }

    /// Builds the full watermark as an attributed string with inline FadCam logo.
    /// Text Only: "Captured by [logo]"
    /// Text + Timestamp: "Captured by [logo] - 9 June 2026, 11:45:30 AM"
    func buildWatermarkAttributedText(fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // "Captured by " prefix
        let prefixAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        result.append(NSAttributedString(string: Self.brandPrefix, attributes: prefixAttrs))

        // Inline logo image
        if let logo = UIImage(named: "HeaderLogo") {
            let ratio = logo.size.height / logo.size.width
            let logoHeight = fontSize * 1.4
            let logoWidth = logoHeight / ratio
            let attachment = NSTextAttachment()
            attachment.image = logo.withRenderingMode(.alwaysOriginal)
            attachment.bounds = CGRect(x: 0,
                                        y: (fontSize - logoHeight) / 2 - fontSize * 0.15,
                                        width: logoWidth,
                                        height: logoHeight)
            result.append(NSAttributedString(attachment: attachment))
        } else {
            result.append(NSAttributedString(string: "FadCam", attributes: prefixAttrs))
        }

        // Timestamp
        if showTimestamp {
            let tsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: UIColor.white
            ]
            let formatter = DateFormatter()
            formatter.dateFormat = Self.timestampFormat
            result.append(NSAttributedString(string: " - " + formatter.string(from: Date()), attributes: tsAttrs))
        }

        return result
    }

    // MARK: - Enums

    enum Mode: String, CaseIterable, Identifiable {
        case none              = "None"
        case textOnly          = "Text Only"
        case textWithTimestamp = "Text + Timestamp"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .none:              return "No watermark on recordings"
            case .textOnly:          return "Logo + brand text"
            case .textWithTimestamp: return "Logo + brand + date & time"
            }
        }
    }

    enum Corner: String, CaseIterable, Identifiable {
        case topLeading     = "Top Left"
        case topTrailing    = "Top Right"
        case bottomLeading  = "Bottom Left"
        case bottomTrailing = "Bottom Right"

        var id: String { rawValue }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        self.mode          = Mode(rawValue: defaults.string(forKey: Key.mode) ?? Mode.textOnly.rawValue) ?? .textOnly
        self.fontSize      = defaults.object(forKey: Key.fontSize) as? CGFloat ?? Self.defaultFontSize
        self.opacity       = defaults.object(forKey: Key.opacity) as? Double ?? Self.defaultOpacity
        self.corner        = Corner(rawValue: defaults.string(forKey: Key.corner) ?? Self.defaultCorner.rawValue) ?? Self.defaultCorner
        self.shadowEnabled = defaults.object(forKey: Key.shadowEnabled) as? Bool ?? Self.defaultShadow
    }
}
