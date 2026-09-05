//
//  FriendsFeedSection.swift
//  DogHouse
//
//  Feed of friends' public doghouse sendings with ❤️/🐶 reactions,
//  plus the jailbreak-vote banner when two friends are in at once.
//

import SwiftUI

// MARK: - Jailbreak Vote Banner

struct JointVoteBanner: View {
    let vote: VoteEvent
    @ObservedObject var voteService: VoteService
    @ObservedObject var friendService: FriendService

    private var dogNames: String {
        let names = vote.doghousedUserIds.compactMap { vote.doghousedUserNames?[$0] }
        return names.isEmpty ? "Two friends" : names.joined(separator: " & ")
    }

    var body: some View {
        NavigationLink {
            JointVoteLoaderView(
                vote: vote,
                voteService: voteService,
                friendService: friendService
            )
        } label: {
            HStack(spacing: 12) {
                Text("🚨")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("JAILBREAK VOTE!")
                        .font(.caption.bold())
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(dogNames) are both in the DogHouse")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Vote who goes free →")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Text(vote.endsAt, style: .timer)
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.86, green: 0.33, blue: 0.33), Color.cozyOrange],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
    }
}

/// Loads the doghoused users' profiles, then shows the vote screen
struct JointVoteLoaderView: View {
    let vote: VoteEvent
    @ObservedObject var voteService: VoteService
    @ObservedObject var friendService: FriendService

    @State private var profiles: [UserProfile]?

    var body: some View {
        Group {
            if let profiles {
                VoteEventView(
                    voteService: voteService,
                    voteEvent: voteService.activeVoteEvents.first { $0.id == vote.id } ?? vote,
                    doghousedUsers: profiles
                )
            } else {
                ProgressView("Fetching the dogs...")
            }
        }
        .task {
            profiles = (try? await friendService.fetchProfiles(for: vote.doghousedUserIds)) ?? []
        }
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let post: FeedPost
    @ObservedObject var feedService: FeedService
    /// Ids of the votes currently running. A post keeps its `voteEventId`
    /// after the vote settles (the losing dog stays in), so the badge must
    /// check the vote, not the post.
    var activeVoteIds: Set<String> = []

    private var isInActiveVote: Bool {
        guard post.isActive, let voteId = post.voteEventId else { return false }
        return activeVoteIds.contains(voteId)
    }

    private var myReaction: FeedReaction? {
        post.reaction(of: feedService.userId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: who sent whom
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        avatar: DogAvatar.avatar(for: post.receiverAvatarId ?? "dog_1"),
                        mood: post.isActive ? .sad : .happy,
                        size: 44,
                        blinks: false
                    )
                    Text(post.isActive ? "🏚️" : "🏠")
                        .font(.system(size: 15))
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(post.senderName).bold()) sent \(Text(post.receiverName).bold()) to the DogHouse")
                        .font(.subheadline)

                    Text("\(Text(post.createdAt, style: .relative)) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }

            // Reason
            Text("“\(post.reason)”")
                .font(.callout.italic())
                .foregroundStyle(.primary.opacity(0.85))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Reactions + roast menu
            HStack(spacing: 10) {
                reactionButton(.back, count: post.backCount, label: "Back it")
                reactionButton(.dog, count: post.dogCount, label: "Free the dog")
                roastMenu
                Spacer()
                if isInActiveVote {
                    Label("In a vote", systemImage: "hand.raised.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.cozyOrange)
                }
            }

            // Latest roasts
            if let roasts = post.roasts, !roasts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(roasts.values.sorted().prefix(3), id: \.self) { roast in
                        HStack(spacing: 6) {
                            Text("🔥")
                                .font(.caption2)
                            Text(roast)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var roastMenu: some View {
        Menu {
            ForEach(CannedRoast.all, id: \.self) { roast in
                Button(roast) {
                    HapticService.shared.success()
                    Task { try? await feedService.roast(post, with: roast) }
                }
            }
            if post.roasts?[feedService.userId] != nil {
                Divider()
                Button("Remove my roast", role: .destructive) {
                    Task { try? await feedService.roast(post, with: nil) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("🔥")
                Text("Roast")
                    .font(.caption.weight(.semibold))
                if let count = post.roasts?.count, count > 0 {
                    Text("\(count)")
                        .font(.caption.bold().monospacedDigit())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                post.roasts?[feedService.userId] != nil
                    ? Color.red.opacity(0.15)
                    : Color(.systemGray6)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Group {
            if post.isActive {
                Text("IN THE HOUSE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.86, green: 0.33, blue: 0.33))
                    .clipShape(Capsule())
            } else {
                Text(post.releasedByVote == true
                     ? "FREED BY VOTE"
                     : "Served \(post.servedDuration.feedFormatted)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.freedomGreen)
                    .clipShape(Capsule())
            }
        }
    }

    private func reactionButton(_ reaction: FeedReaction, count: Int, label: String) -> some View {
        let isMine = myReaction == reaction
        return Button {
            HapticService.shared.success()
            Task { try? await feedService.react(to: post, with: reaction) }
        } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                Text(label)
                    .font(.caption.weight(.semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold().monospacedDigit())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isMine ? Color.cozyOrange.opacity(0.25) : Color(.systemGray6))
            .overlay(
                Capsule().stroke(isMine ? Color.cozyOrange : Color.clear, lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isMine)
    }
}

// MARK: - Top Dog Leaderboard

/// Aggregates total time served per dog from the visible feed window
struct TopDogLeaderboard: View {
    let posts: [FeedPost]

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let avatarId: String?
        let totalServed: TimeInterval
        let stints: Int
    }

    private var entries: [Entry] {
        var byDog: [String: Entry] = [:]
        for post in posts {
            let served = post.servedDuration
            if let existing = byDog[post.receiverId] {
                byDog[post.receiverId] = Entry(
                    id: existing.id, name: existing.name, avatarId: existing.avatarId,
                    totalServed: existing.totalServed + served,
                    stints: existing.stints + 1
                )
            } else {
                byDog[post.receiverId] = Entry(
                    id: post.receiverId, name: post.receiverName,
                    avatarId: post.receiverAvatarId,
                    totalServed: served, stints: 1
                )
            }
        }
        return byDog.values.sorted { $0.totalServed > $1.totalServed }
    }

    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
            HStack(spacing: 12) {
                Text(index < medals.count ? medals[index] : "  ")
                    .font(.title3)

                AvatarView(
                    avatar: DogAvatar.avatar(for: entry.avatarId ?? "dog_1"),
                    mood: index == 0 ? .sad : .happy,
                    size: 36,
                    blinks: false
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.bold())
                    Text("\(entry.stints) stint\(entry.stints == 1 ? "" : "s") this week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(entry.totalServed.feedFormatted)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(index == 0 ? .red : .secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Duration formatting for the feed

extension TimeInterval {
    var feedFormatted: String {
        let minutes = Int(self) / 60
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
