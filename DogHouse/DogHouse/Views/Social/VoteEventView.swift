//
//  VoteEventView.swift
//  DogHouse
//

import SwiftUI
import Combine

struct VoteEventView: View {
    @ObservedObject var voteService: VoteService
    var voteEvent: VoteEvent

    // Mock user data for the doghoused users
    var doghousedUsers: [UserProfile]

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var currentDate = Date()
    @State private var showConfetti = false
    @State private var isResolving = false
    @State private var resolvedWinnerId: String?

    private var timeRemaining: TimeInterval {
        max(voteEvent.endsAt.timeIntervalSince(currentDate), 0)
    }

    private var isExpired: Bool {
        timeRemaining <= 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("🐕 Who Let The Dogs Out?")
                        .font(.dhTitle)

                    Text("Vote to free a dog!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                // Countdown
                VStack(spacing: 4) {
                    Text("Time Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeRemaining.formattedTimer)
                        .font(Font.dhTimer)
                        .foregroundStyle(timeRemaining < 300 ? .red : Color.cozyOrange)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                // Candidates
                ForEach(doghousedUsers) { user in
                    candidateCard(user: user)
                }

                // Result section
                if isExpired {
                    resultView
                }
            }
        }
        .onReceive(timer) { date in
            currentDate = date
            guard timeRemaining <= 0, !isResolving, resolvedWinnerId == nil else { return }
            isResolving = true
            // Compute winner locally for immediate display; the server
            // (resolveExpiredVotes) is the authority and performs the release.
            let liveEvent = voteService.activeVoteEvents.first { $0.id == voteEvent.id } ?? voteEvent
            var voteCounts: [String: Int] = [:]
            for votedForId in liveEvent.votes.values {
                voteCounts[votedForId, default: 0] += 1
            }
            resolvedWinnerId = voteCounts.max(by: { $0.value < $1.value })?.key
        }
        .overlay {
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Candidate Card

    private func candidateCard(user: UserProfile) -> some View {
        let votes = voteService.votesFor(userId: user.id, in: voteEvent.id)
        let hasVoted = voteService.hasVoted(in: voteEvent.id)
        let votedForThis = voteEvent.votes.values.contains(user.id)
        let total = voteService.totalVotes(in: voteEvent.id)
        let percentage = total > 0 ? Double(votes) / Double(total) : 0

        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Mini doghouse with avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)

                    AvatarView(
                        avatar: DogAvatar.avatar(for: user.avatarId ?? "dog_1"),
                        mood: .sad,
                        size: 44,
                        blinks: false
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.headline)

                    Text("\(votes) vote\(votes == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isExpired && !hasVoted {
                    Button {
                        Task {
                            try? await voteService.castVote(
                                voteEventId: voteEvent.id,
                                votedForUserId: user.id
                            )
                        }
                    } label: {
                        Text("Vote 🗳️")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.freedomGreen)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                } else if hasVoted && votedForThis {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.freedomGreen)
                        .font(.title2)
                }
            }

            // Vote bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.freedomGreen.opacity(0.6))
                        .frame(width: geo.size.width * percentage)
                        .animation(.easeInOut, value: percentage)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(spacing: 12) {
            Text("🎵 WHO LET THE DOGS OUT 🎵")
                .font(.dhSubtitle)
                .foregroundStyle(Color.cozyOrange)

            if let winnerId = resolvedWinnerId ?? voteEvent.winnerId,
               let winner = doghousedUsers.first(where: { $0.id == winnerId }) {
                AvatarView(
                    avatar: DogAvatar.avatar(for: winner.avatarId ?? "dog_1"),
                    mood: .happy,
                    size: 80
                )
                Text("\(winner.displayName) is FREE!")
                    .font(.headline)
                    .foregroundStyle(Color.freedomGreen)
            } else {
                Text("Voting has ended!")
                    .font(.headline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation {
                showConfetti = true
            }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showConfetti = false }
            }
        }
    }
}

// MARK: - Simple Confetti

struct ConfettiView: View {
    @State private var particles: [(id: Int, x: CGFloat, y: CGFloat, color: Color, rotation: Double)] = []

    var body: some View {
        ZStack {
            ForEach(particles, id: \.id) { particle in
                RoundedRectangle(cornerRadius: 2)
                    .fill(particle.color)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(particle.rotation))
                    .position(x: particle.x, y: particle.y)
            }
        }
        .onAppear {
            let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink]
            let screen = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
            for i in 0..<40 {
                let startX = CGFloat.random(in: 0...screen.width)
                particles.append((
                    id: i,
                    x: startX,
                    y: -20,
                    color: colors.randomElement()!,
                    rotation: Double.random(in: 0...360)
                ))
            }
            // Animate particles falling
            withAnimation(.easeIn(duration: 2.0)) {
                for i in particles.indices {
                    particles[i].y = screen.height + 20
                    particles[i].rotation += Double.random(in: 180...720)
                }
            }
        }
    }
}

#Preview {
    VoteEventView(
        voteService: VoteService(userId: "me"),
        voteEvent: VoteEvent(
            id: "vote_1",
            groupId: "group_1",
            doghousedUserIds: ["friend_1", "friend_2"],
            votes: ["voter_1": "friend_1"],
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(1800),
            winnerId: nil,
            status: "active"
        ),
        doghousedUsers: [
            UserProfile(id: "friend_1", displayName: "Jordan", avatarId: "dog_3", partnerCode: "ABC123", partnerId: nil, immunityUntil: nil, friendIds: [], createdAt: Date(), fcmToken: nil),
            UserProfile(id: "friend_2", displayName: "Riley", avatarId: "dog_5", partnerCode: "XYZ789", partnerId: nil, immunityUntil: nil, friendIds: [], createdAt: Date(), fcmToken: nil),
        ]
    )
}
