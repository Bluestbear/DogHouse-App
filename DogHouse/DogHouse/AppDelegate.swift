//
//  AppDelegate.swift
//  DogHouse
//
//  Firebase initialization, FCM token handling, and push notification delegates.
//

import UIKit
import FirebaseCore
import FirebaseCrashlytics
import FirebaseMessaging
#if DEBUG
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
#endif
import UserNotifications
import OSLog

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        #if DEBUG
        // `-useEmulator`: point Auth, Firestore and Functions at the local
        // Firebase emulator suite (`firebase emulators:start` in DogHouse/)
        // so multi-account test runs on simulators never touch production.
        // Must run before any service touches Firestore, which is why it
        // lives here and not in a lazily created singleton.
        // The choice is persisted so that launching from the icon or from a
        // notification banner (no launch arguments) stays on the emulator;
        // `-useProduction` clears it again.
        let emulatorKey = "dh.useEmulator"
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-useProduction") {
            UserDefaults.standard.removeObject(forKey: emulatorKey)
        } else if args.contains("-useEmulator") {
            UserDefaults.standard.set(true, forKey: emulatorKey)
        }
        if UserDefaults.standard.bool(forKey: emulatorKey) {
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "127.0.0.1:8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
            Functions.functions(region: "europe-west1").useEmulator(withHost: "127.0.0.1", port: 5001)
            Logger.push.info("Firebase emulator mode: auth 9099, firestore 8080, functions 5001")
        }
        #endif

        // Crash reporting. Collection is opt-out at the Firebase console
        // level; no user content is attached to reports, only the uid set in
        // AuthService so a crash can be tied back to a support request.
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        // Product analytics. Opt-out, mirrored from Profile → Share Usage Data;
        // applied here so a user who turned it off never logs a launch event.
        AnalyticsService.shared.start()

        // In-app purchases. Configured at launch; the account is attached
        // later, when auth resolves (AuthService.listenToAuthState).
        Task { @MainActor in PurchaseService.shared.configure() }

        // Push notification setup. The permission request itself happens in
        // the UI (explainer screen / MainTabView) — never cold at launch.
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()

        // Already-authorized users still need APNs registration every launch
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // Read the value out here: UNNotificationSettings is not Sendable,
            // so capturing it in the Task would cross isolation. The status
            // enum itself is.
            let status = settings.authorizationStatus
            Task { @MainActor in
                NotificationService.shared.authStatus = status
                if status == .authorized {
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
        Logger.push.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
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
