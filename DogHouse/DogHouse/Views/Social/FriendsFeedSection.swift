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
                        size: 44
                    )
                    Text(post.isActive ? "🏚️" : "🏠")
                        .font(.system(size: 15))
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    (Text(post.senderName).bold()
                     + Text(" sent ")
                     + Text(post.receiverName).bold()
                     + Text(" to the DogHouse"))
                        .font(.subheadline)

                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    + Text(" ago")
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

            // Reactions
            HStack(spacing: 10) {
                reactionButton(.back, count: post.backCount, label: "Back it")
                reactionButton(.dog, count: post.dogCount, label: "Free the dog")
                Spacer()
                if post.voteEventId != nil && post.isActive {
                    Label("In a vote", systemImage: "hand.raised.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.cozyOrange)
                }
            }
        }
        .padding(.vertical, 6)
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

// MARK: - Duration formatting for the feed

private extension TimeInterval {
    var feedFormatted: String {
        let minutes = Int(self) / 60
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
