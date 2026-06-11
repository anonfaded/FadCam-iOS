import SwiftUI
import Combine

/// Dedicated watermark customization screen with live preview.
struct WatermarkSettingsView: View {
    @StateObject private var settings = WatermarkSettings.shared
    @StateObject private var proManager = ProManager.shared
    @State private var previewTimestamp = Date()
    @State private var showPaywall = false
    @State private var paywallFeature = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            // MARK: - Live Preview
            Section {
                livePreviewCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Live Preview")
            } footer: {
                Text("This is how your watermark will look in recordings and FadShot photos.")
            }

            // MARK: - Mode
            Section {
                VStack(spacing: 12) {
                    Text("Watermark Style")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    modePicker
                }
            } header: {
                Text("Display Mode")
            } footer: {
                Text(settings.mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: - Custom Text
            if settings.isWatermarkShown {
                Section {
                    HStack {
                        VStack(spacing: 8) {
                            HStack {
                                TextField("Optional custom text...", text: $settings.customText)
                                    .font(.system(size: 16))
                                    .padding(10)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                    .disabled(!ProManager.shared.isPro)

                                if !ProManager.shared.isPro {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.yellow)
                                        .onTapGesture { paywallForFeature("custom watermark text") }
                                }
                            }
                            Text(ProManager.shared.isPro
                                 ? "Custom text appears on a new line below the watermark."
                                 : "FadCam Pro — unlock custom watermark text.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    Text("Custom Text")
                }
            }

            // MARK: - Appearance
            if settings.isWatermarkShown {
                Section {
                    // Font Size
                    VStack(spacing: 6) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(settings.fontSize))pt")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.red)
                            resetButton {
                                settings.fontSize = WatermarkSettings.defaultFontSize
                            }
                        }
                        Slider(value: $settings.fontSize, in: 12...96, step: 2)
                            .tint(.red)
                    }

                    // Opacity
                    VStack(spacing: 6) {
                        HStack {
                            Text("Opacity")
                            Spacer()
                            Text("\(Int(settings.opacity * 100))%")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.red)
                            resetButton {
                                settings.opacity = WatermarkSettings.defaultOpacity
                            }
                        }
                        Slider(value: $settings.opacity, in: 0.1...1.0, step: 0.05)
                            .tint(.red)
                    }

                    // Position
                    HStack {
                        if ProManager.shared.isPro {
                            Picker(selection: $settings.corner) {
                                ForEach(WatermarkSettings.Corner.allCases) { corner in
                                    HStack(spacing: 6) {
                                        Image(systemName: corner.systemImage)
                                        Text(corner.rawValue)
                                    }.tag(corner)
                                }
                            } label: {
                                Label("Position", systemImage: "rectangle.arrowtriangle.2.outward")
                            }
                            resetButton {
                                settings.corner = WatermarkSettings.defaultCorner
                            }
                        } else {
                            HStack {
                                Label("Position", systemImage: "rectangle.arrowtriangle.2.outward")
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(settings.corner.rawValue)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.yellow)
                                }
                                .onTapGesture { paywallForFeature("change watermark position") }
                            }
                        }
                    }

