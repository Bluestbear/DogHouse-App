//
//  ModerationService.swift
//  DogHouse
//
//  Reporting and blocking (App Store Guideline 1.2). Reports are written
//  straight to /reports (create-only) and emailed to the developer by a
//  Cloud Function. Blocks go through the blockUser / unblockUser callables,
//  which also sever the couple friendship; this service listens on the
//  owner-only /blocks/{uid} doc so the feed and friends list can filter.
//

import SwiftUI
import Combine
import OSLog
import FirebaseAuth
import FirebaseFirestore

enum ReportTarget {
    case feedPost(FeedPost)
    case user(id: String, name: String)
    case photo(challengeId: String, ownerId: String, ownerName: String)

    var typeName: String {
        switch self {
        case .feedPost: "feedPost"
        case .user: "user"
        case .photo: "photo"
        }
    }
    var targetId: String {
        switch self {
        case .feedPost(let p): p.id
        case .user(let id, _): id
        case .photo(let id, _, _): id
        }
    }
    var targetUserId: String {
        switch self {
        case .feedPost(let p): p.senderId
        case .user(let id, _): id
        case .photo(_, let owner, _): owner
        }
    }
    var title: String {
        switch self {
        case .feedPost: "Report this sending"
        case .user(_, let name): "Report \(name)"
        case .photo(_, _, let name): "Report \(name)'s photo"
        }
    }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case harassment = "Harassment or bullying"
    case hateful = "Hateful or abusive"
    case sexual = "Sexual content"
    case privacy = "Shares private information"
    case spam = "Spam or impersonation"
    case other = "Something else"
    var id: String { rawValue }
}

class ModerationService: ObservableObject {
    static let shared = ModerationService()

    @Published private(set) var blockedUserIds: Set<String> = []

    private let fs = FirebaseService.shared
    private var listener: ListenerRegistration?
    private var userId: String?

    private init() {}

    /// Follow the signed-in account. Safe to call repeatedly.
    func configure(userId newUserId: String?) {
        guard newUserId != userId else { return }
        userId = newUserId
        listener?.remove()
        blockedUserIds = []
        guard let uid = newUserId else { return }
        listener = fs.db.collection("blocks").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        Logger.data.error("Blocks listener: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    let ids = snapshot?.data()?["blockedUserIds"] as? [String] ?? []
                    self.blockedUserIds = Set(ids)
                }
            }
    }

    func isBlocked(_ id: String) -> Bool { blockedUserIds.contains(id) }

    /// A post is hidden when either half of the sending couple is blocked.
    func isHidden(_ post: FeedPost) -> Bool {
        isBlocked(post.senderId) || isBlocked(post.receiverId)
    }

    func report(_ target: ReportTarget, reason: ReportReason, details: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await fs.db.collection("reports").document().setData([
            "reporterId": uid,
            "targetType": target.typeName,
            "targetId": target.targetId,
            "targetUserId": target.targetUserId,
            "reason": reason.rawValue,
            "details": String(details.prefix(1000)),
            "createdAt": Timestamp(date: Date()),
        ])
        AnalyticsService.shared.log(.reportContent, ["type": target.typeName])
    }

    func block(userId: String) async throws {
        try await CloudFunctions.shared.call("blockUser", ["userId": userId])
        blockedUserIds.insert(userId) // optimistic; the listener confirms
        AnalyticsService.shared.log(.blockUser)
    }

    func unblock(userId: String) async throws {
        try await CloudFunctions.shared.call("unblockUser", ["userId": userId])
        blockedUserIds.remove(userId)
    }
}
