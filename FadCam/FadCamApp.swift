//
//  FadCamApp.swift
//  FadCam
//
//  Created by FADED on 07/06/2026.
//

import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "app")

@main
struct FadCamApp: App {
    @State private var showOnboarding: Bool
    @State private var showSplash = true

    init() {
        log.info("App init started")
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        _showOnboarding = State(initialValue: !completed)
        log.info("App init done — onboarding: \(!completed)")
    }

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashView {
                    log.info("Splash finished, transitioning")
                    showSplash = false
                }
            } else if showOnboarding {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    UserDefaults.standard.set(false, forKey: "resumeOnboarding")
                    showOnboarding = false
                    log.info("Onboarding completed")
                }
                .preferredColorScheme(.dark)
            } else {
                ContentView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}

struct SplashView: View {
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let flag = UIImage(named: "Flag") {
                Image(uiImage: flag)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 280)
            }
        }
        .onAppear {
            log.info("SplashView appeared")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    onFinish()
                }
            }
        }
    }
}
