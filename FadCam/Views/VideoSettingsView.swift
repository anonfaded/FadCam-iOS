import SwiftUI
import AVFoundation

/// Video configuration screen — resolution, frame rate, bitrate.
/// All options derived from real camera hardware capabilities.
/// Pro features: resolution > 720p, fps > 30, custom bitrate.
struct VideoSettingsView: View {
    @StateObject private var settings = VideoSettings.shared
    @StateObject private var proManager = ProManager.shared
    @State private var camera: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    @State private var showCustomBitrateDialog = false
    @State private var customBitrateText: String = ""
    @State private var showPaywall = false

    var body: some View {
        List {
            // MARK: - Resolution
            Section {
                Picker("Resolution", selection: Binding(
                    get: { settings.selectedResolution },
                    set: { newRes in
                        if newRes.height > ProManager.freeMaxResolutionHeight,
                           !proManager.isPro {
                            showPaywall = true
                            return
                        }
                        settings.selectedResolution = newRes
                    }
                )) {
                    ForEach(settings.availableResolutions) { res in
                        HStack {
                            Text(res.label)
                            if res.height > ProManager.freeMaxResolutionHeight {
                                Image(systemName: proManager.isPro ? "checkmark" : "lock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(proManager.isPro ? .secondary : Color(red: 1.0, green: 0.85, blue: 0.2))
                            }
                        }
                        .tag(res)
                    }
                }
                .pickerStyle(.menu)
                .onChangeCompat(of: settings.selectedResolution) { res in
                    if let cam = camera {
                        settings.refreshFrameRates(for: res, from: cam.formats)
                    }
                }
            } header: {
                Text("Resolution")
            } footer: {
                if proManager.isPro {
                    Text("Higher resolutions produce sharper video but use more storage.")
                } else {
                    Text(freeResolutionsFooter)
                }
            }

            // MARK: - Frame Rate
            if !settings.availableFrameRates.isEmpty {
                Section {
                    Picker("Frame Rate", selection: Binding(
                        get: { settings.selectedFrameRate },
                        set: { newFps in
                            if newFps > ProManager.freeMaxFrameRate,
                               !proManager.isPro {
                                showPaywall = true
                                return
                            }
                            settings.selectedFrameRate = newFps
                        }
                    )) {
                        ForEach(settings.availableFrameRates, id: \.self) { fps in
                            HStack {
                                Text("\(fps) fps")
                                if fps > ProManager.freeMaxFrameRate {
                                    Image(systemName: proManager.isPro ? "checkmark" : "lock.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(proManager.isPro ? .secondary : Color(red: 1.0, green: 0.85, blue: 0.2))
                                }
                            }
                            .tag(fps)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Frame Rate")
                } footer: {
                    if proManager.isPro {
                        frameRateFooter
                    } else {
                        Text("30 fps is free. FadCam Pro unlocks 60, 120, and 240 fps.")
                    }
                }
            }

            // MARK: - Bitrate
            Section {
                Picker("Bitrate", selection: Binding(
                    get: { settings.bitrateMode },
                    set: { newMode in
                        if newMode == .custom, !proManager.isPro {
                            showPaywall = true
                            return
                        }
                        settings.bitrateMode = newMode
                    }
                )) {
                    Text("Auto").tag(VideoSettings.BitrateMode.auto)
                    HStack {
                        Text("Custom")
                        if !proManager.isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.2))
                        }
                    }
                    .tag(VideoSettings.BitrateMode.custom)
                }
                .pickerStyle(.menu)

                if settings.bitrateMode == .auto {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                            .font(.system(size: 13))
                            .padding(.top, 1)
                        Text("iOS will automatically choose the best bitrate for your selected resolution and frame rate. This is the safest option for most users.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.bitrateMode == .custom {
                    Button {
                        customBitrateText = "\(settings.customBitrateMbps)"
                        showCustomBitrateDialog = true
                    } label: {
                        HStack {
                            Text("Value")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(settings.customBitrateMbps) Mbps")
                                .foregroundColor(.red)
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow.opacity(0.7))
                            .font(.system(size: 13))
                            .padding(.top, 1)
                        Text("For \(settings.selectedResolution.shortLabel) at \(settings.selectedFrameRate) fps, we recommend about \(settings.recommendedBitrateMbps) Mbps for a good balance of quality and file size.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Bitrate")
            } footer: {
                Text("Bitrate controls video quality vs file size. Higher values = better quality but larger files.")
            }

            // MARK: - Orientation (Coming Soon)
            Section {
                HStack {
                    Label("Portrait", systemImage: "rectangle.portrait.inset.filled")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("SOON")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            } header: {
                Text("Orientation")
            } footer: {
                Text("Currently fixed to Portrait. Landscape and auto-rotate options coming in a future update.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Video Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if settings.availableResolutions.isEmpty {
                settings.refreshHardwareOptions()
            }
            // Cap non-Pro users to free limits
            if !proManager.isPro {
                if settings.selectedResolution.height > ProManager.freeMaxResolutionHeight {
                    settings.selectedResolution = settings.availableResolutions.first { $0.height <= ProManager.freeMaxResolutionHeight } ?? settings.availableResolutions.first ?? .hd720
                }
                if settings.selectedFrameRate > ProManager.freeMaxFrameRate {
                    settings.selectedFrameRate = ProManager.freeMaxFrameRate
                }
                if settings.bitrateMode == .custom {
                    settings.bitrateMode = .auto
                }
            }
            setTabBar(hidden: true)
        }
        .onDisappear { setTabBar(hidden: false) }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Custom Bitrate", isPresented: $showCustomBitrateDialog) {
            TextField("Mbps (e.g. 8)", text: $customBitrateText)
                .keyboardType(.numberPad)
            Button("Use Recommended (\(settings.recommendedBitrateMbps) Mbps)") {
                settings.customBitrateMbps = settings.recommendedBitrateMbps
            }
            Button("Save") {
                if let v = Int(customBitrateText), v > 0, v <= 100 {
                    settings.customBitrateMbps = v
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a value between 1–100 Mbps.\nRecommended for this setup: \(settings.recommendedBitrateMbps) Mbps")
        }
    }

    private var frameRateFooter: some View {
        let text: String
        switch settings.selectedFrameRate {
        case ...24: text = "Cinematic motion."
        case 25...30: text = "Standard smooth motion. Good for general use."
        case 31...60: text = "Smooth motion. Great for action."
        default: text = "Slow-motion capable. Ideal for sports or detailed analysis."
        }
        return Text(text)
    }

    /// Dynamic footer listing actual Pro resolutions available on this device.
    private var freeResolutionsFooter: String {
        let proResolutions = settings.availableResolutions
            .filter { $0.height > ProManager.freeMaxResolutionHeight }
            .map { $0.shortLabel }
        guard !proResolutions.isEmpty else {
            return "720p is free. No higher resolutions available on this device."
        }
        let list = proResolutions.joined(separator: ", ")
        return "720p is free.  FadCam Pro unlocks \(list)."
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

#if DEBUG
struct VideoSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            VideoSettingsView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
