import SwiftUI
import AVFoundation

// MARK: - Custom 2-Line Hamburger Icon

struct HamburgerLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let lineH: CGFloat = 2
        let spacing: CGFloat = 5
        // Top line — full width
        path.addRoundedRect(in: CGRect(x: 0, y: (h - lineH * 2 - spacing) / 2, width: w, height: lineH), cornerSize: CGSize(width: 1, height: 1))
        // Bottom line — 60% width, left-aligned (space on the right)
        let bottomW = w * 0.6
        path.addRoundedRect(in: CGRect(x: 0, y: (h - lineH * 2 - spacing) / 2 + lineH + spacing, width: bottomW, height: lineH), cornerSize: CGSize(width: 1, height: 1))
        return path
    }
}

/// A rectangle with rounded corners only on the right (trailing) side.
struct RightRoundedRectangle: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct HomeView: View {
    @ObservedObject var cameraVM: CameraViewModel
    @Binding var selectedTab: Int
    @Environment(\.scenePhase) var scenePhase
    @State private var lastZoomValue: CGFloat = 1.0
    @State private var selectedTopTab: TopTab = .fadCam

    // Drawer
    @State private var showDrawer = false
    @State private var drawerDragOffset: CGFloat = 0
    @State private var showDiscordLink = false
    @State private var showWebsiteLink = false
    @AppStorage("previewAreaEnabled") private var previewAreaEnabled = true

    // Sleeping avatar animations (matching Android AVD flow)
    @State private var breathingOpacity: Double = 0.80
    @State private var breathingScale: Double = 1.0
    @State private var z1Float: CGFloat = 0
    @State private var z2Float: CGFloat = 0
    @State private var z3Float: CGFloat = 0
    /// Eye vertical offset: 2 = sleeping, -8 = awake (eyes rise UP during wake)
    @State private var eyeOffsetY: Double = 2
    /// Eye brightness: 0 = dark #2a2a2a, 1 = white #ffffff
    @State private var eyeBrightness: Double = 0
    /// Glow opacity: 0 = hidden, 1 = full neon bloom
    @State private var eyeGlowOpacity: Double = 0
    /// Avatar scale during transitions
    @State private var avatarScale: Double = 1.0
    /// Avatar opacity during transitions
    @State private var avatarOpacity: Double = 1.0
    /// Iris reveal: 0 = closed, 1 = fully open
    @State private var irisProgress: CGFloat = 0
    /// Whether camera preview is active
    @State private var showCameraPreview = false
    /// Blocks re-entrant taps during animation
    @State private var isTransitioning = false
    /// Size of the preview area for iris calculations
    @State private var previewSize: CGSize = .zero
    /// True when preview was auto-opened by recording start (auto-close on stop)
    @State private var previewAutoOpened = false
    /// Suppresses onChange(isPreviewActive) handler during internal toggle
    @State private var isInternalToggle = false

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
        .overlay {
            if showDrawer {
                drawerOverlay
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDrawer)
        .sheet(isPresented: $showDiscordLink) {
            LinkPreviewView(
                url: URL(string: "https://discord.gg/kvAZvdkuuN")!,
                title: "FadCam Discord"
            )
        }
        .sheet(isPresented: $showWebsiteLink) {
            LinkPreviewView(
                url: URL(string: "https://fadcam.fadseclab.com")!,
                title: "FadCam Website"
            )
        }
    }

    // MARK: - Drawer

