//
//  MainTabView.swift
//  DogHouse
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationService = NotificationService.shared
    // One challenge service shared by Home (games) and Profile (anniversary)
    @StateObject private var challengeService = ChallengeService(userId: "mock_user", partnerId: "mock_partner")
    @State private var selectedTab: AppTab = .home
    @State private var showPermissionExplainer = false
    @State private var showWhatsNew = false

    // The live tour runs on top of these tabs. It starts once for new users
    // (tourComplete == false) after the permission explainer is out of the
    // way, and can be replayed from Profile.
    @ObservedObject private var tour = TourCoordinator.shared
    @State private var tourStartedThisSession = false

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
        .overlay {
            TourOverlayView(
                userName: authService.userProfile?.displayName ?? "there",
                partnerName: authService.partnerProfile?.displayName ?? "your partner"
            )
        }
        // Each tour step lives on a tab; follow it there.
        .onChange(of: tour.currentStep) { _, step in
            guard let step, selectedTab != step.tab else { return }
            selectedTab = step.tab
        }
        // Finished or skipped: back to Home and never auto-show again.
        .onChange(of: tour.completionCount) { _, _ in
            selectedTab = .home
            Task { await authService.markTourComplete() }
        }
        .onChange(of: showPermissionExplainer) { _, _ in maybeStartTour() }
        .onChange(of: showWhatsNew) { _, _ in maybeStartTour() }
        .onChange(of: authService.userProfile?.isTourComplete) { _, _ in maybeStartTour() }
        // Notification taps route to the right tab
        .onChange(of: notificationService.pendingDestination) { _, destination in
            guard let destination else { return }
            switch destination {
            case .home: selectedTab = .home
            case .friends: selectedTab = .friends
            case .shop: selectedTab = .shop
            }
            notificationService.pendingDestination = nil
        }
        // Pre-permission explainer: shown once permission is still undecided
        .task { await authService.recordActivity() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await authService.recordActivity() }
        }
        .task {
            await notificationService.refreshStatus()
            if notificationService.authStatus == .notDetermined {
                showPermissionExplainer = true
            }
            maybeStartTour()
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

    /// Start the tour for a user who hasn't seen it, but only once no sheet
    /// is covering the screen — a spotlight behind a sheet is invisible, and
    /// the notification explainer matters more than the tour.
    private func maybeStartTour() {
        guard !tourStartedThisSession,
              !tour.isActive,
              !showPermissionExplainer,
              !showWhatsNew,
              let profile = authService.userProfile,
              !profile.isTourComplete else { return }
        tourStartedThisSession = true
        Task {
            // Let the tab bar and Home settle so the first anchors exist.
            try? await Task.sleep(for: .seconds(0.7))
            tour.start()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
