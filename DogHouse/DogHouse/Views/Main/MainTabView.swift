//
//  MainTabView.swift
//  DogHouse
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var notificationService = NotificationService.shared
    // One challenge service shared by Home (games) and Profile (anniversary)
    @StateObject private var challengeService = ChallengeService(userId: "mock_user", partnerId: "mock_partner")
    @State private var selectedTab: AppTab = .home
    @State private var showPermissionExplainer = false
    @State private var showWhatsNew = false

    enum AppTab: Hashable {
        case home, friends, shop, profile, input
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView(challengeService: challengeService)
                    .environmentObject(authService)
            }

            Tab("Friends", systemImage: "person.2.fill", value: AppTab.friends) {
                FriendsTabView()
                    .environmentObject(authService)
            }

            Tab("Shop", systemImage: "bag.fill", value: AppTab.shop) {
                ShopTabView()
                    .environmentObject(authService)
            }

            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileTabView(challengeService: challengeService)
                    .environmentObject(authService)
            }

            Tab("Input", systemImage: "envelope.fill", value: AppTab.input) {
                InputTabView()
                    .environmentObject(authService)
            }
        }
        .tint(Color.dogHouseBrown)
        // Notification taps route to the right tab
        .onChange(of: notificationService.pendingDestination) { _, destination in
            guard let destination else { return }
            switch destination {
            case .home: selectedTab = .home
            case .friends: selectedTab = .friends
            }
            notificationService.pendingDestination = nil
        }
        // Pre-permission explainer: shown once permission is still undecided
        .task {
            await notificationService.refreshStatus()
            if notificationService.authStatus == .notDetermined {
                showPermissionExplainer = true
            }
        }
        .sheet(isPresented: $showPermissionExplainer) {
            NotificationPermissionView(notificationService: notificationService)
        }
        // One-time "what's new" for accounts that predate this update.
        // New users get the same info in the onboarding tour instead.
        .onChange(of: authService.userProfile?.id, initial: true) { _, _ in
            guard let profile = authService.userProfile,
                  !UserDefaults.standard.bool(forKey: WhatsNew.seenKey) else { return }
            // Mark seen either way so new users never get it later
            UserDefaults.standard.set(true, forKey: WhatsNew.seenKey)
            if profile.createdAt < WhatsNew.releaseDate {
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
