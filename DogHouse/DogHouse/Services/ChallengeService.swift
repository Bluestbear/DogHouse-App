//
//  ChallengeService.swift
//  DogHouse
//
//  Couple challenges (quiz / photo dash / anniversary race), the
//  anniversary date, and "Whatever I Want" card redemption.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class ChallengeService: ObservableObject {
    @Published var challenges: [Challenge] = []
    @Published var anniversary: Date?
    @Published var receivedWishes: [Wish] = []

    private(set) var userId: String
    private(set) var partnerId: String?
    private let fs = FirebaseService.shared
    private var challengesListener: ListenerRegistration?
    private var metaListener: ListenerRegistration?
    private var wishesListener: ListenerRegistration?

    private var coupleKey: String? {
        guard let partnerId, partnerId != "skipped" else { return nil }
        return fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    init(userId: String, partnerId: String?) {
        if userId == "mock_user", let realUid = Auth.auth().currentUser?.uid {
            self.userId = realUid
        } else {
            self.userId = userId
        }
        self.partnerId = partnerId

        guard self.userId != "mock_user" else {
            loadMockData()
            return
        }

        if partnerId == nil || partnerId == "mock_partner" {
            Task { await resolvePartnerAndListen() }
        } else {
            startListening()
        }
    }

    deinit {
        challengesListener?.remove()
        metaListener?.remove()
        wishesListener?.remove()
    }

    private func resolvePartnerAndListen() async {
        guard let doc = try? await fs.usersCollection.document(userId).getDocument() else { return }
        let pid = doc.data()?["partnerId"] as? String
        await MainActor.run {
            self.partnerId = pid
            self.startListening()
        }
    }

    private func startListening() {
        guard let coupleKey else { return }

        // Query by participants (array-contains me) — this is the shape the
        // security rules can prove; querying by coupleKey alone gets the
        // whole listener denied. coupleKey is then filtered client-side.
        let key = coupleKey
        challengesListener = fs.challengesCollection
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.challenges = docs
                        .compactMap { try? self.fs.decode(Challenge.self, from: $0) }
                        .filter { $0.coupleKey == key }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }

        metaListener = fs.coupleMetaCollection.document(coupleKey)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.anniversary = (snapshot?.data()?["anniversary"] as? Timestamp)?.dateValue()
                }
            }

        wishesListener = fs.wishesCollection
            .whereField("toUserId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.receivedWishes = docs
                        .compactMap { try? self.fs.decode(Wish.self, from: $0) }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }
    }

    /// Couple context, or a helpful error instead of a silent no-op
    private func requireCouple() throws -> (coupleKey: String, partnerId: String) {
        guard let coupleKey, let partnerId, partnerId != "skipped" else {
            throw NSError(domain: "ChallengeService", code: -30,
                          userInfo: [NSLocalizedDescriptionKey: "You need a partner for this — pair up in Profile first!"])
        }
        return (coupleKey, partnerId)
    }

    // MARK: - Anniversary

    func setAnniversary(_ date: Date) async throws {
        let (coupleKey, partnerId) = try requireCouple()
        try await fs.coupleMetaCollection.document(coupleKey).setData([
            "anniversary": Timestamp(date: date),
            "userIds": [userId, partnerId]
        ], merge: true)
    }

    /// Whether today is the anniversary (month + day match)
    var isAnniversaryToday: Bool {
        guard let anniversary else { return false }
        let cal = Calendar.current
        let a = cal.dateComponents([.month, .day], from: anniversary)
        let t = cal.dateComponents([.month, .day], from: Date())
        return a.month == t.month && a.day == t.day
    }

    /// This year's anniversary race, if anyone has won it
    var anniversaryRaceResult: Challenge? {
        guard let coupleKey else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        return challenges.first { $0.id == "anniv_\(coupleKey)_\(year)" }
    }

    /// First tap wins: creates this year's race doc with a deterministic id.
    /// Rules forbid updating a completed challenge, so the second partner's
    /// attempt fails — the race can only be won once.
    func wishHappyAnniversary() async throws {
        let (coupleKey, partnerId) = try requireCouple()
        let year = Calendar.current.component(.year, from: Date())
        let docId = "anniv_\(coupleKey)_\(year)"
        let doc = try await fs.challengesCollection.document(docId).getDocument()
        guard !doc.exists else { return } // partner beat you to it

        try await fs.challengesCollection.document(docId).setData([
            "coupleKey": coupleKey,
            "type": "anniversary",
            "title": "Anniversary Race \(year)",
            "prompt": "First to wish a happy anniversary wins!",
            "createdBy": userId,
            "participants": [userId, partnerId],
            "status": "completed",
            "createdAt": Timestamp(date: Date()),
            "winnerId": userId,
            "completedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Quiz

    func startQuiz() async throws {
        let (coupleKey, partnerId) = try requireCouple()
        let q = QuizQuestion.random()
        try await fs.challengesCollection.document().setData([
            "coupleKey": coupleKey,
            "type": "quiz",
            "title": "Couple Quiz",
            "prompt": q.prompt,
            "options": [q.optionA, q.optionB],
            "createdBy": userId,
            "participants": [userId, partnerId],
            "status": "active",
            "answers": [:],
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// Submit my own preference and my guess about my partner's.
    /// The Cloud Function resolves the winner once both have answered.
    func answerQuiz(_ challenge: Challenge, own: String, guess: String) async throws {
        try await fs.challengesCollection.document(challenge.id).updateData([
            "answers.\(userId)": ["own": own, "guess": guess]
        ])
    }

    // MARK: - Photo Dash

    func startPhotoDash() async throws {
        let (coupleKey, partnerId) = try requireCouple()
        try await fs.challengesCollection.document().setData([
            "coupleKey": coupleKey,
            "type": "photo",
            "title": "Photo Dash",
            "prompt": PhotoDashPrompt.random(),
            "createdBy": userId,
            "participants": [userId, partnerId],
            "status": "active",
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// First photo in wins — claimed with a transaction so a simultaneous
    /// upload from both phones can't produce two winners.
    func submitPhoto(_ challenge: Challenge, image: UIImage) async throws {
        guard let data = compress(image) else {
            throw NSError(domain: "ChallengeService", code: -20,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't process that photo"])
        }
        let ref = fs.challengesCollection.document(challenge.id)
        let uid = userId
        _ = try await fs.db.runTransaction { transaction, errorPointer in
            let snap: DocumentSnapshot
            do { snap = try transaction.getDocument(ref) } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard snap.data()?["status"] as? String == "active" else {
                errorPointer?.pointee = NSError(domain: "ChallengeService", code: -21,
                    userInfo: [NSLocalizedDescriptionKey: "Too late — they beat you to it!"])
                return nil
            }
            transaction.updateData([
                "status": "completed",
                "winnerId": uid,
                "photoData": data.base64EncodedString(),
                "completedAt": Timestamp(date: Date())
            ], forDocument: ref)
            return nil
        }
    }

    /// Compress to fit comfortably in a Firestore document (target < 250KB)
    private func compress(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 640
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.5
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > 250_000, quality > 0.1 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }

    // MARK: - Whatever I Want Cards

    /// Redeem one card. The server validates the balance, decrements
    /// `wishCards` (a protected field), and creates the wish.
    func redeemWishCard(text: String) async throws {
        try await CloudFunctions.shared.call("redeemWishCard", ["text": text])
    }

    func markWishFulfilled(_ wish: Wish) async throws {
        try await fs.wishesCollection.document(wish.id).updateData(["fulfilled": true])
    }

    // MARK: - Mock Data (Preview only)

    private func loadMockData() {
        anniversary = Calendar.current.date(byAdding: .day, value: 12, to: Date())
        challenges = [
            Challenge(id: "c1", coupleKey: "a_b", type: "quiz", title: "Couple Quiz",
                      prompt: "What would your partner prefer for a vacation?",
                      createdBy: "a", participants: ["a", "b"], status: "active",
                      createdAt: Date(), options: ["Italy 🇮🇹", "Sweden 🇸🇪"], answers: [:]),
        ]
    }
}
