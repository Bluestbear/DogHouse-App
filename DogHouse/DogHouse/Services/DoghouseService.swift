//
//  DoghouseService.swift
//  DogHouse
//
//  Firestore-backed doghouse event service with real-time listeners:
//
//  1. myDoghouseEvent — Am I in the doghouse? (receiverId == me, isActive == true)
//     This drives MY avatar display: living room vs doghouse scene.
//
//  2. partnerDoghouseEvent — Did I send my partner to the doghouse?
//     (senderId == me, receiverId == partner, isActive == true)
//     This shows the partner status card and the "Let them out" button.
//
//  3 & 4. History — two queries (sent + received) merged client-side.
//     Avoids a coupleKey query which Firestore rules cannot pre-validate.
//
//  Both active listeners can fire simultaneously (mutual doghousing).
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class DoghouseService: ObservableObject {
    /// Active event where I am the RECEIVER (I'm in the doghouse)
    @Published var myDoghouseEvent: DoghouseEvent?

    /// Active event where I am the SENDER (I sent my partner to the doghouse)
    @Published var partnerDoghouseEvent: DoghouseEvent?

    /// History of all completed events involving this couple
    @Published var doghouseHistory: [DoghouseEvent] = []

    /// Display name of the partner who just sent a belly rub; cleared after consumption
    @Published var receivedBellyRub: String?

    private(set) var userId: String
    private(set) var partnerId: String?
    private let fs = FirebaseService.shared
    private var myEventListener: ListenerRegistration?
    private var partnerEventListener: ListenerRegistration?
    private var historySentListener: ListenerRegistration?
    private var historyReceivedListener: ListenerRegistration?
    private var bellyRubListener: ListenerRegistration?
    private var bellyRubListenStart: Date?
    private var historySentEvents: [DoghouseEvent] = []
    private var historyReceivedEvents: [DoghouseEvent] = []

    init(userId: String, partnerId: String? = nil) {
        // Resolve real user ID from Firebase Auth when views pass "mock_user"
        if userId == "mock_user", let realUid = Auth.auth().currentUser?.uid {
            self.userId = realUid
        } else {
            self.userId = userId
        }

        if partnerId == "mock_partner" {
            // Resolve partner from Firestore
            self.partnerId = nil
            Task { await resolvePartnerAndListen() }
        } else {
            self.partnerId = partnerId
            if let partnerId, partnerId != "skipped" {
                startListening(partnerId: partnerId)
            }
        }
    }

    deinit {
        myEventListener?.remove()
        partnerEventListener?.remove()
        historySentListener?.remove()
        historyReceivedListener?.remove()
        bellyRubListener?.remove()
    }

    // MARK: - Partner Resolution

    private func resolvePartnerAndListen() async {
        guard userId != "mock_user" else { return } // SwiftUI Preview guard
        do {
            let doc = try await fs.usersCollection.document(userId).getDocument()
            let pid = doc.data()?["partnerId"] as? String
            self.partnerId = pid
            if let pid, pid != "skipped" {
                self.startListening(partnerId: pid)
            }
        } catch {
            print("Failed to resolve partner: \(error)")
        }
    }

    // MARK: - Real-time Listeners

    private func startListening(partnerId: String) {
        // LISTENER 1: Am I in the doghouse?
        // Queries for active events where I am the RECEIVER.
        myEventListener = fs.doghouseEventsCollection
            .whereField("receiverId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let doc = snapshot?.documents.first {
                        self.myDoghouseEvent = try? self.fs.decode(DoghouseEvent.self, from: doc)
                    } else {
                        // Immunity on release is now granted server-side by the
                        // releasePartner callable / vote resolver.
                        self.myDoghouseEvent = nil
                    }
                }
            }

        // LISTENER 2: Did I send my partner to the doghouse?
        // Queries for active events where I am the SENDER and partner is the RECEIVER.
        partnerEventListener = fs.doghouseEventsCollection
            .whereField("senderId", isEqualTo: userId)
            .whereField("receiverId", isEqualTo: partnerId)
            .whereField("isActive", isEqualTo: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let doc = snapshot?.documents.first {
                        self.partnerDoghouseEvent = try? self.fs.decode(DoghouseEvent.self, from: doc)
                    } else {
                        self.partnerDoghouseEvent = nil
                    }
                }
            }

        // LISTENERS 3 & 4: History — split into sent/received so Firestore rules
        // can verify access via senderId/receiverId rather than coupleKey.
        historySentListener = fs.doghouseEventsCollection
            .whereField("senderId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: false)
            .order(by: "startedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.historySentEvents = docs.compactMap {
                        try? self.fs.decode(DoghouseEvent.self, from: $0)
                    }
                    self.mergeHistory()
                }
            }

        historyReceivedListener = fs.doghouseEventsCollection
            .whereField("receiverId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: false)
            .order(by: "startedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.historyReceivedEvents = docs.compactMap {
                        try? self.fs.decode(DoghouseEvent.self, from: $0)
                    }
                    self.mergeHistory()
                }
            }

        // LISTENER 5: Incoming belly rubs — document keyed on my userId
        bellyRubListenStart = Date()
        bellyRubListener = fs.bellyRubsCollection.document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self,
                          let data = snapshot?.data(),
                          let sentAt = (data["sentAt"] as? Timestamp)?.dateValue(),
                          let start = self.bellyRubListenStart,
                          sentAt > start,
                          let fromName = data["fromDisplayName"] as? String
                    else { return }
                    self.receivedBellyRub = fromName
                }
            }
    }

    private func mergeHistory() {
        doghouseHistory = (historySentEvents + historyReceivedEvents)
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(50)
            .map { $0 }
    }

    // MARK: - Core Actions

    /// Send partner to the doghouse via the server (grace/immunity are
    /// validated and deducted server-side; public sends create the feed post).
    func sendToDoghouse(reason: String, suggestion: String?, isPublic: Bool = false) async throws {
        guard let partnerId, partnerId != "skipped" else { return }
        try await CloudFunctions.shared.call("sendToDoghouse", [
            "reason": reason,
            "suggestion": suggestion as Any,
            "isPublic": isPublic
        ])
        // Snapshot listeners will update both devices
    }

    /// The dog marks the make-it-up suggestion as done; the sender gets a
    /// push asking to confirm. Server sets the flag on their active event.
    func requestRedemption() async throws {
        guard let event = myDoghouseEvent else { return }
        try await CloudFunctions.shared.call("requestRedemption", ["eventId": event.id])
    }

    /// Release partner from the doghouse. The server marks the event inactive,
    /// grants the freed dog immunity, awards redemption treats, and closes any
    /// public feed post — all atomically with admin privileges.
    func releasePartner(releasedBy: String = "sender") async throws {
        guard let event = partnerDoghouseEvent else { return }
        try await CloudFunctions.shared.call("releasePartner", [
            "eventId": event.id,
            "byRedemption": releasedBy == "redemption"
        ])
    }

    // MARK: - Grace Charge Helpers

    /// Compute effective grace charges accounting for time-based recharge (1 per 24h)
    static func computeEffectiveCharges(stored: Int, lastRecharge: Date?) -> Int {
        guard let lastRecharge else { return stored }
        let hoursSinceRecharge = Date().timeIntervalSince(lastRecharge) / 3600
        let rechargedCharges = Int(hoursSinceRecharge / 24)
        return min(stored + rechargedCharges, UserProfile.maxGraceCharges)
    }

    // MARK: - Computed Helpers

    /// Time since I was last released from the doghouse (for my room progression)
    func timeSinceMyLastRelease() -> TimeInterval {
        // Find the most recent event where I was the receiver
        let myHistory = doghouseHistory.filter { $0.receiverId == userId }
        if let lastEvent = myHistory.first, let endedAt = lastEvent.endedAt {
            return Date().timeIntervalSince(endedAt)
        }
        return 3600 // Default when no history exists
    }

    /// Time since partner was last released from the doghouse (for partner's room progression)
    func timeSincePartnerLastRelease() -> TimeInterval {
        guard let partnerId else { return 3600 }
        let partnerHistory = doghouseHistory.filter { $0.receiverId == partnerId }
        if let lastEvent = partnerHistory.first, let endedAt = lastEvent.endedAt {
            return Date().timeIntervalSince(endedAt)
        }
        return 3600
    }

    /// Whether I am currently in the doghouse
    var iAmInDoghouse: Bool {
        myDoghouseEvent != nil
    }

    /// Whether I have sent my partner to the doghouse
    var partnerIsInDoghouse: Bool {
        partnerDoghouseEvent != nil
    }

    // MARK: - Belly Rub

    /// Send a belly rub to the partner (writes to bellyRubs/{partnerId})
    func sendBellyRub(fromDisplayName: String) async throws {
        guard let partnerId, partnerId != "skipped" else { return }
        try await fs.bellyRubsCollection.document(partnerId).setData([
            "fromUserId": userId,
            "fromDisplayName": fromDisplayName,
            "sentAt": Timestamp(date: Date())
        ])
    }
}
