//
//  NotificationService.swift
//  DogHouse
//
//  Notification permission state, action categories, and tap routing.
//  The AppDelegate feeds taps/actions in; views observe pendingDestination
//  and pendingAction to navigate or act.
//

import SwiftUI
import Combine
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    /// Current system permission status; drives explainer + denied banner
    @Published var authStatus: UNAuthorizationStatus = .notDetermined

    /// Where a tapped notification wants the app to go (consumed by MainTabView)
    @Published var pendingDestination: Destination?

    /// An action button the user tapped on a push (consumed by HomeView)
    @Published var pendingAction: PushAction?

    enum Destination: Equatable {
        case home      // doghouse status, redemption, games
        case friends   // feed, votes, friend requests
        case shop      // "you can now afford…" nudges
    }

    enum PushAction: Equatable {
        case releasePartner  // "Let them out 🏠" on a redemption push
        case bellyRubBack    // "Belly rub back 🐾" on a belly rub push
    }

    private init() {}

    // MARK: - Permission

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    /// Ask the system for permission (call after showing the explainer)
    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshStatus()
        AnalyticsService.shared.log(.pushPermission, ["granted": granted])
        if granted {
            Self.registerForRemoteNotifications()
        }
    }

    /// Register with APNs — only meaningful on a real device
    static func registerForRemoteNotifications() {
        #if !targetEnvironment(simulator)
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif
    }

    /// Deep-link to this app's notification settings
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Action Categories

    static func registerCategories() {
        let bellyRub = UNNotificationCategory(
            identifier: "BELLY_RUB",
            actions: [
                UNNotificationAction(identifier: "RUB_BACK", title: "Belly rub back 🐾", options: [.foreground])
            ],
            intentIdentifiers: []
        )
        let redemption = UNNotificationCategory(
            identifier: "REDEMPTION",
            actions: [
                UNNotificationAction(identifier: "RELEASE", title: "Let them out 🏠", options: [.foreground])
            ],
            intentIdentifiers: []
        )
        // The belly-rub reminder nudge: same one-tap send, different wording.
        let bellyRubNudge = UNNotificationCategory(
            identifier: "BELLY_RUB_NUDGE",
            actions: [
                UNNotificationAction(identifier: "RUB_BACK", title: "Send a belly rub 🐾", options: [.foreground])
            ],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([bellyRub, redemption, bellyRubNudge])
    }

    // MARK: - Routing

    /// Called by the AppDelegate when a notification is tapped or an action chosen
    func handleNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        // `type` is set on every push the server sends, so this is how the
        // engagement nudges get measured: which kinds actually get opened.
        AnalyticsService.shared.log(.pushOpened, [
            "push_type": (userInfo["type"] as? String) ?? "unknown",
            "action": actionIdentifier == UNNotificationDefaultActionIdentifier ? "tap" : actionIdentifier
        ])
        switch actionIdentifier {
        case "RELEASE":
            pendingAction = .releasePartner
            pendingDestination = .home
            return
        case "RUB_BACK":
            pendingAction = .bellyRubBack
            pendingDestination = .home
            return
        default:
            break // plain tap — route by payload type
        }

        switch userInfo["type"] as? String {
        case "feed", "vote", "friends":
            pendingDestination = .friends
        case "shop":
            pendingDestination = .shop
        default:
            // doghouse, redemption, belly_rub, challenge, treats, streak, level → Home
            pendingDestination = .home
        }
    }
}
