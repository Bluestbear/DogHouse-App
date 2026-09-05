//
//  AchievementService.swift
//  DogHouse
//
//  Keeps the couple's achievements/{coupleKey} document: which badges are
//  unlocked (and when) plus the roses / belly-rub counters. Judging happens
//  in `Achievement.progress(in:)`; this only persists what Home hands it.
//  Nothing here touches economy state, so it may write directly — the rule
//  restricts the document to the two partners.
//

import Foundation
import Combine
import FirebaseFirestore
import OSLog

@MainActor
final class AchievementService: ObservableObject {
    @Published private(set) var unlockedAt: [AchievementID: Date] = [:]
    @Published private(set) var counters = AchievementCounters()
    /// The most recent unlock, for Home's toast. Home clears it.
    @Published var justUnlocked: Achievement?

    private let fs = FirebaseService.shared
    private var listener: ListenerRegistration?
    private var coupleKey: String?
    /// Unlocks written but not yet echoed back by the listener, so a second
    /// evaluation in the meantime doesn't write them again.
    private var pendingWrites: Set<AchievementID> = []

    var unlockedCount: Int { unlockedAt.count }

    /// Attach to the couple's document. Safe to call repeatedly; it only
    /// re-subscribes when the couple changes.
    func configure(userId: String, partnerId: String?) {
        guard let partnerId, partnerId != "skipped" else { return }
        let key = fs.coupleKey(userId1: userId, userId2: partnerId)
        guard key != coupleKey else { return }
        listener?.remove()
        coupleKey = key
        #if DEBUG
        // Demo runs have no signed-in user; badges are judged locally only.
        if AuthService.isDemo { return }
        #endif
        listener = fs.achievementsCollection.document(key).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    Logger.data.error("Achievements listener: \(error.localizedDescription, privacy: .public)")
                    return
                }
                self.apply(snapshot?.data() ?? [:])
            }
        }
    }

    private func apply(_ data: [String: Any]) {
        var unlocked: [AchievementID: Date] = [:]
        for (raw, value) in data["unlocked"] as? [String: Any] ?? [:] {
            guard let id = AchievementID(rawValue: raw) else { continue }
            unlocked[id] = (value as? Timestamp)?.dateValue() ?? Date()
        }
        unlockedAt = unlocked
        pendingWrites.subtract(unlocked.keys)

        let c = data["counters"] as? [String: Any] ?? [:]
        counters = AchievementCounters(
            roses: c["roses"] as? Int ?? 0,
            bellyRubs: c["bellyRubs"] as? Int ?? 0
        )
    }

    /// Persist any achievements the snapshot now satisfies. Already-unlocked
    /// ones are never re-evaluated, so a badge can't be lost.
    func evaluate(_ snapshot: AchievementSnapshot) {
        guard let coupleKey else { return }
        let newly = Achievement.all.filter {
            unlockedAt[$0.id] == nil && !pendingWrites.contains($0.id) && $0.isEarned(in: snapshot)
        }
        guard !newly.isEmpty else { return }

        #if DEBUG
        if AuthService.isDemo {
            for a in newly { unlockedAt[a.id] = snapshot.now }
            justUnlocked = newly.first
            return
        }
        #endif
        pendingWrites.formUnion(newly.map(\.id))
        let stamp = Timestamp(date: snapshot.now)
        let payload: [String: Any] = [
            "unlocked": Dictionary(uniqueKeysWithValues: newly.map { ($0.id.rawValue, stamp) })
        ]
        // Merge so two partners unlocking different badges at once don't
        // overwrite each other.
        fs.achievementsCollection.document(coupleKey).setData(payload, merge: true) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, let error else { return }
                self.pendingWrites.subtract(newly.map(\.id))
                Logger.data.error("Achievement write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        justUnlocked = newly.first
    }

    enum Counter: String { case roses, bellyRubs }

    /// Bump a couple counter. Fire-and-forget: a lost increment costs one
    /// rose towards a badge, not anything that matters.
    func record(_ counter: Counter) {
        guard let coupleKey else { return }
        #if DEBUG
        if AuthService.isDemo {
            switch counter {
            case .roses: counters.roses += 1
            case .bellyRubs: counters.bellyRubs += 1
            }
            return
        }
        #endif
        fs.achievementsCollection.document(coupleKey).setData(
            ["counters": [counter.rawValue: FieldValue.increment(Int64(1))]],
            merge: true
        )
    }

    isolated deinit {
        listener?.remove()
    }
}
