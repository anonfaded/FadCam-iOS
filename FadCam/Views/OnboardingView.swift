import SwiftUI
import AVFoundation
import Photos
import UIKit

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var direction = 1
    @State private var cameraGranted = false
    @State private var micGranted = false
    @State private var photoGranted = false
    @State private var cameraChecked = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("resumeOnboarding") private var resumeOnboarding = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                currentPageView
                    .transition(.asymmetric(
                        insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.35), value: currentPage)
                    .id(currentPage)

                Spacer()

                pageIndicator
                    .padding(.bottom, 16)
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
        .onAppear {
            if resumeOnboarding { resumeOnboarding = false }
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            photoGranted = PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
            cameraChecked = true
        }
        .onChange(of: cameraGranted) { granted in if granted { cameraChecked = true } }
    }

    // MARK: - Current Page

    private var currentPageView: some View {
        Group {
            switch currentPage {
            case 0: welcomePage
            case 1: cameraPage
            case 2: microphonePage
            case 3: photoPage
            case 4: donePage
            default: EmptyView()
            }
        }
    }

    // MARK: - Page Indicator (Bottom)

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<5) { i in
                Capsule()
                    .fill(i == currentPage ? Color.red : Color.white.opacity(0.25))
                    .frame(width: i == currentPage ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
    }

    // Helper
    private func goNext() { direction = 1; withAnimation { currentPage = min(currentPage + 1, 4) } }
    private func goBack() { direction = -1; withAnimation { currentPage = max(currentPage - 1, 0) } }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 60)

            if let logo = UIImage(named: "HeaderLogo") {
                Image(uiImage: logo).resizable().aspectRatio(contentMode: .fit).frame(height: 50)
            }

            Text("Welcome to FadCam")
                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)

            Text("Ad-free. Open source. Dashcam for iOS.")
                .font(.subheadline).foregroundColor(.white.opacity(0.6))

            VStack(alignment: .leading, spacing: 18) {
                item(icon: "hand.raised.fill", title: "Zero Tracking", desc: "No analytics, no ads, no data collection ever.")
                item(icon: "lock.shield.fill", title: "100% Private", desc: "All recordings stay on your device.")
                item(icon: "chevron.left.forwardslash.chevron.right", title: "Open Source", desc: "github.com/anonfaded/FadCam-iOS")
                item(icon: "wifi.slash", title: "Works Offline", desc: "No internet required. No servers, no cloud.")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button { goNext() } label: {
                Text("Continue").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.red).cornerRadius(14)
            }
            .padding(.horizontal, 40).padding(.bottom, 8)
        }
    }

    // MARK: - Page 2: Camera (REQUIRED)

    private var cameraPage: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            Image(systemName: cameraGranted ? "camera.fill" : "camera")
                .font(.system(size: 64)).foregroundColor(cameraGranted ? .green : .red)
            Text("Camera Access").font(.title2.bold()).foregroundColor(.white)
            Text("Required to record videos. FadCam cannot work without camera access.")
                .font(.subheadline).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            if cameraChecked && !cameraGranted {
                VStack(spacing: 8) {
                    Text("Permission denied").font(.caption).foregroundColor(.orange)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(.subheadline).foregroundColor(.red)
                }
            }

            if !cameraGranted {
                Button {
                    Task {
                        let s = AVCaptureDevice.authorizationStatus(for: .video)
                        if s == .notDetermined { cameraGranted = await AVCaptureDevice.requestAccess(for: .video) }
                        else if s == .denied || s == .restricted {
                            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
                        } else { cameraGranted = true }
                        cameraChecked = true
                    }
                } label: {
                    Text("Grant Camera Access").font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.red).cornerRadius(14)
                }
                .padding(.horizontal, 40)
            } else {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            }

            Spacer()

            HStack {
                Button("Back") { goBack() }.foregroundColor(.white.opacity(0.5))
                Spacer()
                Button("Next") { goNext() }.font(.body.bold())
                    .foregroundColor(cameraGranted ? .red : .white.opacity(0.2))
                    .disabled(!cameraGranted)
            }
            .padding(.horizontal, 40).padding(.bottom, 8)
        }
    }

    // MARK: - Page 3: Microphone

    private var microphonePage: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            Image(systemName: micGranted ? "mic.fill" : "mic.slash")
                .font(.system(size: 64)).foregroundColor(micGranted ? .green : .red)
            Text("Microphone Access").font(.title2.bold()).foregroundColor(.white)
            Text("Record audio with your videos for a complete capture experience.")
                .font(.subheadline).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            if !micGranted {
                Button {
                    Task {
                        let s = AVCaptureDevice.authorizationStatus(for: .audio)
                        if s == .notDetermined { micGranted = await AVCaptureDevice.requestAccess(for: .audio) }
                        else if s == .denied || s == .restricted {
                            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
                        } else { micGranted = true }
                    }
                } label: {
                    Text("Enable Microphone").font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.red).cornerRadius(14)
                }
                .padding(.horizontal, 40)
            } else {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            }

            Spacer()

            HStack {
                Button("Back") { goBack() }.foregroundColor(.white.opacity(0.5))
                Spacer()
                Button("Next") { goNext() }.font(.body.bold()).foregroundColor(.red)
            }
            .padding(.horizontal, 40).padding(.bottom, 8)
        }
    }

    // MARK: - Page 4: Photo

    private var photoPage: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            Image(systemName: photoGranted ? "photo.on.rectangle.fill" : "photo.on.rectangle")
                .font(.system(size: 64)).foregroundColor(photoGranted ? .green : .red)
            Text("Save to Photos").font(.title2.bold()).foregroundColor(.white)
            Text("Save recordings to your Photos library. Change anytime in Settings.")
                .font(.subheadline).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            if !photoGranted {
                Button {
                    Task {
                        let s = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                        if s == .notDetermined { photoGranted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized }
                        else if s == .denied || s == .restricted {
                            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
                        } else { photoGranted = true }
                    }
                } label: {
                    Text("Enable Photo Access").font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.red).cornerRadius(14)
                }
                .padding(.horizontal, 40)
            } else {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            }

            Spacer()

            HStack {
                Button("Back") { goBack() }.foregroundColor(.white.opacity(0.5))
                Spacer()
                Button("Next") { goNext() }.font(.body.bold()).foregroundColor(.red)
            }
            .padding(.horizontal, 40).padding(.bottom, 8)
        }
    }

    // MARK: - Page 5: Done

    private var donePage: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            ZStack {
                Circle().stroke(Color.green.opacity(0.3), lineWidth: 3).frame(width: 100, height: 100)
                Image(systemName: "checkmark").font(.system(size: 44, weight: .bold)).foregroundColor(.green)
            }

            Text("You're All Set").font(.title.bold()).foregroundColor(.white)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 2)
                Text("Your privacy is protected. Zero tracking. Zero logs. Open source.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("Start Using FadCam").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.red).cornerRadius(14)
            }
            .padding(.horizontal, 40).padding(.bottom, 8)
        }
    }

    // MARK: - Helper

    private func item(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundColor(.red.opacity(0.8)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundColor(.white)
                Text(desc).font(.caption).foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

#Preview { OnboardingView() }
