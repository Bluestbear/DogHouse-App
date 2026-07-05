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

    deinit {
        taskDocListener?.remove()
    }

    // MARK: - Real-Time Listener

    private func startListening() {
        let docRef = fs.onboardingTasksCollection.document(coupleKey)
        taskDocListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
                    print("Failed to decode onboarding tasks: \(error)")
                }
            }
        }
    }

    // MARK: - Phase 5A: Submit Tasks

    func submitMyTasks(_ tasks: [OnboardingTask]) async throws {
        isLoading = true
        defer { isLoading = false }

        let docRef = fs.onboardingTasksCollection.document(coupleKey)
        let sortedIds = [userId, partnerId].sorted()
        let isUser1 = userId == sortedIds[0]

        let tasksData: [[String: Any]] = tasks.map {
            ["id": $0.id, "title": $0.title]
        }

        if taskDocument == nil {
            // First user to submit — create the doc
            let initialDoc: [String: Any] = [
                "id": coupleKey,
                "coupleId": coupleKey,
                "user1Id": sortedIds[0],
                "user1Tasks": isUser1 ? tasksData : [] as [[String: Any]],
                "user1Submitted": isUser1,
                "user2Id": sortedIds[1],
                "user2Tasks": isUser1 ? [] as [[String: Any]] : tasksData,
                "user2Submitted": !isUser1,
                "user1Strikes": [] as [[String: Any]],
                "user1ReviewComplete": false,
                "user2Strikes": [] as [[String: Any]],
                "user2ReviewComplete": false,
                "user1Confirmed": false,
                "user2Confirmed": false,
                "finalTasks": [] as [[String: Any]],
            ]
            try await docRef.setData(initialDoc, merge: true)
        } else {
            // Document exists — update my slot
            let prefix = isUser1 ? "user1" : "user2"
            try await docRef.updateData([
                "\(prefix)Tasks": tasksData,
                "\(prefix)Submitted": true,
            ])
        }
    }

    // MARK: - Phase 5B: Submit Review (Strikes)

    func submitReview(strikes: [TaskStrike]) async throws {
        isLoading = true
        defer { isLoading = false }

        let docRef = fs.onboardingTasksCollection.document(coupleKey)
        let sortedIds = [userId, partnerId].sorted()
        let isUser1 = userId == sortedIds[0]
        let prefix = isUser1 ? "user1" : "user2"

        let strikesData: [[String: Any]] = strikes.map {
            ["originalTaskId": $0.originalTaskId, "replacementTitle": $0.replacementTitle]
        }

        try await docRef.updateData([
            "\(prefix)Strikes": strikesData,
            "\(prefix)ReviewComplete": true,
        ])
    }

    // MARK: - Phase 5C: Build Final Task List

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
                    id: UUID().uuidString,
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
                    id: UUID().uuidString,
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

        let docRef = fs.onboardingTasksCollection.document(coupleKey)
        let finalData: [[String: Any]] = finalTasks.map {
            ["id": $0.id, "title": $0.title, "suggestedBy": $0.suggestedBy, "isAppSuggestion": $0.isAppSuggestion]
        }
        try await docRef.updateData(["finalTasks": finalData])
    }

    // MARK: - Phase 5C: Confirm Final List

    func confirmFinalList() async throws {
        isLoading = true
        defer { isLoading = false }

        let docRef = fs.onboardingTasksCollection.document(coupleKey)
        let sortedIds = [userId, partnerId].sorted()
        let isUser1 = userId == sortedIds[0]
        let prefix = isUser1 ? "user1" : "user2"

        try await docRef.updateData(["\(prefix)Confirmed": true])
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
