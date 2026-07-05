//
//  DogHouseApp.swift
//  DogHouse
//

import SwiftUI

@main
struct DogHouseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if !authService.isAuthInitialized {
                // Wait for Firebase Auth to resolve before showing any UI
                Color.cozyOrange.opacity(0.15)
                    .ignoresSafeArea()
                    .task {
                        // Safety fallback: if Firebase Auth never responds, unblock after 3s
                        try? await Task.sleep(for: .seconds(3))
                        authService.isAuthInitialized = true
                    }
            } else if !authService.isAuthenticated {
                WelcomeView()
            } else if authService.userProfile?.isOnboardingComplete == true {
                MainTabView()
            } else {
                OnboardingContainerView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthInitialized)
        .animation(.easeInOut, value: authService.isAuthenticated)
        .animation(.easeInOut, value: authService.userProfile?.isOnboardingComplete)
    }
}
