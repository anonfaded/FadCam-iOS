import SwiftUI
import Combine
import Foundation

/// Persisted watermark configuration. Backed by @AppStorage / UserDefaults.
/// Designed for scalability — adding new properties just requires new keys.
final class WatermarkSettings: ObservableObject {
    // MARK: - Singleton

    static let shared = WatermarkSettings()

    // MARK: - Keys

    private enum Key {
        static let enabled      = "watermark.enabled"
        static let text         = "watermark.text"
        static let fontSize     = "watermark.fontSize"
        static let opacity      = "watermark.opacity"
        static let corner       = "watermark.corner"
    }

    // MARK: - Published Properties

    /// Whether watermark is rendered at all.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Key.enabled) }
    }

    /// The watermark text. Default: "Captured by FadCam"
    @Published var text: String {
        didSet { UserDefaults.standard.set(text, forKey: Key.text) }
    }

    /// Font size in points (scale-relative). 48 = default.
    @Published var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(fontSize, forKey: Key.fontSize) }
    }

    /// Opacity 0.0–1.0.
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Key.opacity) }
    }

    /// Which corner the watermark appears in.
    @Published var corner: Corner {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: Key.corner) }
    }

    // MARK: - Corner enum

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
        self.enabled  = defaults.object(forKey: Key.enabled) as? Bool ?? true
        self.text     = defaults.string(forKey: Key.text) ?? "Captured by FadCam"
        self.fontSize = defaults.object(forKey: Key.fontSize) as? CGFloat ?? 48
        self.opacity  = defaults.object(forKey: Key.opacity) as? Double ?? 0.5
        self.corner   = Corner(rawValue: defaults.string(forKey: Key.corner) ?? Corner.topLeading.rawValue) ?? .topLeading
    }
}
