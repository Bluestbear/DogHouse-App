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
import OSLog

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

    /// Display name of the partner who just sent roses; cleared after consumption
    @Published var receivedRoses: String?

    /// When roses were last sent TO ME — drives the bouquet next to my dog
    @Published var myRosesSentAt: Date?

    /// When roses were last sent TO MY PARTNER — drives the bouquet next
    /// to their dog (visible to me, the sender, on their scene page)
    @Published var partnerRosesSentAt: Date?

    private(set) var userId: String
    private(set) var partnerId: String?
    private let fs = FirebaseService.shared
    private var myEventListener: ListenerRegistration?
    private var partnerEventListener: ListenerRegistration?
    private var bellyRubListener: ListenerRegistration?
    private var bellyRubListenStart: Date?
    private var rosesListener: ListenerRegistration?
    private var partnerRosesListener: ListenerRegistration?
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

    isolated deinit {
        myEventListener?.remove()
        partnerEventListener?.remove()
        bellyRubListener?.remove()
        rosesListener?.remove()
        partnerRosesListener?.remove()
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
            Logger.data.error("Partner resolution failed: \(error.localizedDescription, privacy: .public)")
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
                        let wasActive = self.myDoghouseEvent != nil
                        self.myDoghouseEvent = nil
                        // A release just closed an event — pull the new history.
                        if wasActive { Task { await self.refreshHistory() } }
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
                        let wasActive = self.partnerDoghouseEvent != nil
                        self.partnerDoghouseEvent = nil
                        if wasActive { Task { await self.refreshHistory() } }
                    }
                }
            }

        // History is fetched once, not listened to. Closed events only change
        // when an active event ends, which listeners 1 and 2 already observe —
        // holding two more live 50-document queries open for the whole session
        // was continuous socket traffic and read billing for data that changes
        // a couple of times a week. See refreshHistory().
        Task { await refreshHistory() }

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

        // LISTENER 6: Incoming roses — document keyed on my userId.
        // The timestamp always feeds the bouquet (shows for 5h); the
        // toast only fires for roses sent after app open.
        rosesListener = fs.db.collection("roses").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self,
                          let data = snapshot?.data(),
                          let sentAt = (data["sentAt"] as? Timestamp)?.dateValue()
                    else { return }
                    self.myRosesSentAt = sentAt
                    if let start = self.bellyRubListenStart, sentAt > start,
                       let fromName = data["fromDisplayName"] as? String {
                        self.receivedRoses = fromName
                    }
                }
            }

        // LISTENER 7: Roses I sent to my partner — so the bouquet also
        // shows next to their dog on my screen
        partnerRosesListener = fs.db.collection("roses").document(partnerId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self,
                          let data = snapshot?.data(),
                          let sentAt = (data["sentAt"] as? Timestamp)?.dateValue()
                    else { return }
                    self.partnerRosesSentAt = sentAt
                }
            }
    }

    /// Re-read closed events. Called at start-up and whenever an active event
    /// disappears (a release), which is the only way history can grow.
    func refreshHistory() async {
        guard userId != "mock_user" else { return }
        let base = fs.doghouseEventsCollection.whereField("isActive", isEqualTo: false)
        do {
            async let sent = base
                .whereField("senderId", isEqualTo: userId)
                .order(by: "startedAt", descending: true).limit(to: 50).getDocuments()
            async let received = base
                .whereField("receiverId", isEqualTo: userId)
                .order(by: "startedAt", descending: true).limit(to: 50).getDocuments()

            let (sentSnap, receivedSnap) = try await (sent, received)
            historySentEvents = sentSnap.documents.compactMap {
                try? fs.decode(DoghouseEvent.self, from: $0)
            }
            historyReceivedEvents = receivedSnap.documents.compactMap {
                try? fs.decode(DoghouseEvent.self, from: $0)
            }
            mergeHistory()
        } catch {
            Logger.data.error("History refresh failed: \(error.localizedDescription, privacy: .public)")
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

    /// When a user's current stay at home began: the moment they were last
    /// released from the doghouse, or — for someone who has never been in one —
    /// the day they created their account.
    ///
    /// The account-creation fallback is what makes the "You've been home for"
    /// counter move for a brand new user. It used to return a flat one hour,
    /// so every user who had never been doghoused saw a timer permanently
    /// reading "1h 0m 0s" and a room level frozen at 2.
    nonisolated static func homeStartDate(
        history: [DoghouseEvent],
        receiverId: String,
        accountCreatedAt: Date?
    ) -> Date? {
        let released = history
            .filter { $0.receiverId == receiverId }
            .compactMap(\.endedAt)
            .max()
        return released ?? accountCreatedAt
    }

    /// Time since I was last released from the doghouse (for my room progression)
    func timeSinceMyLastRelease(accountCreatedAt: Date?, now: Date = Date()) -> TimeInterval {
        guard let start = Self.homeStartDate(
            history: doghouseHistory,
            receiverId: userId,
            accountCreatedAt: accountCreatedAt
        ) else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    /// Time since partner was last released from the doghouse (for partner's room progression)
    func timeSincePartnerLastRelease(accountCreatedAt: Date?, now: Date = Date()) -> TimeInterval {
        guard let partnerId, let start = Self.homeStartDate(
            history: doghouseHistory,
            receiverId: partnerId,
            accountCreatedAt: accountCreatedAt
        ) else { return 0 }
        return max(0, now.timeIntervalSince(start))
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

    // MARK: - Roses

    /// Send roses to the partner. Costs treats, so it runs through the
    /// sendRoses callable (server deducts and writes roses/{partnerId}).
    func sendRoses() async throws {
        guard let partnerId, partnerId != "skipped" else { return }
        try await CloudFunctions.shared.call("sendRoses")
    }
}
