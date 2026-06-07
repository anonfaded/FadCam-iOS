//
//  FadCamApp.swift
//  FadCam
//
//  Created by FADED on 07/06/2026.
//

import SwiftUI

@main
struct FadCamApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .preferredColorScheme(.dark)
            } else {
                OnboardingView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
