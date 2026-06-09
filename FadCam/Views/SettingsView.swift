import SwiftUI
import Photos

struct SettingsView: View {
    @AppStorage("saveToPhotos") private var saveToPhotos = false
    @AppStorage("resumeOnboarding") private var resumeOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @StateObject private var watermarkSettings = WatermarkSettings.shared
    @StateObject private var videoSettings = VideoSettings.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showGitHubLink = false
    @State private var showWebsiteLink = false
    @State private var pushVideoSettings = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: — Camera
                Section {
                    NavigationLink(isActive: $pushVideoSettings) {
                        VideoSettingsView()
                    } label: {
                        HStack {
                            Label("Video", systemImage: "video.fill")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(videoSettings.selectedResolution.shortLabel)")
                                    .font(.subheadline)
                                Text("\(videoSettings.selectedFrameRate) fps")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $saveToPhotos) {
                        Label("Save to Photos", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: saveToPhotos) { newValue in if newValue { requestPhotoPermission() } }
                    .tint(.red)

                    NavigationLink {
                        WatermarkSettingsView()
                    } label: {
                        HStack {
                            Label("Watermark", systemImage: "text.word.spacing")
                            Spacer()
                            Text(watermarkSettings.mode.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: { Text("Camera") }
                footer: { Text("Select video resolution and frame rate. When enabled, recordings are automatically saved to the Photos app. Customize the watermark overlay.") }

                // MARK: — App Info
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }

                    Toggle(isOn: $resumeOnboarding) {
                        Label("Show Onboarding Again", systemImage: "arrow.counterclockwise")
                    }
                    .onChange(of: resumeOnboarding) { newValue in
                        if newValue {
                            hasCompletedOnboarding = false
                        } else {
                            hasCompletedOnboarding = true
                        }
                    }
                    .tint(.red)

                    Button {
                        showGitHubLink = true
                    } label: {
                        HStack {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }

                    Button {
                        showWebsiteLink = true
                    } label: {
                        HStack {
                            Label("Website", systemImage: "globe")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                } header: { Text("App Info") }
                footer: { Text("Toggle ON to show onboarding on next app launch. Toggle OFF to cancel.") }

                // MARK: — Danger Zone
                Section {
                    NavigationLink {
                        TrashView()
                    } label: {
                        HStack {
                            Label("Trash", systemImage: "trash.fill")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.5))
                        }
                    }
                } header: { Text("Danger Zone") }
                footer: { Text("Recover or permanently delete trashed recordings.") }

                // MARK: — Footer
                Section {
                    VStack(spacing: 8) {
                        if let logo = UIImage(named: "HeaderLogo") {
                            Image(uiImage: logo).resizable().aspectRatio(contentMode: .fit).frame(height: 24).opacity(0.5)
                        }
                        Button {
                            if let url = URL(string: "https://fadcam.fadseclab.com") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text(verbatim: "https://fadcam.fadseclab.com")
                                .font(.footnote)
                                .foregroundColor(.red.opacity(0.7))
                        }
                        Text("Made with \u{2764}\u{FE0F} by FadSec Lab in \u{1F1F5}\u{1F1F0}")
                            .font(.footnote).foregroundColor(.secondary)
                        Text("\u{00A9} 2024\u{2013}2026  \u{2022}  GPLv3 License")
                            .font(.caption2).foregroundColor(.secondary).opacity(0.7)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .navigationTitle("Settings")
            .onReceive(NotificationCenter.default.publisher(for: .openVideoSettings)) { _ in
                pushVideoSettings = true
            }
            .sheet(isPresented: $showGitHubLink) {
                LinkPreviewView(
                    url: URL(string: "https://github.com/anonfaded/FadCam-iOS")!,
                    title: "FadCam iOS Source Code"
                )
            }
            .sheet(isPresented: $showWebsiteLink) {
                LinkPreviewView(
                    url: URL(string: "https://fadcam.fadseclab.com")!,
                    title: "FadCam Website"
                )
            }
            .alert("Permission Required", isPresented: $showingAlert) {
                Button("Cancel", role: .cancel) { saveToPhotos = false }
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: { Text(alertMessage) }
        }
    }

    private func requestPhotoPermission() {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: break
        case .notDetermined:
            Task {
                if await PHPhotoLibrary.requestAuthorization(for: .addOnly) != .authorized {
                    await MainActor.run {
                        saveToPhotos = false
                        alertMessage = "Photo library access needed."
                        showingAlert = true
                    }
                }
            }
        case .denied, .restricted:
            saveToPhotos = false
            alertMessage = "Access denied. Enable in Settings."
            showingAlert = true
        @unknown default: break
        }
    }
}

enum TrashAutoDeleteOption: String, CaseIterable, Identifiable {
    case immediately
    case oneHour
    case fiveHours
    case tenHours
    case oneDay
    case sevenDays
    case thirtyDays
    case sixtyDays
    case ninetyDays
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneHour: return "After 1 hour"
        case .fiveHours: return "After 5 hours"
        case .tenHours: return "After 10 hours"
        case .oneDay: return "After 1 day"
        case .sevenDays: return "After 7 days"
        case .thirtyDays: return "After 30 days (Default)"
        case .sixtyDays: return "After 60 days"
        case .ninetyDays: return "After 90 days"
        case .never: return "Never"
        }
    }

    var seconds: Int {
        switch self {
        case .immediately: return 0
        case .oneHour: return 3600
        case .fiveHours: return 18000
        case .tenHours: return 36000
        case .oneDay: return 86400
        case .sevenDays: return 604800
        case .thirtyDays: return 2592000
        case .sixtyDays: return 5184000
        case .ninetyDays: return 7776000
        case .never: return -1
        }
    }
}

struct AboutView: View {
    @State private var copied = false

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
        ?? "FadCam"
    }
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.fadseclab.fadcam"
    }

    /// Tries to load the primary app icon from the bundle.
    private var appIconImage: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last {
            return UIImage(named: last)
        }
        // Fallback: try the asset catalog name
        return UIImage(named: "AppIcon")
    }

    private var allInfoText: String {
        """
        \(appName)
        Version \(version) (Build \(build))
        Bundle ID: \(bundleID)
        iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)
        Licensed under GNU GPL v3.0
        Made with love by FadSec Lab, Pakistan
        """
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if let icon = appIconImage {
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text(appName)
                        .font(.title2.bold())
                    Text("Ad-free. Open source. Dashcam & Bodycam for iOS.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                row("Version", version)
                row("Build", build)
                row("Bundle ID", bundleID)
            } header: { Text("App Info") }

            Section {
                row("iOS", UIDevice.current.systemVersion)
                row("Device", UIDevice.current.model)
            } header: { Text("System") }

            Section {
                Button {
                    UIPasteboard.general.string = allInfoText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack {
                        if copied {
                            Label("Copied", systemImage: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Label("Copy All Info", systemImage: "doc.on.doc")
                        }
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setTabBar(hidden: true) }
        .onDisappear { setTabBar(hidden: false) }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }

    private func setTabBar(hidden: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            if let tab = findTab(from: root) { tab.tabBar.isHidden = hidden }
        }
    }

    private func findTab(from vc: UIViewController) -> UITabBarController? {
        if let t = vc as? UITabBarController { return t }
        if let t = vc.tabBarController { return t }
        for child in vc.children { if let f = findTab(from: child) { return f } }
        return nil
    }
}

#Preview { SettingsView() }
