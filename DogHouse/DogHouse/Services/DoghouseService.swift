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

    /// My stay that just ended while the app was open (let out, make-up
    /// confirmed, or voted out), confirmed closed by the server. Home plays
    /// its own "YOU'RE FREE!" for it once, then clears this.
    @Published var justReleasedEvent: DoghouseEvent?

    /// True once history and both active-stay listeners have reported from
    /// the server. Until then "no active stay" and "never released" only mean
    /// "not loaded yet", and badges judged on them were false (QA-026).
    var hasLoadedState: Bool {
        #if DEBUG
        if AuthService.isDemo || DoghouseService.demoDoghouseHours != nil { return true }
        #endif
        return historyLoaded && myEventLoaded && partnerEventLoaded
    }
    @Published private var historyLoaded = false
    @Published private var myEventLoaded = false
    @Published private var partnerEventLoaded = false

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

    #if DEBUG
    /// Launch with `-demoDoghouseHours 30` (alongside `-demoOnboarding`) to
    /// see yourself in the doghouse that many hours in, without a Firestore
    /// event. Drives the scene's weather stages for previews and screenshots.
    static var demoDoghouseHours: Double? {
        let h = UserDefaults.standard.double(forKey: "demoDoghouseHours")
        return h > 0 ? h : nil
    }
    #endif

    init(userId: String, partnerId: String? = nil) {
        #if DEBUG
        if let hours = DoghouseService.demoDoghouseHours {
            self.userId = "demo_me"
            self.partnerId = "demo_partner"
            self.myDoghouseEvent = DoghouseEvent(
                id: "demo", senderId: "demo_partner", receiverId: "demo_me",
                reason: "Left the dishes again", suggestion: "Cook dinner",
                startedAt: Date().addingTimeInterval(-hours * 3600), endedAt: nil, isActive: true
            )
            return
        }
        #endif
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
                    if snapshot != nil { self.myEventLoaded = true }
                    if let doc = snapshot?.documents.first {
                        self.myDoghouseEvent = try? self.fs.decode(DoghouseEvent.self, from: doc)
                    } else {
                        // Immunity on release is now granted server-side by the
                        // releasePartner callable / vote resolver.
                        let ended = self.myDoghouseEvent
                        self.myDoghouseEvent = nil
                        // A release just closed an event — pull the new history.
                        if let ended {
                            Task { await self.refreshHistory() }
                            // A listener error also lands here (no snapshot),
                            // so only a real, server-confirmed close counts.
                            if snapshot != nil, error == nil {
                                Task { await self.confirmRelease(of: ended) }
                            }
                        }
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
                    if snapshot != nil { self.partnerEventLoaded = true }
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
            historyLoaded = true
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
        #if DEBUG
        // Demo mode has no account: land the send locally so the send flow
        // and its animation can be tried on the sim without touching Firebase.
        if AuthService.isDemo {
            try? await Task.sleep(for: .milliseconds(400))
            partnerDoghouseEvent = DoghouseEvent(
                id: "demo_sent", senderId: "demo_me", receiverId: "demo_partner",
                reason: reason, suggestion: suggestion,
                startedAt: Date(), endedAt: nil, isActive: true
            )
            if isPublic { FeedService.demoShare(reason: reason) }
            return
        }
        #endif
        guard let partnerId, partnerId != "skipped" else { return }
        try await CloudFunctions.shared.call("sendToDoghouse", [
            "reason": reason,
            "suggestion": suggestion as Any,
            "isPublic": isPublic
        ])
        AnalyticsService.shared.log(.sendToDoghouse, [
            "is_public": isPublic,
            "has_suggestion": suggestion?.isEmpty == false
        ])
        // Snapshot listeners will update both devices
    }

    /// Publishes `justReleasedEvent` if the stay I was just watching really
    /// ended on the server — the listener going empty isn't proof on its own.
    private func confirmRelease(of event: DoghouseEvent) async {
        do {
            let doc = try await fs.doghouseEventsCollection.document(event.id)
                .getDocument(source: .server)
            guard let closed = try? fs.decode(DoghouseEvent.self, from: doc),
                  !closed.isActive, closed.receiverId == userId else { return }
            justReleasedEvent = closed
        } catch {
            Logger.data.error("Release check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The dog marks the make-it-up suggestion as done; the sender gets a
    /// push asking to confirm. Server sets the flag on their active event.
    func requestRedemption() async throws {
        guard let event = myDoghouseEvent else { return }
        try await CloudFunctions.shared.call("requestRedemption", ["eventId": event.id])
        AnalyticsService.shared.log(.requestRedemption, ["hours_served": Int(event.duration / 3600)])
    }

    /// Release partner from the doghouse. The server marks the event inactive,
    /// grants the freed dog immunity, awards redemption treats, and closes any
    /// public feed post — all atomically with admin privileges.
    func releasePartner(releasedBy: String = "sender") async throws {
        #if DEBUG
        if AuthService.isDemo {
            partnerDoghouseEvent = nil
            return
        }
        #endif
        guard let event = partnerDoghouseEvent else { return }
        try await CloudFunctions.shared.call("releasePartner", [
            "eventId": event.id,
            "byRedemption": releasedBy == "redemption"
        ])
        AnalyticsService.shared.log(.releasePartner, [
            "released_by": releasedBy,
            "hours_served": Int(event.duration / 3600)
        ])
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
        AnalyticsService.shared.log(.sendBellyRub)
    }

    // MARK: - Roses

    /// Send roses to the partner. Costs treats, so it runs through the
    /// sendRoses callable (server deducts and writes roses/{partnerId}).
    func sendRoses() async throws {
        guard let partnerId, partnerId != "skipped" else { return }
        try await CloudFunctions.shared.call("sendRoses")
        AnalyticsService.shared.log(.sendRoses)
    }
}
