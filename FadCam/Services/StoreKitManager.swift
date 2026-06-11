import StoreKit
import Combine
import OSLog

private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "store")

/// Manages StoreKit 2 subscriptions for FadCam Pro.
/// Singleton — access via `StoreKitManager.shared`.
@MainActor
final class StoreKitManager: ObservableObject {

    // MARK: - Singleton

    static let shared = StoreKitManager()

    // MARK: - Product IDs

    enum ProductID: String, CaseIterable {
        case monthly = "com.fadseclab.fadcam.pro.monthly"
        case yearly  = "com.fadseclab.fadcam.pro.yearly"
    }

    // MARK: - Published State

    /// Available products loaded from App Store.
    @Published var products: [Product] = []

    /// Sorted: monthly first, then yearly.
    @Published var sortedProducts: [Product] = []

    /// True when product loading is in progress.
    @Published var isLoadingProducts = false

    /// True once product loading has completed (even if empty).
    @Published private(set) var productsLoaded = false

    /// True when a purchase is in flight.
    @Published var isPurchasing = false

    /// Non-nil when loading products failed.
    @Published var loadError: String?

    /// Non-nil when a purchase fails.
    @Published var purchaseError: String?

    /// Whether the user currently has Pro entitlement.
    @Published private(set) var isPro = false

    /// Product identifier for the currently active Pro subscription.
    @Published private(set) var activeProductID: String?

    /// Expiration date for the currently active Pro subscription.
    @Published private(set) var subscriptionExpirationDate: Date?

    /// True once the initial entitlement check completes.
    @Published private(set) var entitlementChecked = false

    // MARK: - Transactions

    private var updateListenerTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        // Restore cached entitlement state immediately
        isPro = Self.readCachedPro()
        log.info("StoreKitManager init — cached isPro: \(self.isPro)")

        // Start transaction listener
        updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
            }
        }

        // Check current entitlements
        Task { @MainActor in
            await checkEntitlements()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    /// Load products from StoreKit. Retries if already loaded but was empty.
    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        loadError = nil
        defer {
            isLoadingProducts = false
            productsLoaded = true
        }

        let identifiers = ProductID.allCases.map { $0.rawValue }
        do {
            let loaded = try await Product.products(for: identifiers)
            products = loaded
            sortedProducts = loaded.sorted {
                if $0.id == ProductID.monthly.rawValue { return true }
                if $1.id == ProductID.monthly.rawValue { return false }
                return $0.id < $1.id
            }
            log.info("Loaded \(self.products.count) products")
            if loaded.isEmpty {
                log.warning("No products returned from StoreKit")
            }
        } catch {
            loadError = "Could not load products. Please check your internet connection."
            log.error("Product load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    /// Purchases a single product. Returns the transaction once completed.
    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction? {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            purchaseError = error.localizedDescription
            log.error("Purchase failed: \(error.localizedDescription)")
            throw error
        }

        switch result {
        case .success(let verificationResult):
            let transaction = await handle(transactionResult: verificationResult)
            return transaction

        case .userCancelled:
            log.info("User cancelled purchase")
            return nil

        case .pending:
            log.info("Purchase pending (parental approval, etc.)")
            purchaseError = "Purchase is pending approval."
            return nil

        @unknown default:
            log.error("Unknown purchase result")
            purchaseError = "An unknown error occurred."
            return nil
        }
    }

    // MARK: - Restore

    /// Restore all previous purchases.
    func restorePurchases() async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        // Sync any transactions that may not have been processed.
        // Transaction.currentEntitlements handles this, but a sync
        // catches edge cases.
        do {
            try await AppStore.sync()
            log.info("AppStore.sync() completed")
        } catch {
            log.warning("AppStore.sync() failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Entitlement Check

    /// Check current entitlements from Transaction history.
    func checkEntitlements() async {
        var hasActive = false
        var activeProductID: String?
        var latestExpirationDate: Date?
        let proProductIDs = Set(ProductID.allCases.map(\.rawValue))

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                guard proProductIDs.contains(transaction.productID) else { continue }
                let hasBeenRevoked = transaction.revocationDate != nil
                let hasExpired = transaction.expirationDate.map { $0 < Date() } ?? false
                if !hasBeenRevoked && !hasExpired && !transaction.isUpgraded {
                    hasActive = true
                    if latestExpirationDate == nil ||
                        (transaction.expirationDate ?? .distantFuture) > (latestExpirationDate ?? .distantPast) {
                        activeProductID = transaction.productID
                        latestExpirationDate = transaction.expirationDate
                    }
                } else if transaction.isUpgraded {
                    // Upgraded — transaction superseded. Mark original as finished.
                    await transaction.finish()
                }
            }
        }

        // Atomic: update and persist
        self.activeProductID = activeProductID
        subscriptionExpirationDate = latestExpirationDate
        updateIsPro(hasActive)
        log.info("Entitlements checked — isPro: \(hasActive)")
    }

    // MARK: - Transaction Handling

    @discardableResult
    private func handle(transactionResult: VerificationResult<Transaction>) async -> Transaction? {
        switch transactionResult {
        case .verified(let transaction):
            guard ProductID.allCases.map(\.rawValue).contains(transaction.productID) else {
                log.warning("Ignoring unknown transaction product: \(transaction.productID)")
                await transaction.finish()
                return transaction
            }

            let hasBeenRevoked = transaction.revocationDate != nil
            let hasExpired = transaction.expirationDate.map { $0 < Date() } ?? false
            guard !hasBeenRevoked, !hasExpired, !transaction.isUpgraded else {
                log.info("Transaction inactive — refreshing Pro entitlement")
                await transaction.finish()
                await checkEntitlements()
                return transaction
            }

            // Grant immediately from the verified purchase result. In local StoreKit
            // testing, currentEntitlements may briefly lag behind a successful purchase.
            activeProductID = transaction.productID
            subscriptionExpirationDate = transaction.expirationDate
            updateIsPro(true)
            log.info("Transaction verified — granting Pro")
            await transaction.finish()
            return transaction

        case .unverified(_, let error):
            log.error("Transaction unverified: \(error.localizedDescription)")
            purchaseError = "Transaction could not be verified."
            return nil
        }
    }

    // MARK: - Internal: Update & Persist

    private func updateIsPro(_ value: Bool) {
        isPro = value
        entitlementChecked = true
        Self.writeCachedPro(value)
    }

    // MARK: - Caching

    private static let cacheKey = "FadCam.pro.isPro"

    private static func readCachedPro() -> Bool {
        UserDefaults.standard.bool(forKey: cacheKey)
    }

    private static func writeCachedPro(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: cacheKey)
    }
}
