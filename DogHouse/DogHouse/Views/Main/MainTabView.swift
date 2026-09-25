//
//  MainTabView.swift
//  DogHouse
//

import SwiftUI
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationService = NotificationService.shared
    // One challenge service shared by Home (games) and Profile (anniversary)
    @StateObject private var challengeService = ChallengeService(userId: "mock_user", partnerId: "mock_partner")
    // Home judges badges and toasts unlocks; Play shows the shelf.
    @StateObject private var achievements = AchievementService()
    @State private var selectedTab: AppTab = Self.initialTab
    @State private var showPermissionExplainer = false
    @State private var showWhatsNew = false
    /// Accounts that predate the Terms of Use accept them once, before
    /// anything else (a spotlight behind a sheet is invisible anyway).
    private var showTermsGate: Bool {
        guard let profile = authService.userProfile else { return false }
        return !profile.hasAcceptedCurrentTerms
    }

    /// The sheets that can want the screen on launch.
    ///
    /// They are driven through ONE `.sheet(item:)` rather than one modifier
    /// each: SwiftUI silently drops all but one sheet attached to the same
    /// view, and an existing account with notifications still undecided
    /// wants two at once. The one that must never be dropped is the terms
    /// gate — a user who slips past it can post content they never agreed
    /// to the rules for. Priority order is the presentation order: accepting
    /// the terms makes this recompute and the next sheet takes its place.
    private enum StartupSheet: Identifiable {
        case terms, notifications, whatsNew
        var id: Self { self }
    }

    private var startupSheet: StartupSheet? {
        if showTermsGate { return .terms }
        if showPermissionExplainer { return .notifications }
        if showWhatsNew { return .whatsNew }
        return nil
    }

    // The live tour runs on top of these tabs. It starts once for new users
    // (tourComplete == false) after the permission explainer is out of the
    // way, and can be replayed from Profile.
    @ObservedObject private var tour = TourCoordinator.shared
    @State private var tourStartedThisSession = false

    enum AppTab: Hashable {
        case home, play, friends, shop, profile
    }

    private static var initialTab: AppTab {
        #if DEBUG
        if AuthService.isDemoShop { return .shop }
        if AuthService.isDemoPlay { return .play }
        if AuthService.isDemoFriends { return .friends }
        #endif
        return .home
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView(achievements: achievements, challengeService: challengeService)
                    .environmentObject(authService)
            }

            Tab("Play", image: "TabBone", value: AppTab.play) {
                PlayTabView(challengeService: challengeService, achievements: achievements)
                    .environmentObject(authService)
            }
            .badge(challengeService.myTurn.count)

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
        // SwiftUI reports no screens on its own, so each tab names itself.
        .onChange(of: selectedTab, initial: true) { _, tab in
            AnalyticsService.shared.logScreen(String(describing: tab))
        }
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
        // The tour can only start once nothing is covering the screen.
        .onChange(of: startupSheet) { _, _ in maybeStartTour() }
        .onChange(of: authService.userProfile?.isTourComplete) { _, _ in maybeStartTour() }
        // Notification taps route to the right tab
        .onChange(of: notificationService.pendingDestination) { _, destination in
            guard let destination else { return }
            switch destination {
            case .home: selectedTab = .home
            case .play: selectedTab = .play
            case .friends: selectedTab = .friends
            case .shop: selectedTab = .shop
            }
            notificationService.pendingDestination = nil
        }
        // Pre-permission explainer: shown once permission is still undecided
        .task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
            await authService.recordActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await authService.recordActivity() }
            // AppDelegate's applicationDidBecomeActive never fires under the
            // SwiftUI scene lifecycle, so foreground work lives here.
            // Server pushes set badge=1; clear it whenever the app is opened.
            UNUserNotificationCenter.current().setBadgeCount(0)
            // Permission may have changed in Settings while backgrounded.
            Task { await notificationService.refreshStatus() }
        }
        .task {
            #if DEBUG
            if AuthService.isDemoTab { return }
            #endif
            await notificationService.refreshStatus()
            if notificationService.authStatus == .notDetermined {
                showPermissionExplainer = true
            }
            maybeStartTour()
        }
        .sheet(item: .init(
            get: { startupSheet },
            set: { newValue in
                // Only a dismissal comes back through here. Clear whichever
                // sheet was showing; the terms gate clears itself by writing
                // termsAcceptedVersion, so an attempted dismissal of it just
                // re-presents — which is the point of a gate.
                guard newValue == nil else { return }
                switch startupSheet {
                case .notifications: showPermissionExplainer = false
                case .whatsNew: showWhatsNew = false
                case .terms, .none: break
                }
            }
        )) { sheet in
            switch sheet {
            case .terms:
                TermsGateView()
                    .environmentObject(authService)
            case .notifications:
                NotificationPermissionView(notificationService: notificationService)
            case .whatsNew:
                WhatsNewView()
            }
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
    }

    /// Start the tour for a user who hasn't seen it, but only once no sheet
    /// is covering the screen — a spotlight behind a sheet is invisible, and
    /// the notification explainer matters more than the tour.
    private func maybeStartTour() {
        guard !tourStartedThisSession,
              !tour.isActive,
              startupSheet == nil,
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
