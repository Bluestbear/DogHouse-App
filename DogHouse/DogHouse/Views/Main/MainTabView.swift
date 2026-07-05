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

    enum AppTab: Hashable {
        case home, friends, shop, profile
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
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
