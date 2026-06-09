import SwiftUI
import Combine

/// Dedicated watermark customization screen with sticky live preview.
struct WatermarkSettingsView: View {
    @StateObject private var settings = WatermarkSettings.shared
    @State private var previewTimestamp = Date()
    @State private var hostingTabBar: UITabBar?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
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
                    }

                    // Shadow
                    Toggle(isOn: $settings.shadowEnabled) {
                        Label("Drop Shadow", systemImage: "circle.fill")
                    }
                    .tint(.red)
                } header: {
                    Text("Appearance")
                } footer: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Tap to reset any setting to its default.  A drop shadow helps readability on bright scenes.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Live Preview")
                        .font(.footnote)
                        .textCase(.uppercase)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Card
                livePreviewCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .padding(.bottom, 4)
            .background(.bar)
        }
        .navigationTitle("Watermark")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(timer) { _ in
            previewTimestamp = Date()
        }
        .onAppear {
            hostingTabBar?.isHidden = true
        }
        .onDisappear {
            hostingTabBar?.isHidden = false
        }
        .background(HostingTabBarFinder(hostingTabBar: $hostingTabBar))
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
        .padding(10)
    }

    private var previewWatermarkLabel: some View {
        let fontSize = previewFontSize
        let brand = WatermarkSettings.brandPrefix
        let hasTs = settings.mode == .textWithTimestamp
        return Group {
            if let logo = UIImage(named: "HeaderLogo") {
                (Text(brand)
                    .font(.system(size: fontSize, weight: .semibold))
                + Text(" ")  // spacing before logo
                + Text(Image(uiImage: logo)).baselineOffset(-fontSize * 0.15)
                + (hasTs
                    ? Text(" - " + timestampString)
                        .font(.system(size: fontSize, weight: .regular))
                    : Text("")))
            } else {
                (Text("Captured by FadCam")
                    .font(.system(size: fontSize, weight: .semibold))
                + (hasTs
                    ? Text(" - " + timestampString)
                        .font(.system(size: fontSize, weight: .regular))
                    : Text("")))
            }
        }
        .foregroundColor(.white.opacity(settings.opacity))
        .shadow(
            color: settings.shadowEnabled ? .black.opacity(0.5) : .clear,
            radius: settings.shadowEnabled ? 2 : 0,
            x: settings.shadowEnabled ? 1 : 0,
            y: settings.shadowEnabled ? 1 : 0
        )
    }

    private var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = WatermarkSettings.timestampFormat
        return formatter.string(from: previewTimestamp)
    }

    /// Scaled font size for the preview card.
    private var previewFontSize: CGFloat {
        max(8, settings.fontSize * 0.3)
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
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.mode = mode
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22))
                    .foregroundColor(settings.mode == mode ? .white : .secondary)
                Text(mode.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(settings.mode == mode ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(settings.mode == mode ? Color.red : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(settings.mode == mode ? Color.red : Color(.systemGray4), lineWidth: 1)
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

// MARK: - TabBar Hider (per-instance, not global)

private struct HostingTabBarFinder: UIViewRepresentable {
    @Binding var hostingTabBar: UITabBar?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        DispatchQueue.main.async {
            var responder: UIResponder? = view
            while let r = responder {
                if let tabBarController = r as? UITabBarController {
                    hostingTabBar = tabBarController.tabBar
                    break
                }
                if let nav = r as? UINavigationController,
                   let tabBarController = nav.tabBarController {
                    hostingTabBar = tabBarController.tabBar
                    break
                }
                responder = r.next
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
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