    private var drawerOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(showDrawer ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismissDrawer() }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button { dismissDrawer() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 30, height: 30)
                    }
                    Text("Home Options")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 54)
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text("PREVIEW")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    HStack {
                        Label("Preview Area", systemImage: "eye.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $previewAreaEnabled)
                            .labelsHidden()
                            .tint(.red)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)

                    Text("When disabled, recording will not auto-open the preview area.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer()

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 20)

                Button { showDiscordLink = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Discord")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                }

                VStack(spacing: 6) {
                    Button { showWebsiteLink = true } label: {
                        Text(verbatim: "https://fadcam.fadseclab.com")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    Text("Made with \u{2764}\u{FE0F} by FadSec Lab in \u{1F1F5}\u{1F1F0}")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\u{00A9} 2024\u{2013}2026  \u{2022}  GPLv3 License")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 36)
            }
            .frame(width: 300)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.07),
                        Color(red: 0.02, green: 0.02, blue: 0.03),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .clipShape(RightRoundedRectangle(radius: 24))
            .offset(x: drawerDragOffset)
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { val in
                    drawerDragOffset = min(0, val.translation.width)
                }
                .onEnded { val in
                    if val.predictedEndTranslation.width < -80 {
                        dismissDrawer()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            drawerDragOffset = 0
                        }
                    }
                }
        )
    }

    private func dismissDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showDrawer = false
            drawerDragOffset = 0
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
                // Left: Hamburger — custom 2-line icon
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showDrawer.toggle()
                    }
                } label: {
                    HamburgerLines()
                        .fill(.white)
                        .frame(width: 18, height: 14)
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
            // Camera preview — always present during preview, masked by iris
            if showCameraPreview {
                ZStack {
                    CameraPreview(session: cameraVM.cameraService.session,
                                  isMirrored: cameraVM.currentCamera == .front && !cameraVM.isFrontFlipped)
                        .scaleEffect(cameraVM.zoomFactor)

                    // Dark vignette overlay — ambient dim edges, no solid pillarbox
                    RadialGradient(
                        colors: [.clear, .clear, .clear, Color.black.opacity(0.35)],
                        center: .center,
                        startRadius: 30,
                        endRadius: max(100, max(previewSize.width, previewSize.height))
                    )
                    .allowsHitTesting(false)
                }
                .background(GeometryReader { geo in
                    Color.clear.onAppear { previewSize = geo.size }
                        .onChange(of: geo.size) { previewSize = $0 }
                })
                .mask(irisMask)

                if cameraVM.recordingState == .recording {
                    VStack {
                        HStack(spacing: 6) {
                            RecordingDot()
                            Text(formatTime(cameraVM.elapsedTime))
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
                                previewActionButton(icon: cameraVM.isBatterySaverActive ? "moon.fill" : "moon", label: "Saver") {
                                    cameraVM.toggleBatterySaver()
                                }
                                .opacity(cameraVM.recordingState == .recording ? 1 : 0.4)
                                .disabled(cameraVM.recordingState != .recording)
                                previewActionButton(icon: "camera.fill", label: "FadShot") {
                                    cameraVM.capturePhoto()
                                }
                                .opacity(showCameraPreview ? 1 : 0.4)
                                .disabled(!showCameraPreview)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 8)
                }
            }

            // Mascot — visible during sleep AND during iris transitions
            if !showCameraPreview || avatarOpacity > 0.001 {
                mascotView
                    .opacity(avatarOpacity)
                    .scaleEffect(avatarScale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            guard !isTransitioning, previewAreaEnabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            previewAutoOpened = false
            handlePreviewToggle()
        }
        .onChange(of: cameraVM.recordingState) { newState in
            guard previewAreaEnabled else { return }
            if newState == .recording && !showCameraPreview && !isTransitioning {
                previewAutoOpened = true
                handlePreviewToggle()
            }
        }
        // Handle EXTERNAL isPreviewActive changes (recording stop, background, etc.)
        .onChange(of: cameraVM.isPreviewActive) { active in
            guard !isInternalToggle else { return }
            guard previewAreaEnabled || previewAutoOpened else { return }
            if !active && showCameraPreview {
                // Play full iris-close + fade-in avatar sequence, same as manual sleep
                isTransitioning = true
                avatarOpacity = 0
                setAwakeState()
                withAnimation(.easeIn(duration: 0.48)) {
                    irisProgress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                    showCameraPreview = false
                    avatarScale = 1.0
                    withAnimation(.easeIn(duration: 0.3)) {
                        avatarOpacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        guard isTransitioning else { return }
                        withAnimation(.easeInOut(duration: 0.42)) {
                            setSleepState()
                        }
                        startBreathingAnimation()
                        startFloatingZAnimations()
                        isTransitioning = false
                    }
                }
            }
        }
    }

    /// Circular iris mask centered on preview area. irisProgress: 0=closed, 1=open.
    @ViewBuilder
    private var irisMask: some View {
        if previewSize.width > 0 {
            let maxR = hypot(previewSize.width, previewSize.height) / 2
            let r = max(0.1, maxR * irisProgress)
            Circle()
                .frame(width: r * 2, height: r * 2)
                .position(x: previewSize.width / 2, y: previewSize.height / 2)
        }
    }

    // MARK: - Preview Toggle (Wake / Sleep animation sequence)

    private func handlePreviewToggle() {
        isInternalToggle = true
        isTransitioning = true
        if showCameraPreview {
            // ═══ Preview → Avatar (sleep) ══════════════════════════════
            setAwakeState()
            avatarOpacity = 0
            irisProgress = 1
            withAnimation(.easeIn(duration: 0.48)) {
                irisProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                showCameraPreview = false
                // Directly stop camera — avoids onChange(isPreviewActive) loop
                if cameraVM.isPreviewActive && cameraVM.recordingState != .recording {
                    cameraVM.isPreviewActive = false
                    cameraVM.stopSession()
                }
                avatarOpacity = 0
                avatarScale = 1.0
                withAnimation(.easeIn(duration: 0.3)) {
                    avatarOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    guard isTransitioning else { return }
                    withAnimation(.easeInOut(duration: 0.42)) {
                        setSleepState()
                    }
                    startBreathingAnimation()
                    startFloatingZAnimations()
                    isTransitioning = false
                    isInternalToggle = false
                }
            }
        } else {
            // ═══ Avatar → Preview (wake) ═══════════════════════════════
            // Directly start camera — bypass togglePreview to avoid loop
            if !cameraVM.isPreviewActive {
                cameraVM.isPreviewActive = true
                cameraVM.startSession()
            }
            showCameraPreview = true
            irisProgress = 0

            stopBreathing()
            stopFloatingZ()
            withAnimation(.easeOut(duration: 0.42)) {
                setAwakeState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                guard isTransitioning else { return }
                withAnimation(.easeIn(duration: 0.28)) {
                    avatarOpacity = 0
                    avatarScale = 0.72
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42 + 0.28) {
                guard isTransitioning else { return }
                withAnimation(.easeOut(duration: 0.48)) {
                    irisProgress = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                    isTransitioning = false
                    isInternalToggle = false
                }
            }
        }
    }

    private func setAwakeState() {
        eyeOffsetY = -8
        eyeBrightness = 1
        eyeGlowOpacity = 1
        breathingOpacity = 1.0
        breathingScale = 1.0
        z1Float = 0; z2Float = 0; z3Float = 0
    }

    private func setSleepState() {
        eyeOffsetY = 2
        eyeBrightness = 0
        eyeGlowOpacity = 0
    }

    private func stopBreathing() {
        withAnimation(.easeOut(duration: 0.1)) {
            breathingOpacity = 1.0
            breathingScale = 1.0
        }
    }

    private func stopFloatingZ() {
        z1Float = 0; z2Float = 0; z3Float = 0
    }

    private var mascotView: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.04, blue: 0.08), Color(red: 0.02, green: 0.02, blue: 0.04)], startPoint: .top, endPoint: .bottom)

            starfield
            crescentMoon
                .position(x: 50, y: 50)
            sparkles
            sleepingMoon
                .overlay(alignment: .topTrailing) {
                    zzzBadge
                        .offset(x: 8, y: -2)
                        .opacity(1.0 - eyeGlowOpacity)
                }

            VStack {
                Spacer()
                Text("Hold to wake up the camera")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.bottom, 8)

                // Buttons — active when recording even if preview is off
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        let isRecording = cameraVM.recordingState == .recording
                        previewActionButton(
                            icon: cameraVM.isBatterySaverActive ? "moon.fill" : "moon",
                            label: "Saver"
                        ) {
                            cameraVM.toggleBatterySaver()
                        }
                        .opacity(isRecording ? 1 : 0.4)
                        .disabled(!isRecording)
                        previewActionButton(icon: "camera.fill", label: "FadShot") {
                            cameraVM.capturePhoto()
                        }
                        .opacity(isRecording ? 1 : 0.4)
                        .disabled(!isRecording)
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
        Circle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay(
                Circle()
                    .frame(width: 36, height: 36)
                    .offset(x: 12, y: -3)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
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
            }
        }
    }

    private var sleepingMoon: some View {
        ZStack {
            // Round body with radial gradient matching Android (#c8c8c8 → #2e2e2e)
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.784, green: 0.784, blue: 0.784),
                        Color(red: 0.180, green: 0.180, blue: 0.180)
                    ]),
                    center: UnitPoint(x: 0.375, y: 0.25),
                    startRadius: 10,
                    endRadius: 75
                ))
                .frame(width: 95, height: 95)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                .opacity(breathingOpacity)
                .scaleEffect(breathingScale)

            // Left eye + soft glow
            ZStack {
                // Neon bloom: blurred white circle behind the eye
                Circle()
                    .fill(Color.white.opacity(0.25 * eyeGlowOpacity))
                    .frame(width: 20, height: 20)
                    .blur(radius: 6 * eyeGlowOpacity)
                // Softer outer bloom
                Circle()
                    .fill(Color.white.opacity(0.12 * eyeGlowOpacity))
                    .frame(width: 28, height: 28)
                    .blur(radius: 10 * eyeGlowOpacity)
                // The eye itself
                leftEye
            }
            .offset(x: -19, y: eyeOffsetY)

            // Right eye + soft glow
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.25 * eyeGlowOpacity))
                    .frame(width: 20, height: 20)
                    .blur(radius: 6 * eyeGlowOpacity)
                Circle()
                    .fill(Color.white.opacity(0.12 * eyeGlowOpacity))
                    .frame(width: 28, height: 28)
                    .blur(radius: 10 * eyeGlowOpacity)
                rightEye
            }
            .offset(x: 19, y: eyeOffsetY)
        }
        .onAppear {
            if eyeOffsetY > -2 {
                startBreathingAnimation()
                startFloatingZAnimations()
            }
        }
    }

    // MARK: - Eye Components

    private var leftEye: some View {
        Path { path in
            path.addArc(center: CGPoint(x: 11, y: 0), radius: 11,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.closeSubpath()
        }
        .fill(eyeFillColor)
        .frame(width: 22, height: 11)
    }

    private var rightEye: some View {
        Path { path in
            path.addArc(center: CGPoint(x: 11, y: 0), radius: 11,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.closeSubpath()
        }
        .fill(eyeFillColor)
        .frame(width: 22, height: 11)
    }

    /// Interpolated: #2a2a2a (sleep) → #ffffff (awake)
    private var eyeFillColor: Color {
        Color(red: 0.165 + 0.835 * eyeBrightness,
              green: 0.165 + 0.835 * eyeBrightness,
              blue: 0.165 + 0.835 * eyeBrightness)
    }

    // zZz floating text — positioned at top-right of avatar, separate from the head
    private var zzzBadge: some View {
        HStack(alignment: .bottom, spacing: 1) {
            Text("z")
                .font(.system(size: 8, weight: .black, design: .default))
                .foregroundColor(Color(red: 0.66, green: 0.85, blue: 0.94))
                .offset(y: z1Float)
            Text("Z")
                .font(.system(size: 11, weight: .black, design: .default))
                .foregroundColor(Color(red: 0.81, green: 0.93, blue: 0.97))
                .offset(y: z2Float)
            Text("Z")
                .font(.system(size: 14, weight: .black, design: .default))
                .foregroundColor(.white)
                .offset(y: z3Float)
        }
    }

    private func startBreathingAnimation() {
        withAnimation(Animation.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            breathingOpacity = 0.55
            breathingScale = 0.94
        }
    }

    private func startFloatingZAnimations() {
        withAnimation(Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            z1Float = -4
        }
        withAnimation(Animation.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
            z2Float = -5
        }
        withAnimation(Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            z3Float = -6
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

    // MARK: - Action Bar (Torch | Start/Stop | Switch | Flip)

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
                cameraVM.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }

            if cameraVM.currentCamera == .front {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    cameraVM.toggleFlip()
                } label: {
                    Image(systemName: cameraVM.isFrontFlipped ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
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
