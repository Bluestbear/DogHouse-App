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
    /// A plain button rather than a NavigationLink: inside a List the link
    /// adds a disclosure chevron beside the banner, which both clutters it
    /// and makes it narrower than the feed card below.
    let onOpen: () -> Void

    private var dogNames: String {
        let names = vote.doghousedUserIds.compactMap { vote.doghousedUserNames?[$0] }
        return names.isEmpty ? "Two friends" : names.joined(separator: " & ")
    }

    var body: some View {
        Button(action: onOpen) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.collarBrown)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // Zero side insets: the banner spans the same width as the feed card.
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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

    private var myReaction: FeedReaction? {
        post.reaction(of: feedService.userId)
    }

    @State private var reportTarget: ReportTarget?
    @State private var userToBlock: (id: String, name: String)?

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

                    // "Sent X to the DogHouse" already says they're in, so an
                    // active post needs no badge; only a finished one says so.
                    HStack(spacing: 4) {
                        Text("\(Text(post.createdAt, style: .relative)) ago")
                        if let outcome {
                            Text("·")
                            Text(outcome)
                                .foregroundStyle(Color.freedomGreen)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                moderationMenu
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
            // Full labels when they fit on one line, emoji + count when not,
            // so a pill never wraps mid-word.
            ViewThatFits(in: .horizontal) {
                reactionRow(compact: false)
                reactionRow(compact: true)
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
        .sheet(isPresented: Binding(
            get: { reportTarget != nil },
            set: { if !$0 { reportTarget = nil } }
        )) {
            if let reportTarget {
                ReportSheet(target: reportTarget,
                            blockableUser: (post.senderId, post.senderName))
            }
        }
        .alert("Block \(userToBlock?.name ?? "")?", isPresented: Binding(
            get: { userToBlock != nil },
            set: { if !$0 { userToBlock = nil } }
        )) {
            Button("Block", role: .destructive) {
                guard let user = userToBlock else { return }
                userToBlock = nil
                Task { try? await ModerationService.shared.block(userId: user.id) }
            }
            Button("Cancel", role: .cancel) { userToBlock = nil }
        } message: {
            Text("You'll stop seeing their sendings and the couple friendship is removed. They aren't told.")
        }
    }

    /// Report / block, required for anything other people wrote
    /// (App Store Guideline 1.2). The reason text on a post is free text.
    private var moderationMenu: some View {
        Menu {
            Button {
                reportTarget = .feedPost(post)
            } label: {
                Label("Report", systemImage: "flag")
            }
            Button(role: .destructive) {
                userToBlock = (post.senderId, post.senderName)
            } label: {
                Label("Block \(post.senderName)", systemImage: "hand.raised")
            }
            Button(role: .destructive) {
                userToBlock = (post.receiverId, post.receiverName)
            } label: {
                Label("Block \(post.receiverName)", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func roastMenu(compact: Bool) -> some View {
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
                if !compact {
                    Text("Roast")
                        .font(.caption.weight(.semibold))
                }
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
            .lineLimit(1)
            .fixedSize()
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Roast")
    }

    /// How a finished stint ended, shown beside the timestamp. nil while
    /// the dog is still in.
    private var outcome: String? {
        guard !post.isActive else { return nil }
        return post.releasedByVote == true
            ? "freed by vote"
            : "served \(post.servedDuration.feedFormatted)"
    }

    private func reactionRow(compact: Bool) -> some View {
        HStack(spacing: 8) {
            reactionButton(.back, count: post.backCount, label: "Back it", compact: compact)
            reactionButton(.dog, count: post.dogCount, label: "Free the dog", compact: compact)
            roastMenu(compact: compact)
            Spacer(minLength: 0)
        }
    }

    private func reactionButton(_ reaction: FeedReaction, count: Int, label: String, compact: Bool) -> some View {
        let isMine = myReaction == reaction
        return Button {
            HapticService.shared.success()
            Task { try? await feedService.react(to: post, with: reaction) }
        } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                if !compact {
                    Text(label)
                        .font(.caption.weight(.semibold))
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold().monospacedDigit())
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isMine ? Color.cozyOrange.opacity(0.25) : Color(.systemGray6))
            .overlay(
                Capsule().stroke(isMine ? Color.cozyOrange : Color.clear, lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(label), \(count)" : label)
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
