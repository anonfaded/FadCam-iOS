import SwiftUI
import AVFoundation
import Photos

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var direction = 1
    @State private var cameraGranted = false
    @State private var micGranted = false
    @State private var photoGranted = false

    private let totalPages = 3

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
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let ps = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            photoGranted = (ps == .authorized || ps == .limited)
        }
    }

    // MARK: - Navigation

    private var currentPageView: some View {
        Group {
            switch currentPage {
            case 0: welcomePage
            case 1: permissionsPage
            case 2: donePage
            default: EmptyView()
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == currentPage ? Color.red : Color.white.opacity(0.25))
                    .frame(width: i == currentPage ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
    }

    private func goNext() {
        direction = 1
        withAnimation { currentPage = min(currentPage + 1, totalPages - 1) }
    }

    private func goBack() {
        direction = -1
        withAnimation { currentPage = max(currentPage - 1, 0) }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 60)

            if let logo = UIImage(named: "HeaderLogo") {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 50)
            }

            Text("Welcome to FadCam")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Ad-free. Open source. Dashcam for iOS.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))

            VStack(alignment: .leading, spacing: 18) {
                item(icon: "hand.raised.fill", title: "Zero Tracking",
                     desc: "No analytics, no ads, no data collection ever.")
                item(icon: "lock.shield.fill", title: "100% Private",
                     desc: "All recordings stay on your device.")
                item(icon: "chevron.left.forwardslash.chevron.right", title: "Open Source",
                     desc: "github.com/anonfaded/FadCam-iOS")
                item(icon: "wifi.slash", title: "Works Offline",
                     desc: "No internet required. No servers, no cloud.")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button { goNext() } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(modernButtonBg)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Permissions (Unified)

    private var permissionsPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            VStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red.opacity(0.8))
                Text("Permissions")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("All three permissions are required.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 32)

            VStack(spacing: 16) {
                permissionCard(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Required to record videos.",
                    granted: cameraGranted,
                    onAllow: { await requestCameraDirect() },
                    onSettings: { await requestCameraSettings() }
                )

                permissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Required for audio recording with videos.",
                    granted: micGranted,
                    onAllow: { await requestMicDirect() },
                    onSettings: { await requestMicSettings() }
                )

                permissionCard(
                    icon: "photo.on.rectangle.fill",
                    title: "Photo Library",
                    subtitle: "Required to save recordings. Can be changed later in Settings.",
                    granted: photoGranted,
                    onAllow: { await requestPhotoDirect() },
                    onSettings: { await requestPhotoSettings() }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("Back") { goBack() }
                    .foregroundColor(.white.opacity(0.5))
                    .font(.body)

                Spacer()

                Button("Next") { goNext() }
                    .font(.body.bold())
                    .foregroundColor(cameraGranted && micGranted && photoGranted ? .red : .white.opacity(0.2))
                    .disabled(!cameraGranted || !micGranted || !photoGranted)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        onAllow: @escaping () async -> Void,
        onSettings: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: granted ? icon : icon.replacingOccurrences(of: ".fill", with: ""))
                    .font(.system(size: 18))
                    .foregroundColor(granted ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            } else {
                VStack(spacing: 4) {
                    Button {
                        Task { await onAllow() }
                    } label: {
                        Text("Allow")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    Button {
                        Task { await onSettings() }
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .underline()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func requestCameraDirect() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
        default:
            cameraGranted = true
        }
    }

    private func requestCameraSettings() async {
        if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
    }

    private func requestMicDirect() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
        default:
            micGranted = true
        }
    }

    private func requestMicSettings() async {
        if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
    }

    private func requestPhotoDirect() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .notDetermined:
            let new = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            photoGranted = (new == .authorized || new == .limited)
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
        default:
            photoGranted = true
        }
    }

    private func requestPhotoSettings() async {
        if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
    }

    // MARK: - Done

    private var donePage: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 3)
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.green)
            }

            Text("You're All Set")
                .font(.title.bold())
                .foregroundColor(.white)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                Text("Your privacy is protected. Zero tracking. Zero logs. Open source.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                onComplete()
            } label: {
                Text("Start Using FadCam")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(modernButtonBg)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Helper

    private var modernButtonBg: some View {
        LinearGradient(
            colors: [Color.red.opacity(0.9), Color.red.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func item(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.red.opacity(0.8))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
