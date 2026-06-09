import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var cameraVM = CameraViewModel()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView(cameraVM: cameraVM, selectedTab: $selectedTab)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                RecordsView()
                    .tabItem {
                        Label("Records", systemImage: "list.bullet.rectangle.fill")
                    }
                    .tag(1)

                FaditorMiniView()
                    .tabItem {
                        Label("Faditor Mini", systemImage: "film.stack")
                    }
                    .badge("Soon")
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(.red)

            if cameraVM.isBatterySaverActive && cameraVM.recordingState == .recording {
                Color.black
                    .ignoresSafeArea()
                    .overlay(batterySaverOverlay)
                    .zIndex(100)
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
    }

    private var batterySaverOverlay: some View {
        VStack {
            Spacer()
            Text("Long press to disable battery saver mode")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.0) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            cameraVM.toggleBatterySaver()
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

#Preview {
    ContentView()
}
