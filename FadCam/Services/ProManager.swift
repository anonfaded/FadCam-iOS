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

    /// Lifetime hard limit. After 5 free uses, user must subscribe.
    static let maxFreeSaverUsesLifetime = 5

    private static let saverUseKey = "FadCam.saver.lifetimeUses"

    /// How many lifetime uses remain. Pro = unlimited.
    var saverRemainingUses: Int {
        guard !isPro else { return Int.max }
        let used = UserDefaults.standard.integer(forKey: Self.saverUseKey)
        return max(0, Self.maxFreeSaverUsesLifetime - used)
    }

    /// Call when user confirms Battery Saver activation. Returns true if allowed.
    @discardableResult
    func consumeSaverUse() -> Bool {
        guard !isPro else { return true }
        guard saverRemainingUses > 0 else { return false }
        let used = UserDefaults.standard.integer(forKey: Self.saverUseKey) + 1
        UserDefaults.standard.set(used, forKey: Self.saverUseKey)
        return true
    }
}
