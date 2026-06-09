import SwiftUI
import AVFoundation

/// Video configuration screen — resolution, frame rate, bitrate.
/// All options come from real camera hardware capabilities.
struct VideoSettingsView: View {
    @StateObject private var settings = VideoSettings.shared
    @State private var camera: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

    var body: some View {
        List {
            // MARK: - Resolution
            Section {
                ForEach(settings.availableResolutions) { res in
                    Button {
                        settings.selectedResolution = res
                        if let cam = camera {
                            settings.refreshFrameRates(for: res, from: cam.formats)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(res.shortLabel)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("\(res.width)×\(res.height)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if settings.selectedResolution == res {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
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
                    ForEach(settings.availableFrameRates, id: \.self) { fps in
                        Button {
                            settings.selectedFrameRate = fps
                        } label: {
                            HStack {
                                Text("\(fps) fps")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                if settings.selectedFrameRate == fps {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Frame Rate")
                } footer: {
                    frameRateFooter
                }
            }

            // MARK: - Bitrate
            Section {
                ForEach(VideoSettings.Bitrate.allCases) { br in
                    Button {
                        settings.selectedBitrate = br
                    } label: {
                        HStack {
                            Text(br.label)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            if settings.selectedBitrate == br {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Bitrate")
            } footer: {
                Text("Auto lets the system choose. Manual caps affect quality vs file size. Higher = better quality, bigger files.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Video Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if settings.availableResolutions.isEmpty {
                settings.refreshHardwareOptions()
            }
        }
    }

    private var frameRateFooter: some View {
        Group {
            if settings.selectedFrameRate <= 30 {
                Text("Standard motion. Good for general use and smaller files.")
            } else if settings.selectedFrameRate <= 60 {
                Text("Smooth motion. Great for capturing action.")
            } else {
                Text("Slow-motion capable. Ideal for sports or detailed movement analysis.")
            }
        }
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
