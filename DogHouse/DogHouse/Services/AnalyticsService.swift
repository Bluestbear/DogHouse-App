//
//  AnalyticsService.swift
//  DogHouse
//
//  Product analytics: which screens people open and which parts of the loop
//  they actually use. Deliberately coarse — we log intents (a sending, a
//  release, a purchase), never individual taps.
//
//  NOTHING a user writes about their relationship is logged here. Reasons,
//  make-it-up notes, display names, partner ids and email addresses stay out
//  of every parameter; Firebase forbids personal data in them and the app has
//  no reason to send it. Parameters are counts, flags and catalog ids only.
//
//  Users can turn all of it off in Profile → Share Usage Data. Firebase
//  persists that choice itself; the UserDefaults mirror exists so the toggle
//  renders correctly and so the choice survives a reinstall of the SDK's
//  own state. Follows the SoundService/HapticService settings idiom.
//

import Foundation
import Combine
import FirebaseAnalytics

final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()

    /// Absent means on: this is an opt-out, and the privacy policy says so.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "analyticsEnabled")
            Analytics.setAnalyticsCollectionEnabled(isEnabled)
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool ?? true
    }

    /// Apply the stored choice at launch. Collection is disabled in
    /// Info.plist so that nothing is gathered before this runs; this call is
    /// what actually turns it on for users who have not opted out.
    func start() {
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    /// Every event this app sends. An enum rather than string literals, so a
    /// typo can't quietly create a second near-identical event name that then
    /// splits a funnel in the console.
    ///
    /// Names steer clear of Firebase's reserved set — notably
    /// `notification_open`, which FCM owns, hence `push_opened`.
    enum Event: String {
        // The core loop
        case sendToDoghouse    = "send_to_doghouse"
        case releasePartner    = "release_partner"
        case requestRedemption = "request_redemption"
        case sendBellyRub      = "send_belly_rub"
        case sendRoses         = "send_roses"
        case claimTreats       = "claim_treats"
        case purchaseCosmetic  = "purchase_cosmetic"
        case equipCosmetic     = "equip_cosmetic"
        case redeemWishCard    = "redeem_wish_card"

        // Onboarding funnel, in the order a new couple meets it
        case signupComplete    = "signup_complete"
        case avatarChosen      = "avatar_chosen"
        case partnerPaired     = "partner_paired"
        case tourComplete      = "tour_complete"
        case pushPermission    = "push_permission"

        // Did the nudges actually bring anyone back?
        case pushOpened        = "push_opened"

        // Moderation
        case reportContent     = "report_content"
        case blockUser         = "block_user"
    }

    // MARK: - Logging

    func log(_ event: Event, _ parameters: [String: Any] = [:]) {
        guard isEnabled else { return }
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }

    /// SwiftUI has no automatic screen tracking, so the tabs report themselves.
    func logScreen(_ name: String) {
        guard isEnabled else { return }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name
        ])
    }

    /// A coarse segment for the console's comparison filters. Never the uid,
    /// never a name — only whether this account has reached the paired state.
    func setPairedProperty(_ paired: Bool) {
        guard isEnabled else { return }
        Analytics.setUserProperty(paired ? "paired" : "solo", forName: "pairing_state")
    }
}
