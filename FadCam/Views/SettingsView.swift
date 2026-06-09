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

    var body: some View {
        NavigationView {
            Form {
                // MARK: — Video
                Section {
                    NavigationLink {
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
                } header: { Text("Video") }
                footer: { Text("Resolution, frame rate, and encoding quality.") }

                // MARK: — Recording
                Section {
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
                } header: { Text("Recording") }
                footer: { Text("Auto-save and watermark preferences for recorded media.") }

                // MARK: — Onboarding
                Section {
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
                } header: { Text("Onboarding") }
                footer: { Text("Toggle ON to show onboarding on next app launch. Toggle OFF to cancel.") }

                // MARK: — Information
                Section {
                    Button {
                        showGitHubLink = true
                    } label: {
                        HStack {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        showWebsiteLink = true
                    } label: {
                        HStack {
                            Label("Website", systemImage: "globe")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }

                    NavigationLink {
                        TrashView()
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                } header: { Text("Information") }

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
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if let logo = UIImage(named: "HeaderLogo") {
                        Image(uiImage: logo).resizable().aspectRatio(contentMode: .fit).frame(height: 40)
                    }
                    Text("FadCam").font(.title2.bold())
                    Text("Ad-free. Open source. Dashcam for iOS.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Text("Zero tracking. Zero logs.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundColor(.secondary)
                }
            } header: { Text("App Info") }

            Section {
                HStack {
                    Text("iOS")
                    Spacer()
                    Text(UIDevice.current.systemVersion).foregroundColor(.secondary)
                }
                HStack {
                    Text("Device")
                    Spacer()
                    Text(UIDevice.current.model).foregroundColor(.secondary)
                }
            } header: { Text("System") }

            Section {
                Link(destination: URL(string: "https://github.com/anonfaded/FadCam-iOS")!) {
                    HStack {
                        Text("GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                Link(destination: URL(string: "https://fadcam.fadseclab.com")!) {
                    HStack {
                        Text("Website")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            } header: { Text("Links") }

            Section {
                VStack(spacing: 8) {
                    Text("Made with love by FadSec Lab, Pakistan")
                        .font(.footnote).foregroundColor(.secondary)
                    Text("GNU General Public License v3.0")
                        .font(.caption2).foregroundColor(.secondary).opacity(0.7)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
        .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { SettingsView() }
