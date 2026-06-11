import SwiftUI
import Combine

/// Centralized feature-gating for FadCam Pro.
/// All Pro checks flow through this type — never check StoreKitManager directly.
@MainActor
final class ProManager: ObservableObject {
    static let shared = ProManager()

    @Published private(set) var isPro = false
    @Published private(set) var entitlementChecked = false

    private let storeManager = StoreKitManager.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        isPro = storeManager.isPro
        entitlementChecked = storeManager.entitlementChecked

        // Mirror StoreKitManager state via Combine
        storeManager.$isPro
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPro, on: self)
            .store(in: &cancellables)

        storeManager.$entitlementChecked
            .receive(on: DispatchQueue.main)
            .assign(to: \.entitlementChecked, on: self)
            .store(in: &cancellables)

        // Warm product loading
        Task { await storeManager.loadProducts() }
    }

    // MARK: - Feature Gates

    /// Whether the user can disable the watermark entirely ("None" mode).
    var canDisableWatermark: Bool { isPro }

    /// Whether the user can enter custom watermark text.
    var canCustomWatermarkText: Bool { isPro }

    /// Whether the user can change watermark corner position.
    var canChangeWatermarkPosition: Bool { isPro }

    /// Maximum free resolution height. Pro users can exceed this.
    static let freeMaxResolutionHeight = 720

    /// Maximum free frame rate. Pro users can exceed this.
    static let freeMaxFrameRate = 30

    /// Whether the user can select custom bitrate.
    var canCustomBitrate: Bool { isPro }

    // MARK: - Battery Saver Freemium

    /// Maximum free Battery Saver uses per day. Pro users get unlimited.
    static let maxFreeSaverUsesPerDay = 3

    /// How many saver uses remain today for a free user.
    var saverRemainingUses: Int {
        guard !isPro else { return Int.max }
        let today = Self.todayKey()
        let stored = UserDefaults.standard.string(forKey: today) ?? ""
        let usedToday: Int
        if let num = Int(stored) { usedToday = num } else { usedToday = 0 }
        return max(0, Self.maxFreeSaverUsesPerDay - usedToday)
    }

    /// Call this when the user activates Battery Saver. Returns true if allowed.
    @discardableResult
    func consumeSaverUse() -> Bool {
        guard !isPro else { return true }
        guard saverRemainingUses > 0 else { return false }

        let today = Self.todayKey()
        let stored = UserDefaults.standard.string(forKey: today) ?? "0"
        let current = (Int(stored) ?? 0) + 1
        UserDefaults.standard.set("\(current)", forKey: today)
        return true
    }

    /// "YYYY-MM-DD" key for today's saver use counter.
    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "FadCam.saver.uses." + formatter.string(from: Date())
    }
}
