import SwiftUI
import StoreKit

/// FadCam Pro purchase and subscription-management screen.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var videoSettings = VideoSettings.shared

    @State private var selectedPeriod: StoreKitManager.ProductID = .yearly
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var appeared = false
    @State private var glowPulse = false
    @State private var crownDrift = false

    private let gold = Color(red: 1.0, green: 0.77, blue: 0.15)
    private let paleGold = Color(red: 1.0, green: 0.91, blue: 0.58)
    private let warmBrown = Color(red: 0.18, green: 0.11, blue: 0.025)

    private var selectedProduct: Product? {
        product(for: selectedPeriod)
    }

    private var monthlyProduct: Product? {
        product(for: .monthly)
    }

    private var yearlyProduct: Product? {
        product(for: .yearly)
    }

    private var yearlySavingsPercent: Int? {
        guard let monthlyProduct, let yearlyProduct else { return nil }
        let monthlyYear = NSDecimalNumber(decimal: monthlyProduct.price).doubleValue * 12
        let yearly = NSDecimalNumber(decimal: yearlyProduct.price).doubleValue
        guard monthlyYear > 0, yearly < monthlyYear else { return nil }
        return Int(((monthlyYear - yearly) / monthlyYear * 100).rounded())
    }

    private var yearlyMonthlyEquivalent: String? {
        guard let yearlyProduct else { return nil }
        let monthlyPrice = yearlyProduct.price / 12
        return monthlyPrice.formatted(yearlyProduct.priceFormatStyle)
    }

    private var maxResPro: String {
        let labels = videoSettings.availableResolutions
            .filter { $0.height > ProManager.freeMaxResolutionHeight }
            .map { $0.shortLabel }
        let ordered = ["4K UHD", "1080p FHD", "QHD"].compactMap { standard in
            labels.first { $0 == standard || $0.hasPrefix(standard) }
        }
        return ordered.first ?? labels.first ?? "Higher resolution"
    }

    private var maxFpsPro: String {
        let maxFrameRate = videoSettings.availableFrameRates.max() ?? 30
        return maxFrameRate > 30 ? "Up to \(maxFrameRate) fps" : "High frame rates"
    }

    var body: some View {
        ZStack {
            background

            if storeManager.isLoadingProducts && !storeManager.productsLoaded {
                ProgressView()
                    .tint(gold)
                    .scaleEffect(1.15)
            } else if let error = storeManager.loadError, storeManager.products.isEmpty {
                errorView(error)
            } else {
                content
            }

            // Close button — pinned top-trailing, no NavigationView needed
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.72))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.22)))
                            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .padding(.trailing, 18)
                    .padding(.top, 12)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.145, blue: 0.025),
                    Color(red: 0.105, green: 0.062, blue: 0.018),
                    Color(red: 0.035, green: 0.028, blue: 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(gold.opacity(glowPulse ? 0.20 : 0.10))
                .frame(width: 330, height: 330)
                .blur(radius: 72)
                .offset(x: 130, y: -260)

            Circle()
                .fill(Color.orange.opacity(glowPulse ? 0.10 : 0.04))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: -150, y: 220)

            crownPattern
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                crownDrift = true
            }
        }
    }

    private var crownPattern: some View {
        GeometryReader { proxy in
            let columns = 5
            let rows = 9
            let horizontalSpacing = proxy.size.width / CGFloat(columns)
            let verticalSpacing = proxy.size.height / CGFloat(rows)

            ZStack {
                ForEach(0..<(columns * rows), id: \.self) { index in
                    let column = index % columns
                    let row = index / columns
                    let stagger = row.isMultiple(of: 2) ? horizontalSpacing * 0.35 : 0

                    Image(systemName: "crown.fill")
                        .font(.system(size: CGFloat(10 + (index % 3) * 3), weight: .bold))
                        .foregroundColor(paleGold.opacity(index.isMultiple(of: 4) ? 0.075 : 0.035))
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -12 : 12))
                        .position(
                            x: CGFloat(column) * horizontalSpacing + stagger,
                            y: CGFloat(row) * verticalSpacing + (crownDrift ? verticalSpacing : -verticalSpacing)
                        )
                }
            }
            .blur(radius: 0.3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if storeManager.isPro {
                    subscribedContent
                } else {
                    purchaseContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var purchaseContent: some View {
        VStack(spacing: 22) {
            hero
            privacyPromise
            comparisonTable
            plansSection
            purchaseSection
            discordBanner
            restoreSection
            legalText
        }
    }

    private var subscribedContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("FADCAM PRO ACTIVE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                }
                .foregroundColor(warmBrown)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(LinearGradient(colors: [paleGold, gold], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: gold.opacity(0.3), radius: 18, y: 6)
                .padding(.top, 8)

                Text("You have the full experience.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Every current Pro feature is unlocked, plus new Pro features as they arrive.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            membershipCard
            privacyPromise

            Button {
                manageSubscription()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape.fill")
                    Text("Manage Subscription")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(warmBrown)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [paleGold, gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            }
            .buttonStyle(.plain)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }

            Text("Plan changes and cancellation are handled securely by Apple.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            discordBanner
            legalText
        }
    }

    private var membershipCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "crown.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(gold)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13).fill(gold.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(activePlanName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                if let expirationDate = storeManager.subscriptionExpirationDate {
                    Text("Access through \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("Subscription active")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            Text("ACTIVE")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(warmBrown)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(gold))
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 18).fill(gold.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(gold.opacity(0.48), lineWidth: 1))
    }

    private var activePlanName: String {
        switch storeManager.activeProductID {
        case StoreKitManager.ProductID.monthly.rawValue:
            return "Pro Monthly"
        case StoreKitManager.ProductID.yearly.rawValue:
            return "Pro Yearly"
        default:
            return "FadCam Pro"
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .bold))

                Text("FADCAM PRO")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.8)
            }
            .foregroundColor(warmBrown)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [paleGold, gold], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: gold.opacity(0.28), radius: 16, y: 5)
            .padding(.top, 8)

            Text("Record without limits.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)

            Text("Unlock the full power of your camera with every Pro feature.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Privacy Promise

    private var privacyPromise: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(gold)
                .frame(width: 38, height: 38)
                .background(Circle().fill(gold.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Private by design")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                Text("Open Source  •  No Ads  •  No Tracking")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(paleGold.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.green)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(gold.opacity(0.16), lineWidth: 1))
    }

    // MARK: - Comparison

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("FREE VS PRO")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(paleGold)

                Spacer()

                Text("More Pro features coming")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.48))
            }
            .padding(.bottom, 12)

            comparisonHeader
            comparisonRow("Resolution", free: "720p", pro: maxResPro)
            comparisonRow("Frame rate", free: "30 fps", pro: maxFpsPro)
            comparisonRow("Watermark", free: "Required", pro: "Custom / Off")
            comparisonRow("Bitrate", free: "Auto", pro: "Full control")
            comparisonRow("Battery Saver", free: "5 uses", pro: "Unlimited", isLast: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var comparisonHeader: some View {
        HStack(spacing: 8) {
            Text("Feature")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .frame(width: 70)
            Text("Pro")
                .foregroundColor(warmBrown)
                .frame(width: 96)
                .padding(.vertical, 5)
                .background(Capsule().fill(gold))
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.white.opacity(0.48))
        .padding(.bottom, 5)
    }

    private func comparisonRow(
        _ feature: String,
        free: String,
        pro: String,
        isLast: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(feature)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(free)
                    .foregroundColor(.white.opacity(0.42))
                    .frame(width: 70)

                Text(pro)
                    .foregroundColor(paleGold)
                    .frame(width: 96)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.vertical, 9)

            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.065))
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose your plan")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Text("Cancel anytime")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.48))
            }

            planCard(.yearly)
            planCard(.monthly)
        }
    }

    @ViewBuilder
    private func planCard(_ period: StoreKitManager.ProductID) -> some View {
        let isSelected = selectedPeriod == period
        let isYearly = period == .yearly
        let product = product(for: period)

        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                selectedPeriod = period
            }
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? gold : Color.white.opacity(0.25), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(gold)
                            .frame(width: 12, height: 12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)

                        if isYearly, let savings = yearlySavingsPercent {
                            Text("SAVE \(savings)%")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(warmBrown)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(gold))
                        }
                    }

                    if isYearly, let equivalent = yearlyMonthlyEquivalent {
                        Text("Just \(equivalent)/month, billed yearly")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isSelected ? paleGold.opacity(0.9) : .white.opacity(0.48))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    } else {
                        Text("Flexible monthly access")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.48))
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product?.displayPrice ?? "—")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(isYearly ? "per year" : "per month")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? gold.opacity(0.13) : Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? gold.opacity(0.85) : Color.white.opacity(0.09), lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: isSelected ? gold.opacity(0.16) : .clear, radius: 18, y: 6)
            .scaleEffect(isSelected ? 1 : 0.985)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    do {
                        try await storeManager.purchase(product)
                        if storeManager.isPro { dismiss() }
                    } catch {}
                }
            } label: {
                HStack(spacing: 9) {
                    if storeManager.isPurchasing {
                        ProgressView().tint(warmBrown).scaleEffect(0.85)
                    } else {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Text(ctaTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundColor(warmBrown)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [paleGold, gold, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: gold.opacity(glowPulse ? 0.34 : 0.18), radius: glowPulse ? 22 : 12, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(selectedProduct == nil || storeManager.isPurchasing)
            .opacity(selectedProduct == nil ? 0.55 : 1)

            if let error = storeManager.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var ctaTitle: String {
        if storeManager.isPurchasing { return "Completing purchase..." }
        guard let selectedProduct else { return "Plans unavailable" }
        return "Continue with \(selectedProduct.displayPrice)"
    }

    // MARK: - Discord

    private var discordBanner: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let url = URL(string: "https://discord.gg/kvAZvdkuuN") {
                    UIApplication.shared.open(url)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.55, green: 0.58, blue: 1.0))

                Text("Join our Discord for direct support")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restore and Legal

    private var restoreSection: some View {
        VStack(spacing: 6) {
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundColor(storeManager.isPro ? .green : .white.opacity(0.6))
            }

            Button {
                Task {
                    isRestoring = true
                    restoreMessage = nil
                    do {
                        try await storeManager.restorePurchases()
                        await storeManager.checkEntitlements()
                        restoreMessage = storeManager.isPro ? "Purchases restored." : "No active subscription found."
                        if storeManager.isPro {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                        }
                    } catch {
                        restoreMessage = "Restore failed. Please try again."
                    }
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Text("Restore Purchases")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.62))
                }
            }
            .disabled(isRestoring)
        }
    }

    private var legalText: some View {
        VStack(spacing: 8) {
            // Subscription details — required by App Store Guidelines 3.1.2
            VStack(spacing: 4) {
                if let monthly = monthlyProduct {
                    HStack {
                        Text("FadCam Pro Monthly")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text("\(monthly.displayPrice)/month")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                if let yearly = yearlyProduct {
                    HStack {
                        Text("FadCam Pro Yearly")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text("\(yearly.displayPrice)/year")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            }
            .foregroundColor(.white.opacity(0.55))

            Text("Payment charged to your Apple ID. Subscription auto-renews unless canceled at least 24 hours before the period ends. Manage in App Store > Account > Subscriptions.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://github.com/anonfaded/FadCam-iOS/blob/main/PRIVACY.md")!)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.42))
        }
        .padding(.horizontal, 12)
    }

    private func product(for period: StoreKitManager.ProductID) -> Product? {
        storeManager.sortedProducts.first { $0.id == period.rawValue }
    }

    private func manageSubscription() {
        Task {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
                restoreMessage = "Unable to open subscription management right now."
                return
            }

            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
                await storeManager.checkEntitlements()
            } catch {
                restoreMessage = "Unable to open subscription management right now."
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34))
                .foregroundColor(gold)

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                Task { await storeManager.loadProducts() }
            }
            .buttonStyle(.borderedProminent)
            .tint(gold)
            .foregroundColor(warmBrown)
        }
    }
}
