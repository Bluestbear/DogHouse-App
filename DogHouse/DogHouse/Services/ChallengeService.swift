//
//  ChallengeService.swift
//  DogHouse
//
//  Couple challenges (quiz / photo dash / anniversary race), Play-tab
//  games and their scorecard, task renegotiation, the anniversary date,
//  and "Whatever I Want" card redemption.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFunctions
// @preconcurrency: the Firestore ObjC transaction API predates Sendable
// annotation. The closure runs on Firestore's own queue and touches no
// actor-isolated state, so the suppressed warning is not a real race.
@preconcurrency import FirebaseFirestore

class ChallengeService: ObservableObject {
    @Published var challenges: [Challenge] = []
    @Published var anniversary: Date?
    @Published var receivedWishes: [Wish] = []
    @Published var gameStats = GameStats()
    @Published var taskRenegotiation: TaskRenegotiation?

    private(set) var userId: String
    private(set) var partnerId: String?
    private let fs = FirebaseService.shared
    private var challengesListener: ListenerRegistration?
    private var metaListener: ListenerRegistration?
    private var wishesListener: ListenerRegistration?
    private var gameStatsListener: ListenerRegistration?
    private var renegotiationListener: ListenerRegistration?

    private var coupleKey: String? {
        guard let partnerId, partnerId != "skipped" else { return nil }
        return fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    init(userId: String, partnerId: String?) {
        // Demo mode stays on the mock data even when the simulator still has a
        // signed-in Firebase account cached (it used to mix that account in).
        if userId == "mock_user", !Self.isDemoRun, let realUid = Auth.auth().currentUser?.uid {
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

    private static var isDemoRun: Bool {
        #if DEBUG
        AuthService.isDemo
        #else
        false
        #endif
    }

    isolated deinit {
        challengesListener?.remove()
        metaListener?.remove()
        wishesListener?.remove()
        gameStatsListener?.remove()
        renegotiationListener?.remove()
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

        startGameListeners(coupleKey: coupleKey)
    }

    private func startGameListeners(coupleKey: String) {
        // Both docs are server-written and path-ruled, so the listeners can
        // attach before either exists.
        gameStatsListener = fs.gameStatsCollection.document(coupleKey)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    self?.gameStats = GameStats(snapshot?.data() ?? [:])
                }
            }

        renegotiationListener = fs.taskRenegotiationCollection.document(coupleKey)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard let data = snapshot?.data(),
                          let by = data["requestedBy"] as? String else {
                        self.taskRenegotiation = nil
                        return
                    }
                    self.taskRenegotiation = TaskRenegotiation(
                        requestedBy: by,
                        requestedAt: (data["requestedAt"] as? Timestamp)?.dateValue(),
                        accepted: data["status"] as? String == "accepted"
                    )
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
    /// The existence check and the write run in one transaction, so two
    /// taps a few milliseconds apart can't both read "no doc yet" and race
    /// each other to the create; the loser simply sees the winner's doc.
    /// (Rules also forbid updating a completed challenge, as a backstop.)
    func wishHappyAnniversary() async throws {
        let (coupleKey, partnerId) = try requireCouple()
        let year = Calendar.current.component(.year, from: Date())
        let ref = fs.challengesCollection.document("anniv_\(coupleKey)_\(year)")
        let userId = self.userId
        _ = try await fs.db.runTransaction { transaction, errorPointer in
            do {
                let doc = try transaction.getDocument(ref)
                guard !doc.exists else { return nil } // partner beat you to it
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            transaction.setData([
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
            ], forDocument: ref)
            return nil
        }
    }

    // MARK: - Quiz

    // Legacy quizzes can still be answered. New ones can't be created from the
    // client any more (rules deny it): games go through createGame, which
    // enforces the free daily limit.

    /// Submit my own answer. The Cloud Function resolves the quiz
    /// (match or no match) once both partners have answered.
    func answerQuiz(_ challenge: Challenge, own: String) async throws {
        try await fs.challengesCollection.document(challenge.id).updateData([
            "answers.\(userId)": ["own": own]
        ])
    }

    /// The active app-triggered photo dash, if any.
    var activePhotoDash: Challenge? {
        challenges.first { $0.type == "photo" && $0.isActive }
    }

    // MARK: - Games (Play tab)

    /// Send a game. The server stores `answerIndex` where the partner's
    /// phone can't read it until they've guessed.
    func createGame(_ kind: GameKind, prompt: String, options: [String], answerIndex: Int) async throws {
        #if DEBUG
        if AuthService.isDemo {
            // Same rule as the server: one free game a day unless the couple
            // is premium. Counted from launch so the first send always works.
            if !PurchaseService.shared.demoCouplePremium, demoGamesToday >= 1 {
                throw DailyGameLimitError()
            }
            demoGamesToday += 1
            challenges.insert(Challenge(
                id: UUID().uuidString, coupleKey: "demo", type: "game", title: kind.title,
                prompt: prompt, createdBy: userId, participants: [userId, "mock_partner"],
                status: "active", createdAt: Date(), options: options, kind: kind.rawValue), at: 0)
            return
        }
        #endif
        _ = try requireCouple()
        do {
            try await CloudFunctions.shared.call("createGame", [
                "kind": kind.rawValue,
                "prompt": prompt,
                "options": options,
                "answerIndex": answerIndex,
            ])
        } catch let error as NSError where DailyGameLimitError.matches(error) {
            throw DailyGameLimitError()
        }
    }

    /// The couple has used today's free game (createGame's
    /// `resource-exhausted` with reason `daily-game-limit`). The composer
    /// answers it with the premium paywall.
    struct DailyGameLimitError: LocalizedError {
        var errorDescription: String? { "You've played today's free game. Premium makes games unlimited." }

        /// Matched on the reason, not the code: "too many active games" is
        /// also resource-exhausted.
        static func matches(_ error: NSError) -> Bool {
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            return details?["reason"] as? String == "daily-game-limit"
                || error.localizedDescription == "daily-game-limit"
        }
    }

    #if DEBUG
    /// Games sent this demo session, for the demo's daily limit.
    private var demoGamesToday = 0
    #endif

    struct GameResult {
        var correct: Bool
        var answerIndex: Int
        /// The WINNER earned a card — which is the author when I guessed wrong.
        var cardEarned: Bool
        var winnerId: String?
    }

    /// Answer a game my partner sent. The server resolves it on the spot.
    func answerGame(_ game: Challenge, guessIndex: Int) async throws -> GameResult {
        #if DEBUG
        if AuthService.isDemo {
            let answer = Int.random(in: 0..<(game.options?.count ?? 2))
            let correct = game.gameKind == .likelyTo ? answer != guessIndex : answer == guessIndex
            if let i = challenges.firstIndex(where: { $0.id == game.id }) {
                challenges[i].status = "completed"
                challenges[i].answerIndex = answer
                challenges[i].guessIndex = guessIndex
                challenges[i].correct = correct
                challenges[i].completedAt = Date()
            }
            return GameResult(correct: correct, answerIndex: answer, cardEarned: false, winnerId: nil)
        }
        #endif
        let result = try await CloudFunctions.shared.call("answerGame", [
            "challengeId": game.id,
            "guessIndex": guessIndex,
        ])
        return GameResult(
            correct: result["correct"] as? Bool ?? false,
            answerIndex: result["answerIndex"] as? Int ?? 0,
            cardEarned: result["cardEarned"] as? Bool ?? false,
            winnerId: result["winnerId"] as? String
        )
    }

    /// Games and legacy quizzes waiting on me.
    var myTurn: [Challenge] {
        challenges.filter { c in
            guard c.isActive else { return false }
            if c.isGame { return c.createdBy != userId }
            return c.type == "quiz" && !c.hasAnswered(userId)
        }
    }

    /// Games and legacy quizzes I sent that my partner hasn't played yet.
    var theirTurn: [Challenge] {
        challenges.filter { c in
            guard c.isActive else { return false }
            if c.isGame { return c.createdBy == userId }
            return c.type == "quiz" && c.hasAnswered(userId)
        }
    }

    /// Finished games, newest first.
    var recentResults: [Challenge] {
        challenges
            .filter { $0.isGame && !$0.isActive }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    func wins(for uid: String) -> Int { gameStats.wins[uid] ?? 0 }
    var myWins: Int { wins(for: userId) }
    var partnerWins: Int { partnerId.map(wins(for:)) ?? 0 }
    var myCardProgress: Int { min(gameStats.cardProgress[userId] ?? 0, GameStats.cardEvery) }

    // MARK: - Task renegotiation

    /// request → partner accepts (or declines) → both negotiate → complete.
    enum RenegotiationAction: String { case request, cancel, accept, decline, complete }

    func renegotiateTasks(_ action: RenegotiationAction) async throws {
        #if DEBUG
        if AuthService.isDemo {
            switch action {
            case .request: taskRenegotiation = TaskRenegotiation(requestedBy: userId, requestedAt: Date())
            case .accept: taskRenegotiation?.accepted = true
            case .cancel, .decline, .complete: taskRenegotiation = nil
            }
            return
        }
        #endif
        _ = try requireCouple()
        try await CloudFunctions.shared.call("taskRenegotiation", ["action": action.rawValue])
    }

    // MARK: - Photo Dash (challenges are created by the server at random)

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

    /// A drawn stand-in photo (warm gradient + paw) as base64 JPEG, the same
    /// shape a real photo dash stores. Drawn rather than bundled so the demo
    /// needs no asset; no emoji, which iOS 26 sims can't render.
    private static func demoPhotoBase64() -> String? {
        let size = CGSize(width: 600, height: 400)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: 150, weight: .bold)
            if let paw = UIImage(systemName: "pawprint.fill", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                paw.draw(at: CGPoint(x: (size.width - paw.size.width) / 2,
                                     y: (size.height - paw.size.height) / 2))
            }
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }

    private func loadMockData() {
        anniversary = Calendar.current.date(byAdding: .day, value: 12, to: Date())
        let me = userId, them = "mock_partner"
        let hour: TimeInterval = 3_600
        func game(_ id: String, _ kind: GameKind, _ prompt: String, _ options: [String],
                  by: String, ago: TimeInterval, answer: Int? = nil, guess: Int? = nil,
                  correct: Bool? = nil, winner: String? = nil) -> Challenge {
            Challenge(id: id, coupleKey: "demo", type: "game", title: kind.title, prompt: prompt,
                      createdBy: by, participants: [me, them],
                      status: answer == nil ? "active" : "completed",
                      createdAt: Date().addingTimeInterval(-ago), options: options,
                      winnerId: winner, completedAt: answer == nil ? nil : Date().addingTimeInterval(-ago + hour),
                      kind: kind.rawValue, answerIndex: answer, guessIndex: guess, correct: correct)
        }
        challenges = [
            game("g1", .preference, "What would your partner prefer for a vacation?",
                 ["Italy 🇮🇹", "Sweden 🇸🇪"], by: them, ago: hour),
            game("g2", .twoTruths, "Two truths and a lie",
                 ["I once met a Beatle", "I can juggle", "I've never seen Star Wars"], by: them, ago: 3 * hour),
            game("g3", .ballKnowledge, "What was the name of my first pet?",
                 ["Biscuit", "Rex", "Mr. Whiskers"], by: me, ago: 5 * hour),
            game("g4", .likelyTo, "...fall asleep first on a movie night?",
                 ["me", "you"], by: them, ago: 26 * hour, answer: 0, guess: 1, correct: true),
            game("g5", .preference, "Your partner's breakfast pick?",
                 ["Sweet 🥞", "Savory 🍳"], by: me, ago: 30 * hour, answer: 1, guess: 1,
                 correct: true, winner: them),
        ]
        // A won photo dash, so the Home result card (and its Save button) shows.
        challenges.append(Challenge(
            id: "p1", coupleKey: "demo", type: "photo", title: "Photo Dash",
            prompt: "Send a picture of your coffee ☕️", createdBy: them, participants: [me, them],
            status: "completed", createdAt: Date().addingTimeInterval(-2 * hour),
            photoData: Self.demoPhotoBase64(), winnerId: me,
            completedAt: Date().addingTimeInterval(-hour)))
        var stats = GameStats()
        stats.played = 12
        stats.wins = [me: 7, them: 4]
        stats.likelyToPlayed = 3
        stats.inSync = 2
        stats.cardProgress = [me: 3]
        gameStats = stats
    }
}
