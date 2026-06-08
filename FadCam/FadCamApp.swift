//
//  FadCamApp.swift
//  FadCam
//
//  Created by FADED on 07/06/2026.
//

import SwiftUI

@main
struct FadCamApp: App {
    @State private var showOnboarding: Bool

    init() {
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        _showOnboarding = State(initialValue: !completed)
    }

    var body: some Scene {
        WindowGroup {
            if showOnboarding {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    showOnboarding = false
                }
                .preferredColorScheme(.dark)
            } else {
                ContentView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
