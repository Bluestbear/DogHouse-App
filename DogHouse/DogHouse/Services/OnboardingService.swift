//
//  OnboardingService.swift
//  DogHouse
//
//  Manages the task negotiation onboarding flow (Steps 5A/5B/5C).
//  Attaches a real-time Firestore listener on onboardingTasks/{coupleKey}
//  so both partners see updates live.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import OSLog

@MainActor
class OnboardingService: ObservableObject {

    // MARK: - Published State

    @Published var taskDocument: OnboardingTasksDocument?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let fs = FirebaseService.shared
    private var taskDocListener: ListenerRegistration?
    private var didFinalizeOnboarding = false
    let userId: String
    let partnerId: String

    var coupleKey: String {
        fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    // MARK: - Init / Deinit

    init(userId: String, partnerId: String) {
        self.userId = userId
        self.partnerId = partnerId
        startListening()
    }

    isolated deinit {
        taskDocListener?.remove()
    }

    // MARK: - Real-Time Listener

    private func startListening() {
        let docRef = fs.onboardingTasksCollection.document(coupleKey)
        taskDocListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Never swallow this. Firestore tears a listener down for good
                // when a read is denied, so the symptom of a bad rule is not an
                // error anywhere — it is a screen that waits forever. This log
                // is the difference between "it just spins" and a diagnosis.
                if let error {
                    Logger.data.error("Onboarding listener failed: \(error.localizedDescription, privacy: .public)")
                    self.errorMessage = "Couldn't sync with your partner. Check your connection and reopen the app."
                    return
                }
                self.errorMessage = nil

                guard let snapshot, snapshot.exists else {
                    self.taskDocument = nil
                    return
                }
                do {
                    let doc = try self.fs.decode(OnboardingTasksDocument.self, from: snapshot)
                    self.taskDocument = doc

                    // When both partners confirm, each user independently finalizes their own
                    // side — avoids cross-user Firestore writes that security rules block.
                    if doc.bothConfirmed && !self.didFinalizeOnboarding {
                        self.didFinalizeOnboarding = true
                        Task { try? await self.finalizeOnboardingForCurrentUser(finalTasks: doc.finalTasks) }
                    }
                } catch {
                    Logger.data.error("Onboarding task decode failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - My Half of the Document

    private var sortedIds: [String] { [userId, partnerId].sorted() }
    private var myPrefix: String { userId == sortedIds[0] ? "user1" : "user2" }

    /// Write only this user's own fields, plus the document's identity.
    ///
    /// Every negotiation write goes through here, and none of them ever names a
    /// field belonging to the partner. That is what makes the two clients safe to
    /// run in any order: disjoint `merge: true` writes commute, so neither can
    /// undo the other.
    ///
    /// The previous version branched on `taskDocument == nil` and, on that branch,
    /// wrote BOTH halves — including `user2Submitted: false`. When both partners
    /// tapped Submit before either had received a snapshot (the normal case when
    /// a couple onboards side by side), the second write reset the first
    /// partner's tasks and their submitted flag. Each client had already set its
    /// own `hasSubmitted` locally, so both showed "Tasks Submitted!" and waited
    /// on a partner who, as far as the document was concerned, had never
    /// submitted at all.
    private func writeMyFields(_ fields: [String: Any]) async throws {
        var data: [String: Any] = [
            "id": coupleKey,
            "coupleId": coupleKey,
            "user1Id": sortedIds[0],
            "user2Id": sortedIds[1],
        ]
        data.merge(fields) { _, mine in mine }
        try await fs.onboardingTasksCollection.document(coupleKey).setData(data, merge: true)
    }

    // MARK: - Phase 5A: Submit Tasks

    func submitMyTasks(_ tasks: [OnboardingTask]) async throws {
        isLoading = true
        defer { isLoading = false }

        let tasksData: [[String: Any]] = tasks.map {
            ["id": $0.id, "title": $0.title]
        }

        try await writeMyFields([
            "\(myPrefix)Tasks": tasksData,
            "\(myPrefix)Submitted": true,
        ])
    }

    // MARK: - Phase 5B: Submit Review (Strikes)

    func submitReview(strikes: [TaskStrike]) async throws {
        isLoading = true
        defer { isLoading = false }

        let strikesData: [[String: Any]] = strikes.map {
            ["originalTaskId": $0.originalTaskId, "replacementTitle": $0.replacementTitle]
        }

        try await writeMyFields([
            "\(myPrefix)Strikes": strikesData,
            "\(myPrefix)ReviewComplete": true,
        ])
    }

    // MARK: - Phase 5C: Build Final Task List

    /// Both clients reach this phase and both build the list, so the result has
    /// to be identical on each — otherwise the two writes race and the partners
    /// briefly see different task lists. Deriving the replacement's id from the
    /// struck task's id (rather than a fresh UUID) makes the whole array a pure
    /// function of the document, which makes the duplicate write harmless.
    private func replacementId(for struckTaskId: String) -> String {
        "\(struckTaskId)_replacement"
    }

    func buildFinalTaskListIfNeeded() async throws {
        guard let doc = taskDocument, doc.bothReviewComplete, doc.finalTasks.isEmpty else { return }

        var finalTasks: [CoupleTask] = []

        let user1StrikeIds = Set(doc.user1Strikes.map { $0.originalTaskId })
        let user2StrikeIds = Set(doc.user2Strikes.map { $0.originalTaskId })

        // User1's tasks (suggested for user2 to do) — user2 may have struck some
        for task in doc.user1Tasks {
            if user2StrikeIds.contains(task.id),
               let strike = doc.user2Strikes.first(where: { $0.originalTaskId == task.id }) {
                finalTasks.append(CoupleTask(
                    id: replacementId(for: task.id),
                    title: strike.replacementTitle,
                    suggestedBy: "app",
                    isAppSuggestion: true
                ))
            } else {
                finalTasks.append(CoupleTask(
                    id: task.id,
                    title: task.title,
                    suggestedBy: doc.user1Id,
                    isAppSuggestion: false
                ))
            }
        }

        // User2's tasks (suggested for user1 to do) — user1 may have struck some
        for task in doc.user2Tasks {
            if user1StrikeIds.contains(task.id),
               let strike = doc.user1Strikes.first(where: { $0.originalTaskId == task.id }) {
                finalTasks.append(CoupleTask(
                    id: replacementId(for: task.id),
                    title: strike.replacementTitle,
                    suggestedBy: "app",
                    isAppSuggestion: true
                ))
            } else {
                finalTasks.append(CoupleTask(
                    id: task.id,
                    title: task.title,
                    suggestedBy: doc.user2Id,
                    isAppSuggestion: false
                ))
            }
        }

        let finalData: [[String: Any]] = finalTasks.map {
            ["id": $0.id, "title": $0.title, "suggestedBy": $0.suggestedBy, "isAppSuggestion": $0.isAppSuggestion]
        }
        // Shared field rather than a per-user one, but both clients compute the
        // identical array (see replacementId), so whichever write lands last
        // writes the same bytes.
        try await writeMyFields(["finalTasks": finalData])
    }

    // MARK: - Phase 5C: Confirm Final List

    func confirmFinalList() async throws {
        isLoading = true
        defer { isLoading = false }

        try await writeMyFields(["\(myPrefix)Confirmed": true])
        // Snapshot listener detects bothConfirmed and calls finalizeOnboardingForCurrentUser
    }

    // MARK: - Finalize Onboarding (own document only)

    // Each user calls this independently when the snapshot shows bothConfirmed.
    // Writing only to our own user document avoids cross-user security rule violations.
    // setData(merge:true) on coupleTasks is safe if both users write simultaneously.
    private func finalizeOnboardingForCurrentUser(finalTasks: [CoupleTask]) async throws {
        let coupleTaskRef = fs.coupleTasksCollection.document(coupleKey)
        let tasksData: [[String: Any]] = finalTasks.map {
            ["id": $0.id, "title": $0.title, "suggestedBy": $0.suggestedBy, "isAppSuggestion": $0.isAppSuggestion]
        }
        try await coupleTaskRef.setData([
            "coupleId": coupleKey,
            "tasks": tasksData,
            "createdAt": Timestamp(date: Date()),
        ], merge: true)

        try await fs.usersCollection.document(userId).updateData(["onboardingComplete": true])
    }
}
