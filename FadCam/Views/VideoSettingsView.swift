import SwiftUI
import AVFoundation

/// Video configuration screen — resolution, frame rate, bitrate.
/// All options derived from real camera hardware capabilities.
struct VideoSettingsView: View {
    @StateObject private var settings = VideoSettings.shared
    @State private var camera: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    @State private var showCustomBitrateDialog = false
    @State private var customBitrateText: String = ""

    var body: some View {
        List {
            // MARK: - Resolution
            Section {
                Picker("Resolution", selection: $settings.selectedResolution) {
                    ForEach(settings.availableResolutions) { res in
                        Text(res.label).tag(res)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.selectedResolution) { res in
                    if let cam = camera {
                        settings.refreshFrameRates(for: res, from: cam.formats)
                    }
                }
            } header: {
                Text("Resolution")
            } footer: {
                Text("Higher resolutions produce sharper video but use more storage.")
            }

            // MARK: - Frame Rate
            if !settings.availableFrameRates.isEmpty {
                Section {
                    Picker("Frame Rate", selection: $settings.selectedFrameRate) {
                        ForEach(settings.availableFrameRates, id: \.self) { fps in
                            Text("\(fps) fps").tag(fps)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Frame Rate")
                } footer: {
                    frameRateFooter
                }
            }

            // MARK: - Bitrate
            Section {
                Picker("Bitrate", selection: $settings.bitrateMode) {
                    Text("Auto").tag(VideoSettings.BitrateMode.auto)
                    Text("Custom").tag(VideoSettings.BitrateMode.custom)
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Video Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if settings.availableResolutions.isEmpty {
                settings.refreshHardwareOptions()
            }
            setTabBar(hidden: true)
        }
        .onDisappear { setTabBar(hidden: false) }
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
