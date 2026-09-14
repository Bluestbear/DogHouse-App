//
//  BlockedUsersView.swift
//  DogHouse
//
//  Profile → Blocked People. Lists who you've blocked and lets you undo it.
//

import SwiftUI

struct BlockedUsersView: View {
    @ObservedObject private var moderation = ModerationService.shared
    @StateObject private var friendService = FriendService(userId: "mock_user")
    @State private var names: [String: String] = [:]
    @State private var errorText: String?

    private var ids: [String] { moderation.blockedUserIds.sorted() }

    var body: some View {
        List {
            if ids.isEmpty {
                EmptyStateView(
                    icon: "hand.raised.slash",
                    title: "Nobody Blocked",
                    subtitle: "People you block from the feed or a friend couple show up here."
                )
            } else {
                ForEach(ids, id: \.self) { id in
                    HStack {
                        Text(names[id] ?? "Someone")
                        Spacer()
                        Button("Unblock") {
                            Task {
                                do { try await moderation.unblock(userId: id) }
                                catch { errorText = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.dogHouseBrown)
                    }
                }
                if let errorText {
                    Text(errorText).font(.dhCaption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Blocked People")
        .dhPageBackground()
        .task(id: ids) {
            let profiles = (try? await friendService.fetchProfiles(for: ids)) ?? []
            for p in profiles { names[p.id] = p.displayName }
        }
    }
}
