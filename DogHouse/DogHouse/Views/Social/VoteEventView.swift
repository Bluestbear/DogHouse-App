//
//  VoteEventView.swift
//  DogHouse
//

import SwiftUI

struct VoteEventView: View {
    @ObservedObject var voteService: VoteService
    var voteEvent: VoteEvent

    // Mock user data for the doghoused users
    var doghousedUsers: [UserProfile]

    @State private var showConfetti = false
    /// Flipped once, when the deadline passes — not polled every second.
    @State private var isExpired = false
    /// The settled document, once the server has resolved or cancelled the
    /// vote. Until then the outcome shown is a local provisional tally.
    @State private var finalEvent: VoteEvent?

    /// Freshest copy of the vote: the settled document, else the live
    /// listener's, else the one the banner was tapped with.
    private var currentEvent: VoteEvent {
        finalEvent
            ?? voteService.activeVoteEvents.first { $0.id == voteEvent.id }
            ?? voteEvent
    }

    private var tally: [String: Int] { currentEvent.tally }
    private var totalVotes: Int { tally.values.reduce(0, +) }
    private var hasVoted: Bool { currentEvent.votes[voteService.userId] != nil }
    /// Voting closes at the deadline or the moment the server settles it.
    private var isClosed: Bool { isExpired || finalEvent != nil }

    /// Who goes free: the server's answer once it has one, otherwise the
    /// provisional local leader(s) so the screen isn't blank for the up-to-
    /// a-minute wait on resolveExpiredVotes.
    private var freedUserIds: [String] {
        if let finalEvent { return finalEvent.freedUserIds }
        guard isExpired, let top = tally.values.max(), top > 0 else { return [] }
        return tally.filter { $0.value == top }.map(\.key)
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
                    // Only this label needs a per-second redraw; driving it
                    // from view state re-rendered every candidate card and
                    // avatar once a second too.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(voteEvent.endsAt.timeIntervalSince(context.date), 0)
                        Text(remaining.formattedTimer)
                            .font(Font.dhTimer)
                            .monospacedDigit()
                            .foregroundStyle(remaining < 300 ? .red : Color.cozyOrange)
                    }
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
                if isClosed {
                    resultView
                }
            }
        }
        // Wait out the deadline instead of asking "are we there yet?" sixty
        // times a minute. Fires immediately for an already-expired event.
        .task(id: voteEvent.id) {
            let delay = voteEvent.endsAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            isExpired = true
        }
        // The server is the authority: resolveExpiredVotes releases the
        // winner up to a minute after the deadline, and a partner letting
        // their dog out cancels the vote at any time. Either way the screen
        // shows the real outcome, not a guess from a stale tally.
        .task(id: voteEvent.id) {
            guard let settled = await voteService.awaitResult(voteId: voteEvent.id) else { return }
            finalEvent = settled
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
        let votes = tally[user.id] ?? 0
        let votedForThis = currentEvent.votes[voteService.userId] == user.id
        let total = totalVotes
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

                if !isClosed && !hasVoted {
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

    private var freedUsers: [UserProfile] {
        doghousedUsers.filter { freedUserIds.contains($0.id) }
    }

    private func name(of userId: String) -> String {
        doghousedUsers.first { $0.id == userId }?.displayName
            ?? currentEvent.doghousedUserNames?[userId]
            ?? "A dog"
    }

    private var resultView: some View {
        VStack(spacing: 12) {
            if let finalEvent, finalEvent.isCancelled {
                Text("🏠 VOTE CALLED OFF")
                    .font(.dhSubtitle)
                    .foregroundStyle(Color.cozyOrange)
                Text(finalEvent.releasedUserId.map { "\(name(of: $0)) got let out early." }
                     ?? "One of the dogs got let out early.")
                    .font(.headline)
            } else if !freedUsers.isEmpty {
                Text("🎵 WHO LET THE DOGS OUT 🎵")
                    .font(.dhSubtitle)
                    .foregroundStyle(Color.cozyOrange)
                HStack(spacing: 16) {
                    ForEach(freedUsers) { winner in
                        AvatarView(
                            avatar: DogAvatar.avatar(for: winner.avatarId ?? "dog_1"),
                            mood: .happy,
                            size: 80
                        )
                    }
                }
                Text(freedUsers.count == 1
                     ? "\(freedUsers[0].displayName) is FREE!"
                     : "\(freedUsers.map(\.displayName).joined(separator: " & ")) are FREE! It's a tie!")
                    .font(.headline)
                    .foregroundStyle(Color.freedomGreen)
                if finalEvent == nil {
                    Text("Counting the votes…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("🗳️ VOTING HAS ENDED")
                    .font(.dhSubtitle)
                    .foregroundStyle(Color.cozyOrange)
                Text(finalEvent == nil
                     ? "Counting the votes…"
                     : "Nobody goes free this time 😬")
                    .font(.headline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .onChange(of: freedUsers.isEmpty, initial: true) { _, isEmpty in
            guard !isEmpty, !showConfetti else { return }
            withAnimation { showConfetti = true }
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
