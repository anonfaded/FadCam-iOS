import SwiftUI
import AVFoundation

struct HomeView: View {
    @ObservedObject var cameraVM: CameraViewModel
    @Binding var selectedTab: Int
    @Environment(\.scenePhase) var scenePhase
    @State private var lastZoomValue: CGFloat = 1.0
    @State private var selectedTopTab: TopTab = .fadCam
    @State private var showFullscreenPreview = false

    enum TopTab: String, CaseIterable, Identifiable {
        case fadCam = "FadCam", fadRec = "FadRec", fadMic = "FadMic"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraVM.isPermissionGranted {
                VStack(spacing: 10) {
                    topBar
                    segmentedTabs
                    cardGrid
                    previewArea
                    actionBar
                }
                .padding(.top, 6)
                .padding(.bottom, 8)
            } else {
                permissionDeniedView
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if cameraVM.isPreviewActive {
                        let newZoom = lastZoomValue * value
                        cameraVM.updateZoom(newZoom)
                    }
                }
                .onEnded { _ in
                    lastZoomValue = cameraVM.zoomFactor
                }
        )
        .onAppear {
            cameraVM.checkPermissions()
            if cameraVM.isPermissionGranted && !cameraVM.isCameraReady {
                cameraVM.setupCamera()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if cameraVM.isPermissionGranted && cameraVM.isPreviewActive {
                    cameraVM.startSession()
                }
            case .background:
                if cameraVM.recordingState == .recording { cameraVM.stopRecording() }
                if cameraVM.isPreviewActive { cameraVM.stopSession() }
            default: break
            }
        }
        .alert("Recording Error", isPresented: .constant(cameraVM.errorMessage != nil)) {
            Button("OK") { cameraVM.errorMessage = nil }
        } message: {
            Text(cameraVM.errorMessage ?? "")
        }
        .fullScreenCover(isPresented: $showFullscreenPreview) {
            FullscreenPreviewView(cameraVM: cameraVM)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            // Centered logo - truly centered
            if let logo = UIImage(named: "HeaderLogo") {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
            } else {
                Text("FadCam")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
            }

            HStack {
                // Left: Hamburger menu
                Button { } label: {
                    Image(systemName: "line.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                Spacer()
                // Right: Pro badge
                Button { } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill").font(.system(size: 10))
                        Text("Pro").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.2), Color(red: 1.0, green: 0.7, blue: 0.0)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Segmented Tabs

    @Namespace private var tabNamespace

    private var segmentedTabs: some View {
        HStack(spacing: 0) {
            ForEach(TopTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTopTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selectedTopTab == tab ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedTopTab == tab {
                                    Capsule().fill(Color.red).matchedGeometryEffect(id: "tab", in: tabNamespace)
                                }
                            }
                        )
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .padding(.horizontal, 14)
    }

    // MARK: - Card Grid (2 columns)

    private var cardGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            statusCard
            VStack(spacing: 8) {
                timeCard
                videosCard
            }
        }
        .padding(.horizontal, 14)
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                iconCircle("video.fill", color: .green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cameraVM.currentCamera == .back ? "Back Camera" : "Front Camera")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    Text("4K · 30fps · Portrait")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }
            divider
            HStack(spacing: 8) {
                iconCircle("hourglass", color: .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cameraVM.estimatedRecordingTime)
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.red)
                    Text("Time left")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }
            divider
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 3).frame(width: 30, height: 30)
                    Circle()
                        .trim(from: 0, to: storageFreeRatio)
                        .stroke(storageMeterColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(storageFreeRatio * 100))%")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        Text(ByteCountFormatter.string(fromByteCount: cameraVM.availableStorage?.free ?? 0, countStyle: .file))
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        Text("free")
                            .font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
                    }
                    Text("of \(ByteCountFormatter.string(fromByteCount: cameraVM.availableStorage?.total ?? 0, countStyle: .file))")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.vertical, 6)
    }

    private func iconCircle(_ icon: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.2)).frame(width: 28, height: 28)
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
        }
    }

    // MARK: - Time Card (live clock + Hijri)

    private var timeCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(timeString(context.date))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(dateString(context.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Text(hijriDateString(context.date))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "clock.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.65, green: 0.1, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Videos Card (navigates to records)

    private var videosCard: some View {
        Button {
            selectedTab = 1
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.2)).frame(width: 28, height: 28)
                    Image(systemName: "folder.fill").font(.system(size: 12)).foregroundColor(.red)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("Files:").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                        Text("\(cameraVM.totalMediaCount)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    }
                    HStack(spacing: 3) {
                        Text("Used:").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                        Text(ByteCountFormatter.string(fromByteCount: cameraVM.fadCamStorageBytes, countStyle: .file))
                            .font(.system(size: 10, weight: .medium)).foregroundColor(.white)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.3))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview Area (camera feed OR mascot)

    private var previewArea: some View {
        ZStack {
            if cameraVM.isPreviewActive {
                CameraPreview(session: cameraVM.cameraService.session)
                    .scaleEffect(cameraVM.zoomFactor)
                Color.black.opacity(0.001)

                if cameraVM.recordingState == .recording || cameraVM.isPaused {
                    VStack {
                        HStack(spacing: 6) {
                            if !cameraVM.isPaused {
                                RecordingDot()
                            } else {
                                Circle().fill(.orange).frame(width: 10, height: 10)
                            }
                            Text(cameraVM.isPaused ? "PAUSED" : formatTime(cameraVM.elapsedTime))
                                .font(.system(size: 12, design: .monospaced).weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.top, 8)
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            if cameraVM.zoomFactor > 1.1 {
                                Button {
                                    cameraVM.updateZoom(1.0)
                                    lastZoomValue = 1.0
                                } label: {
                                    Text("\(String(format: "%.1f", cameraVM.zoomFactor))x")
                                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.red.opacity(0.8))
                                        .clipShape(Capsule())
                                }
                            }
                            HStack(spacing: 6) {
                                previewActionButton(
                                    icon: cameraVM.isBatterySaverActive ? "moon.fill" : "moon",
                                    label: "Saver"
                                ) {
                                    cameraVM.toggleBatterySaver()
                                }
                                .opacity(cameraVM.recordingState == .recording ? 1 : 0.4)
                                .disabled(cameraVM.recordingState != .recording)
                                previewActionButton(icon: "camera.fill", label: "FadShot") {
                                    cameraVM.capturePhoto()
                                }
                                .opacity(cameraVM.isPreviewActive ? 1 : 0.4)
                                .disabled(!cameraVM.isPreviewActive)
                                previewActionButton(icon: "rectangle.expand.vertical", label: "Full") {
                                    showFullscreenPreview = true
                                }
                                .opacity(cameraVM.isPreviewActive ? 1 : 0.4)
                                .disabled(!cameraVM.isPreviewActive)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 8)
                }
            } else {
                mascotView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if cameraVM.recordingState == .recording {
                cameraVM.toggleBatterySaver()
            } else {
                cameraVM.togglePreview()
            }
        }
    }

    private var mascotView: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.04, blue: 0.08), Color(red: 0.02, green: 0.02, blue: 0.04)], startPoint: .top, endPoint: .bottom)

            starfield
            crescentMoon
                .position(x: 50, y: 50)
            sparkles
            sleepingMoon

            VStack {
                Spacer()
                // "Hold to wake up" text above the buttons
                Text("Hold to wake up the camera")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.bottom, 8)

                // FadShot + Full buttons at bottom-right (dimmed when preview off)
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        previewActionButton(icon: "camera.fill", label: "FadShot") { }
                            .opacity(0.4)
                            .disabled(true)
                        previewActionButton(icon: "rectangle.expand.vertical", label: "Full") { }
                            .opacity(0.4)
                            .disabled(true)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
    }

    private var starfield: some View {
        GeometryReader { geo in
            ZStack {
                let positions: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.1, 0.15, 1.5), (0.85, 0.1, 1.0), (0.5, 0.3, 2.0),
                    (0.2, 0.5, 1.2), (0.75, 0.6, 1.8), (0.4, 0.8, 1.0),
                    (0.9, 0.4, 1.3), (0.05, 0.7, 1.1), (0.6, 0.15, 1.6),
                    (0.3, 0.35, 1.0), (0.8, 0.85, 1.4), (0.15, 0.9, 1.0),
                    (0.7, 0.25, 1.7), (0.45, 0.6, 1.2), (0.25, 0.75, 1.5),
                    (0.55, 0.45, 1.0), (0.95, 0.7, 1.3), (0.1, 0.4, 1.1),
                    (0.65, 0.9, 1.0), (0.35, 0.2, 1.6), (0.85, 0.55, 1.2)
                ]
                ForEach(0..<positions.count, id: \.self) { i in
                    let pos = positions[i]
                    Circle()
                        .fill(Color.white.opacity(Double(pos.2) * 0.15))
                        .frame(width: pos.2, height: pos.2)
                        .position(x: geo.size.width * pos.0, y: geo.size.height * pos.1)
                }
            }
        }
    }

    private var crescentMoon: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.15)).frame(width: 44, height: 44)
            Circle().fill(Color(red: 0.04, green: 0.03, blue: 0.06)).frame(width: 36, height: 36).offset(x: 12, y: -3)
        }
    }

    private var sparkles: some View {
        GeometryReader { geo in
            ZStack {
                Image(systemName: "sparkle").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                    .position(x: geo.size.width * 0.25, y: geo.size.height * 0.25)
                Image(systemName: "sparkle").font(.system(size: 7)).foregroundColor(.white.opacity(0.3))
                    .position(x: geo.size.width * 0.7, y: geo.size.height * 0.2)
                Image(systemName: "sparkle").font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
                    .position(x: geo.size.width * 0.15, y: geo.size.height * 0.7)
                Image(systemName: "sparkle").font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.75)
                Image(systemName: "sparkle").font(.system(size: 6)).foregroundColor(.white.opacity(0.4))
                    .position(x: geo.size.width * 0.6, y: geo.size.height * 0.45)
                Text("zZ").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    .position(x: geo.size.width * 0.62, y: geo.size.height * 0.32)
            }
        }
    }

    private var sleepingMoon: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [Color(red: 0.5, green: 0.5, blue: 0.55), Color(red: 0.25, green: 0.25, blue: 0.3)]), center: .topLeading, startRadius: 5, endRadius: 100))
                .frame(width: 95, height: 95)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
            HStack(spacing: 18) {
                Capsule().fill(.black).frame(width: 12, height: 3)
                Capsule().fill(.black).frame(width: 12, height: 3)
            }
            .offset(y: -6)
            Capsule().fill(.black).frame(width: 16, height: 2.5).offset(y: 10)
        }
    }

    private func previewActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                Text(label).font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.85))
            }
            .frame(width: 44, height: 38)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    // MARK: - Action Bar (Torch | Start/Stop | Pause/Resume)

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                cameraVM.toggleTorch()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: cameraVM.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16))
                    .foregroundColor(cameraVM.isTorchOn ? .yellow : .white.opacity(0.8))
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(cameraVM.isTorchOn ? .yellow.opacity(0.4) : .clear, lineWidth: 1))
            }

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                switch cameraVM.recordingState {
                case .ready:
                    cameraVM.startRecording()
                case .recording:
                    cameraVM.stopRecording()
                    cameraVM.isPaused = false
                case .error:
                    cameraVM.recordingState = .ready
                }
            } label: {
                ZStack {
                    Capsule().fill(
                        LinearGradient(
                            colors: cameraVM.recordingState == .recording
                                ? [Color.red, Color(red: 0.7, green: 0.1, blue: 0.1)]
                                : [Color(red: 0.3, green: 0.7, blue: 0.35), Color(red: 0.2, green: 0.55, blue: 0.25)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    HStack(spacing: 6) {
                        Image(systemName: cameraVM.recordingState == .recording ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(cameraVM.recordingState == .recording ? "Stop" : "Start")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
                .frame(height: 50)
                .shadow(color: cameraVM.recordingState == .recording ? .red.opacity(0.3) : .green.opacity(0.3), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                togglePauseResume()
            } label: {
                Image(systemName: cameraVM.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: cameraVM.recordingState == .recording
                                ? (cameraVM.isPaused
                                    ? [Color(red: 0.3, green: 0.7, blue: 0.35), Color(red: 0.2, green: 0.55, blue: 0.25)]
                                    : [Color(red: 0.85, green: 0.55, blue: 0.15), Color(red: 0.7, green: 0.4, blue: 0.1)])
                                : [Color.white.opacity(0.08), Color.white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(Circle())
            }
            .opacity(cameraVM.recordingState == .recording || cameraVM.isPaused ? 1 : 0.4)
            .disabled(cameraVM.recordingState != .recording && !cameraVM.isPaused)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.fill").font(.system(size: 48)).foregroundColor(.gray)
            Text("Camera Access Required").font(.title2).foregroundColor(.white)
            Text("Camera access is required to record videos. Please enable it in Settings.")
                .foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent).tint(.red)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var storageFreeRatio: Double {
        guard let s = cameraVM.availableStorage, s.total > 0 else { return 0 }
        return min(Double(s.free) / Double(s.total), 1.0)
    }

    private var storageMeterColor: Color {
        let ratio = storageFreeRatio
        if ratio < 0.15 { return .red }
        if ratio < 0.30 { return .orange }
        return .green
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: date)
    }

    private func hijriDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamic)
        f.locale = Locale(identifier: "ar")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    private func togglePauseResume() {
        if cameraVM.isPaused {
            cameraVM.resumeRecording()
        } else if cameraVM.recordingState == .recording {
            cameraVM.pauseRecording()
        }
    }
}

// MARK: - Fullscreen Preview

struct FullscreenPreviewView: View {
    @ObservedObject var cameraVM: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var lastZoomValue: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: cameraVM.cameraService.session)
                .ignoresSafeArea()
                .scaleEffect(cameraVM.zoomFactor)

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)

                if cameraVM.recordingState == .recording || cameraVM.isPaused {
                    HStack(spacing: 6) {
                        if !cameraVM.isPaused {
                            RecordingDot()
                        } else {
                            Circle().fill(.orange).frame(width: 10, height: 10)
                        }
                        Text(cameraVM.isPaused ? "PAUSED" : formatTime(cameraVM.elapsedTime))
                            .font(.system(size: 16, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 16)
                }

                Spacer()

                // Photo controls row (FadShot)
                HStack(spacing: 0) {
                    // Torch
                    Button {
                        cameraVM.toggleTorch()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cameraVM.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 20))
                            Text("Torch").font(.system(size: 10))
                        }
                        .foregroundColor(cameraVM.isTorchOn ? .yellow : .white)
                        .frame(maxWidth: .infinity)
                    }

                    // Flip
                    Button {
                        cameraVM.switchCamera()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.system(size: 20))
                            Text("Flip").font(.system(size: 10))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }

                    // FadShot
                    Button {
                        cameraVM.capturePhoto()
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().stroke(Color.white, lineWidth: 3).frame(width: 50, height: 50)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            Text("FadShot").font(.system(size: 10))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .opacity(cameraVM.isPreviewActive ? 1 : 0.4)
                    .disabled(!cameraVM.isPreviewActive)

                    // Saver (during recording)
                    Button {
                        if cameraVM.recordingState == .recording {
                            cameraVM.toggleBatterySaver()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cameraVM.isBatterySaverActive ? "moon.fill" : "moon")
                                .font(.system(size: 20))
                            Text("Saver").font(.system(size: 10))
                        }
                        .foregroundColor(cameraVM.isBatterySaverActive ? .red : .white)
                        .frame(maxWidth: .infinity)
                    }
                    .opacity(cameraVM.recordingState == .recording ? 1 : 0.4)
                    .disabled(cameraVM.recordingState != .recording)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.3))

                // Video controls row
                HStack(spacing: 16) {
                    // Pause/Resume
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        togglePauseResume()
                    } label: {
                        Image(systemName: cameraVM.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                LinearGradient(
                                    colors: cameraVM.recordingState == .recording
                                        ? (cameraVM.isPaused
                                            ? [Color(red: 0.3, green: 0.7, blue: 0.35), Color(red: 0.2, green: 0.55, blue: 0.25)]
                                            : [Color(red: 0.85, green: 0.55, blue: 0.15), Color(red: 0.7, green: 0.4, blue: 0.1)])
                                        : [Color.white.opacity(0.1), Color.white.opacity(0.1)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .clipShape(Circle())
                    }
                    .opacity(cameraVM.recordingState == .recording || cameraVM.isPaused ? 1 : 0.4)
                    .disabled(cameraVM.recordingState != .recording && !cameraVM.isPaused)

                    // Record/Stop (big button)
                    Button {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        switch cameraVM.recordingState {
                        case .ready:
                            cameraVM.startRecording()
                        case .recording:
                            cameraVM.stopRecording()
                        case .error:
                            cameraVM.recordingState = .ready
                        }
                    } label: {
                        ZStack {
                            Circle().stroke(Color.white, lineWidth: 4).frame(width: 70, height: 70)
                            if cameraVM.recordingState == .recording {
                                RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 28, height: 28)
                            } else {
                                Circle().fill(Color.red).frame(width: 54, height: 54)
                            }
                        }
                    }
                    .disabled(!cameraVM.isPreviewActive)

                    // Zoom reset (if zoomed)
                    if cameraVM.zoomFactor > 1.1 {
                        Button {
                            cameraVM.updateZoom(1.0)
                            lastZoomValue = 1.0
                        } label: {
                            Text("\(String(format: "%.1f", cameraVM.zoomFactor))x")
                                .font(.system(size: 14, design: .monospaced).weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.red.opacity(0.8))
                                .clipShape(Circle())
                        }
                    } else {
                        Color.clear.frame(width: 50, height: 50)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.4))
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newZoom = lastZoomValue * value
                    cameraVM.updateZoom(newZoom)
                }
                .onEnded { _ in
                    lastZoomValue = cameraVM.zoomFactor
                }
        )
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    private func togglePauseResume() {
        if cameraVM.isPaused {
            cameraVM.resumeRecording()
        } else if cameraVM.recordingState == .recording {
            cameraVM.pauseRecording()
        }
    }
}

// MARK: - Shared Subviews

struct RecordingDot: View {
    @State private var dim = false
    var body: some View {
        Circle().fill(.red).frame(width: 10, height: 10).opacity(dim ? 0.3 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true } }
    }
}

#Preview {
    HomeView(cameraVM: CameraViewModel(), selectedTab: .constant(0))
}
