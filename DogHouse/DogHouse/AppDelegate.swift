//
//  AppDelegate.swift
//  DogHouse
//
//  Firebase initialization, FCM token handling, and push notification delegates.
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // Push notification setup. The permission request itself happens in
        // the UI (explainer screen / MainTabView) — never cold at launch.
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()

        // Already-authorized users still need APNs registration every launch
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                NotificationService.shared.authStatus = settings.authorizationStatus
                if settings.authorizationStatus == .authorized {
                    NotificationService.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Server pushes set badge=1; clear it whenever the app is opened
        UNUserNotificationCenter.current().setBadgeCount(0)
        // Status may have changed in Settings while backgrounded
        Task { await NotificationService.shared.refreshStatus() }
    }

    // MARK: - APNs Token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        UserDefaults.standard.set(token, forKey: "fcmToken")
        NotificationCenter.default.post(name: .fcmTokenRefreshed, object: nil, userInfo: ["token": token])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        Task { @MainActor in
            NotificationService.shared.handleNotificationResponse(
                userInfo: userInfo,
                actionIdentifier: actionId
            )
        }
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let fcmTokenRefreshed = Notification.Name("fcmTokenRefreshed")
}
