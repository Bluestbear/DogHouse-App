//
//  FriendsTabView.swift
//  DogHouse
//
//  Couples add other couples by code. The feed shows friended couples'
//  public sendings; jailbreak votes span all connected couples.
//

import SwiftUI

struct FriendsTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var friendService = FriendService(userId: "mock_user")
    @StateObject private var voteService = VoteService(userId: "mock_user")
    @StateObject private var feedService = FeedService(userId: "mock_user")

    @State private var coupleCode = ""
    @State private var isAdding = false
    @State private var showError = false
    @State private var errorText = ""
    @State private var coupleToRemove: FriendCouple?
    @State private var coupleToBlock: FriendCouple?
    @ObservedObject private var tour = TourCoordinator.shared
    @ObservedObject private var moderation = ModerationService.shared

    /// The feed minus anything from someone I've blocked.
    private var visiblePosts: [FeedPost] {
        feedService.posts.filter { !moderation.isHidden($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                // Jailbreak votes — two dogs from friended couples in at once
                ForEach(voteService.activeJointVotes) { vote in
                    JointVoteBanner(
                        vote: vote,
                        voteService: voteService,
                        friendService: friendService
                    )
                }

                // Friends feed — public sendings
                if !visiblePosts.isEmpty {
                    feedSection
                }

                // Top Dog — most time served among friends this week
                if visiblePosts.count > 1 {
                    Section {
                        TopDogLeaderboard(posts: visiblePosts)
                    } header: {
                        Text("Top Dog 🏆 (this week)")
                    }
                }

                // Add a couple
                addCoupleSection

                // Friend couples
                couplesSection
            }
            .navigationTitle("Friends")
            .dhPageBackground()
            // AuthService is the live source of the pairing; FriendService used to
            // resolve it once at construction and could never recover if it was
            // unavailable at that instant.
            .task(id: authService.userProfile?.partnerId) {
                friendService.configure(partnerId: authService.userProfile?.partnerId)
            }
            .task(id: authService.userProfile?.id) {
                moderation.configure(userId: authService.userProfile?.id)
            }
            .alert("Block this couple?", isPresented: .init(
                get: { coupleToBlock != nil },
                set: { if !$0 { coupleToBlock = nil } }
            )) {
                Button("Block", role: .destructive) {
                    guard let couple = coupleToBlock else { return }
                    coupleToBlock = nil
                    Task {
                        for member in couple.members {
                            try? await moderation.block(userId: member.id)
                        }
                        await friendService.refresh()
                    }
                }
                Button("Cancel", role: .cancel) { coupleToBlock = nil }
            } message: {
                Text("Both of them are blocked and the friendship is removed. They aren't told, and they can't re-add you.")
            }
            .alert("Remove this couple?", isPresented: .init(
                get: { coupleToRemove != nil },
                set: { if !$0 { coupleToRemove = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    guard let couple = coupleToRemove else { return }
                    coupleToRemove = nil
                    Task { try? await friendService.removeCouple(couple) }
                }
                Button("Cancel", role: .cancel) { coupleToRemove = nil }
            } message: {
                Text("You'll stop seeing each other's public sendings.")
            }
            // The feed can push "Add a Couple" below the fold; the tour
            // points at it, so bring it up when that step arrives.
            // `initial: true` matters: this tab is created lazily when the tour
            // switches to it, so by the time it exists the step has already
            // changed and a plain onChange would never fire. The short delay
            // lets the List lay out its rows before scrolling to one.
            .onChange(of: tour.currentStep, initial: true) { _, step in
                guard step == .friends else { return }
                // No scroll animation: the overlay is dimmed and the
                // spotlight fades in once the row has settled, so a visible
                // glide (with the ring chasing it) only added motion. One
                // scroll, after the List has laid out — scrolling earlier
                // lands on an estimate and the row then hops again. The
                // second call is a safety net for a slow first layout; it is
                // a no-op when the row is already in place.
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    proxy.scrollTo("tour-add-couple", anchor: .center)
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo("tour-add-couple", anchor: .center)
                }
            }
            } // ScrollViewReader
        }
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        Section {
            ForEach(visiblePosts) { post in
                FeedPostCard(
                    post: post,
                    feedService: feedService,
                    activeVoteIds: Set(voteService.activeVoteEvents.map(\.id))
                )
            }
        } header: {
            Text("The Feed 📣")
        }
    }

    // MARK: - Add a Couple

    private var addCoupleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Enter a couple's code", text: $coupleCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") {
                            isAdding = true
                            showError = false
                            Task {
                                defer { isAdding = false }
                                do {
                                    try await friendService.addCouple(code: coupleCode)
                                    coupleCode = ""
                                    HapticService.shared.success()
                                } catch {
                                    errorText = error.localizedDescription
                                    showError = true
                                }
                            }
                        }
                        .disabled(coupleCode.count != 6)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.cozyOrange)
                    }
                }

                if let code = authService.partnerCode {
                    Text("Your couple's code: **\(code)** (either partner's code works)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showError {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // A link that was created but can't be displayed used to be
                // silent — the add appeared to work and the list stayed empty.
                if let loadError = friendService.loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .tourAnchor(.addCouple)
            .id("tour-add-couple")
        } header: {
            Text("Add a Couple")
        } footer: {
            Text("Friends are couple-to-couple: connecting links all four of you.")
        }
    }

    // MARK: - Couples List

    private var couplesSection: some View {
        Section {
            if friendService.friendCouples.isEmpty {
                EmptyStateView(
                    icon: "person.2.slash",
                    title: "No Couples Yet",
                    subtitle: "Share your code with another couple to connect!",
                    actionTitle: "Copy Code"
                ) {
                    if let code = authService.partnerCode {
                        UIPasteboard.general.string = code
                        HapticService.shared.success()
                    }
                }
            } else {
                ForEach(friendService.friendCouples) { couple in
                    CoupleRow(couple: couple)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                coupleToRemove = couple
                            } label: {
                                Label("Remove", systemImage: "person.2.slash")
                            }
                            Button {
                                coupleToBlock = couple
                            } label: {
                                Label("Block", systemImage: "hand.raised.fill")
                            }
                            .tint(.orange)
                        }
                }
            }
        } header: {
            Text("Friend Couples")
        }
    }
}

// MARK: - Couple Row

struct CoupleRow: View {
    var couple: FriendCouple

    var body: some View {
        HStack(spacing: 12) {
            // Both partners' avatars, slightly overlapping
            HStack(spacing: -14) {
                ForEach(couple.members) { member in
                    AvatarView(
                        avatar: DogAvatar.avatar(for: member.avatarId ?? "dog_1"),
                        mood: .happy,
                        size: 42,
                        blinks: false
                    )
                    .background(Circle().fill(Color(.systemBackground)).frame(width: 46, height: 46))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(couple.displayName)
                    .font(.subheadline.bold())
                Text("Friend couple")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FriendsTabView()
        .environmentObject(AuthService())
}
