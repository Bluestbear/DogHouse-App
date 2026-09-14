//
//  DogHouseApp.swift
//  DogHouse
//

import SwiftUI
import GoogleSignIn

@main
struct DogHouseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                // Google Sign-In hands control back through a custom URL. This
                // belongs on the scene, not on AppDelegate: a SwiftUI app runs
                // under the UIScene lifecycle, where the app delegate's
                // application(_:open:options:) is never called.
                // Universal links (…/pair/CODE) arrive here too.
                .onOpenURL { url in
                    if authService.handle(url: url) { return }
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
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
                        // Safety fallback: if Firebase Auth never calls back,
                        // unblock after 3s. `isAuthenticated` was seeded from
                        // the keychain-restored user in AuthService.init, so
                        // this can never bounce a signed-in user to Welcome.
                        try? await Task.sleep(for: .seconds(3))
                        authService.isAuthInitialized = true
                    }
            } else if !authService.isAuthenticated {
                WelcomeView()
            } else if authService.userProfile == nil {
                // Signed in, profile still loading (first launch after a
                // reinstall, slow network, or a profile being recreated).
                // Previously this fell through to the pairing screen with a
                // blank "------" code, which read as a broken account.
                ProfileLoadingView()
            } else if authService.userProfile?.isOnboardingComplete == true {
                MainTabView()
            } else {
                OnboardingContainerView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthInitialized)
        .animation(.easeInOut, value: authService.isAuthenticated)
        .animation(.easeInOut, value: authService.userProfile == nil)
        .animation(.easeInOut, value: authService.userProfile?.isOnboardingComplete)
    }
}
