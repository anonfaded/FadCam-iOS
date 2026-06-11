import SwiftUI
import StoreKit

/// FadCam Pro paywall with feature comparison table.
/// Follows App Store best practices: clear value proposition,
/// side-by-side Free vs Pro comparison, transparent pricing,
/// and easily discoverable Restore Purchases.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var videoSettings = VideoSettings.shared

    @State private var selectedProduct: Product?
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    // Dynamic capability labels for comparison table
    private var maxResPro: String {
        let labels = videoSettings.availableResolutions
            .filter { $0.height > ProManager.freeMaxResolutionHeight }
            .map(\.shortLabel)
        return labels.isEmpty ? "—" : "Up to " + (labels.last ?? "—")
    }

    private var maxFpsPro: String {
        let max = videoSettings.availableFrameRates.max() ?? 30
        return max > 30 ? "Up to \(max) fps" : "—"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if storeManager.isLoadingProducts {
                    ProgressView().tint(.red).scaleEffect(1.2)
                } else if let error = storeManager.loadError, storeManager.products.isEmpty {
                    errorView(error)
                } else {
                    content
                }
            }
            .navigationTitle("FadCam Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                comparisonTable
                pricingCards
                ctaButton
                restoreButton
                legalText
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.red.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "crown.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.1))
            }
            .padding(.top, 24)

            Text("Unlock Everything")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("One subscription. All features. Cancel anytime.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 28)
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // Column headers
            headerRow
            tableDivider

            // Rows
            tableRow("Resolution",   free: "720p",      pro: maxResPro)
            tableRow("Frame Rate",   free: "30 fps",    pro: maxFpsPro)
            tableRow("Bitrate",      free: "Auto",      pro: "Custom")
            tableRow("Watermark",    free: proMark(false), pro: proMark(true))
            tableRow("Custom Text",  free: "—",          pro: "Unlimited")
            tableRow("Position",     free: "Locked",     pro: "All Corners")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Feature")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 70)
            Text("Pro")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.1))
                .frame(width: 70)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.03))
    }

    private var tableDivider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    @ViewBuilder
    private func tableRow(_ feature: String, free: String, pro: String) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 70)
            Text(pro)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.1))
                .frame(width: 70)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
    }

    private func proMark(_ active: Bool) -> String {
        active ? "✓" : "—"
    }

    // MARK: - Pricing Cards

    private var pricingCards: some View {
        VStack(spacing: 10) {
            ForEach(storeManager.sortedProducts) { product in
                Button {
                    selectedProduct = product
                } label: {
                    pricingRow(product)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func pricingRow(_ product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let isMonthly = product.id == StoreKitManager.ProductID.monthly.rawValue

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.red : Color.white.opacity(0.2), lineWidth: 2)
                    .frame(width: 20, height: 20)
                if isSelected {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isMonthly ? "Monthly" : "Yearly")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                let period = isMonthly ? "month" : "year"
                Text("\(product.displayPrice)/\(period)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isMonthly {
                Text("Save ~50%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color(red: 1.0, green: 0.85, blue: 0.2))
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.red.opacity(0.1) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.red.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task {
                do {
                    try await storeManager.purchase(product)
                    if storeManager.isPro { dismiss() }
                } catch {}
            }
        } label: {
            HStack(spacing: 8) {
                if storeManager.isPurchasing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                }
                Text(ctaTitle)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        selectedProduct == nil
                            ? AnyShapeStyle(Color.gray.opacity(0.25))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.red, Color(red: 0.65, green: 0.08, blue: 0.08)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
            )
        }
        .disabled(selectedProduct == nil || storeManager.isPurchasing)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var ctaTitle: String {
        if storeManager.isPurchasing { return "Subscribing…" }
        guard let product = selectedProduct else { return "Choose a Plan" }
        let period = product.id.contains("monthly") ? "mo" : "yr"
        return "Subscribe \(product.displayPrice)/\(period)"
    }

    // MARK: - Restore

    private var restoreButton: some View {
        VStack(spacing: 4) {
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundColor(restoreMessage.hasPrefix("✅") ? .green : .secondary)
            }

            Button {
                Task {
                    isRestoring = true
                    restoreMessage = nil
                    do {
                        try await storeManager.restorePurchases()
                        await storeManager.checkEntitlements()
                        restoreMessage = storeManager.isPro
                            ? "✅ Purchases restored!"
                            : "No active subscription found."
                        if storeManager.isPro {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                        }
                    } catch {
                        restoreMessage = "Restore failed. Try again."
                    }
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(isRestoring)
            .padding(.vertical, 8)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Legal

    private var legalText: some View {
        VStack(spacing: 6) {
            Text("Payment will be charged to your Apple ID. Subscription auto-renews unless canceled at least 24 hours before the period ends. Manage in Settings.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 4) {
                Text("Terms of Service")
                Text("·")
                Text("Privacy Policy")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.bottom, 24)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try Again") {
                Task { await storeManager.loadProducts() }
            }
            .buttonStyle(.bordered).tint(.red)
        }
    }
}