                    // Shadow
                    Toggle(isOn: $settings.shadowEnabled) {
                        Label("Drop Shadow", systemImage: "circle.fill")
                    }
                    .tint(.red)
                } header: {
                    Text("Appearance")
                } footer: {
                    (Text(Image(systemName: "arrow.counterclockwise")).font(.system(size: 10))
                     + Text(" Tap to reset any setting to its default.  A drop shadow helps readability on bright scenes."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Watermark")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(timer) { _ in
            previewTimestamp = Date()
        }
        .onAppear { setTabBar(hidden: true) }
        .onDisappear { setTabBar(hidden: false) }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func paywallForFeature(_ feature: String) {
        paywallFeature = feature
        showPaywall = true
    }

    // MARK: - Tab Bar

    /// Walks the responder chain from the root window to find the UITabBarController
    /// and shows/hides its tab bar. Works around the nested-NavigationView limitation.
    private func setTabBar(hidden: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else { return }
            // Recursively search for UITabBarController in the VC hierarchy
            if let tabVC = findTabBarController(from: rootVC) {
                tabVC.tabBar.isHidden = hidden
            }
        }
    }

    private func findTabBarController(from vc: UIViewController) -> UITabBarController? {
        if let tab = vc as? UITabBarController { return tab }
        if let tab = vc.tabBarController { return tab }
        for child in vc.children {
            if let found = findTabBarController(from: child) { return found }
        }
        return nil
    }

    // MARK: - Live Preview Card

    private var livePreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray6), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            if settings.isWatermarkShown {
                watermarkPreviewOverlay
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Watermark")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Watermark Preview Overlay

    private var watermarkPreviewOverlay: some View {
        VStack {
            if settings.corner == .topLeading || settings.corner == .topTrailing {
                HStack {
                    if settings.corner == .topLeading {
                        previewWatermarkLabel
                        Spacer()
                    } else {
                        Spacer()
                        previewWatermarkLabel
                    }
                }
                Spacer()
            } else {
                Spacer()
                HStack {
                    if settings.corner == .bottomLeading {
                        previewWatermarkLabel
                        Spacer()
                    } else {
                        Spacer()
                        previewWatermarkLabel
                    }
                }
            }
        }
        .padding(8)
    }

    private var previewWatermarkLabel: some View {
        let fs = previewFontSize
        let hasTs = settings.mode == .textWithTimestamp
        let logoHeight = fs * WatermarkSettings.logoToFontRatio
        let trimmedCustom = settings.customText.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(WatermarkSettings.brandPrefix)
                    .font(.system(size: fs, weight: .semibold))
                    .shadow(
                        color: settings.shadowEnabled ? .black.opacity(0.5) : .clear,
                        radius: settings.shadowEnabled ? 1.5 : 0,
                        x: settings.shadowEnabled ? 1 : 0,
                        y: settings.shadowEnabled ? 1 : 0
                    )

                if let logo = UIImage(named: "HeaderLogo") {
                    let ratio = logo.size.width / logo.size.height
                    let logoW = logoHeight * ratio
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: logoHeight)
                        .frame(width: logoW)
                }

                if hasTs {
                    Text(" - " + timestampString)
                        .font(.system(size: fs, weight: .regular))
                        .shadow(
                            color: settings.shadowEnabled ? .black.opacity(0.5) : .clear,
                            radius: settings.shadowEnabled ? 1.5 : 0,
                            x: settings.shadowEnabled ? 1 : 0,
                            y: settings.shadowEnabled ? 1 : 0
                        )
                }
            }

            if !trimmedCustom.isEmpty {
                Text(trimmedCustom)
                    .font(.system(size: fs * 0.72, weight: .regular))
                    .shadow(
                        color: settings.shadowEnabled ? .black.opacity(0.5) : .clear,
                        radius: settings.shadowEnabled ? 1.5 : 0,
                        x: settings.shadowEnabled ? 1 : 0,
                        y: settings.shadowEnabled ? 1 : 0
                    )
            }
        }
        .foregroundColor(.white.opacity(settings.opacity))
    }

    private var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = WatermarkSettings.timestampFormat
        return formatter.string(from: previewTimestamp)
    }

    private var previewFontSize: CGFloat {
        settings.fontSize * 0.5
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(WatermarkSettings.Mode.allCases) { mode in
                modeCard(mode)
            }
        }
    }

    private func modeCard(_ mode: WatermarkSettings.Mode) -> some View {
        let isNone = mode == .none
        let locked = isNone && !ProManager.shared.isPro
        let isSelected = settings.mode == mode
        let title: String = {
            switch mode {
            case .none: return "None"
            case .textOnly: return "Text Only"
            case .textWithTimestamp: return "Text + Time"
            }
        }()

        return Button {
            guard !locked else {
                paywallForFeature("remove watermark")
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.mode = mode
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: mode.icon)
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .white : .secondary)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                            .offset(x: 14, y: -10)
                    }
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.red : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.red : Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reset Button

    private func resetButton(action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.red.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

extension WatermarkSettings.Mode {
    var icon: String {
        switch self {
        case .none:              return "text.badge.xmark"
        case .textOnly:          return "text.word.spacing"
        case .textWithTimestamp: return "clock.badge"
        }
    }
}

extension WatermarkSettings.Corner {
    var systemImage: String {
        switch self {
        case .topLeading:     return "arrow.up.left"
        case .topTrailing:    return "arrow.up.right"
        case .bottomLeading:  return "arrow.down.left"
        case .bottomTrailing: return "arrow.down.right"
        }
    }
}

#if DEBUG
struct WatermarkSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WatermarkSettingsView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
