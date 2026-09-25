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

    @State private var showAddCouple = false
    @State private var openVote: VoteEvent?
    @State private var coupleToRemove: FriendCouple?
    @State private var coupleToBlock: FriendCouple?
    @ObservedObject private var moderation = ModerationService.shared

    /// The week's sendings minus anything from someone I've blocked. The
    /// leaderboard ranks time served, so it needs the finished ones too.
    private var weekPosts: [FeedPost] {
        feedService.posts.filter { !moderation.isHidden($0) }
    }

    /// Feed cards: only dogs still in the DogHouse. A release flips the
    /// post's status server-side (releasePartner, or a won jailbreak vote),
    /// and the listener drops the card live.
    private var visiblePosts: [FeedPost] {
        weekPosts.filter(\.isActive)
    }

    var body: some View {
        NavigationStack {
            List {
                header

                // Jailbreak votes — two dogs from friended couples in at once
                ForEach(voteService.activeJointVotes) { vote in
                    JointVoteBanner(vote: vote) { openVote = vote }
                }

                // My couple's public sendings, then friends'
                if !ownPosts.isEmpty {
                    postsSection("Your Sends", posts: ownPosts)
                }
                if !friendPosts.isEmpty {
                    postsSection("Feed 📣", posts: friendPosts)
                }

                // Top Dog — most time served among friends this week
                if weekPosts.count > 1 {
                    Section {
                        TopDogLeaderboard(posts: weekPosts)
                    } header: {
                        Text("Top Dog 🏆 (this week)")
                    }
                }

                // Friend couples
                couplesSection
            }
            .navigationTitle("Friends")
            .dhPageBackground()
            // The title is drawn in the List (see `header`) so the add button
            // can sit on the same line; the title here only names the back
            // button on pushed screens.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddCouple) {
                AddCoupleSheet(friendService: friendService)
                    .environmentObject(authService)
            }
            .navigationDestination(isPresented: Binding(
                get: { openVote != nil },
                set: { if !$0 { openVote = nil } }
            )) {
                if let openVote {
                    JointVoteLoaderView(
                        vote: openVote,
                        voteService: voteService,
                        friendService: friendService
                    )
                    // Friends hides its bar; the vote screen needs the back button.
                    .toolbar(.visible, for: .navigationBar)
                }
            }
            // AuthService is the live source of the pairing; FriendService used to
            // resolve it once at construction and could never recover if it was
            // unavailable at that instant.
            .task(id: authService.userProfile?.partnerId) {
                friendService.configure(partnerId: authService.userProfile?.partnerId)
            }
            .task(id: authService.userProfile?.id) {
                moderation.configure(userId: authService.userProfile?.id)
                feedService.configure(userId: authService.userProfile?.id)
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
        }
    }

    // MARK: - Header

    /// Large title and add button on one line. A toolbar item can only sit
    /// in the bar above a large title, never beside it.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Friends")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showAddCouple = true
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.cozyOrange))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a Couple")
            .tourAnchor(.addCouple)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Feed Section

    /// Sendings I made or was sent by, kept apart from friends' posts
    private var ownPosts: [FeedPost] {
        visiblePosts.filter { $0.involves(feedService.userId) }
    }

    private var friendPosts: [FeedPost] {
        visiblePosts.filter { !$0.involves(feedService.userId) }
    }

    private func postsSection(_ title: String, posts: [FeedPost]) -> some View {
        Section {
            ForEach(posts) { post in
                FeedPostCard(post: post, feedService: feedService)
            }
        } header: {
            Text(title)
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
                    actionTitle: "Add a Couple"
                ) {
                    showAddCouple = true
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

// MARK: - Add a Couple

/// Opened from the toolbar's add button: my code to share, and a field for
/// theirs.
struct AddCoupleSheet: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var friendService: FriendService
    @Environment(\.dismiss) private var dismiss

    @State private var coupleCode = ""
    @State private var isAdding = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if let code = authService.partnerCode {
                    myCodeCard(code)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Their code")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField("6-character code", text: $coupleCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.title3, design: .monospaced).bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onSubmit(add)

                        Button(action: add) {
                            Group {
                                if isAdding {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Add").bold()
                                }
                            }
                            .frame(width: 64, height: 46)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Color.cozyOrange.opacity(coupleCode.count == 6 ? 1 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(coupleCode.count != 6 || isAdding)
                    }

                    if let errorText {
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

                Text("Friends are couple-to-couple: either partner's code works, and connecting links all four of you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pageGradient.ignoresSafeArea())
            .navigationTitle("Add a Couple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func myCodeCard(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Partner Code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(code)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Color.collarBrown)
                    .textSelection(.enabled)
                Spacer()
                ShareLink(
                    item: "Add us on DogHouse! Our couple code is \(code)",
                    subject: Text("DogHouse couple code")
                ) {
                    Text("Share")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.cozyOrange))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func add() {
        guard coupleCode.count == 6, !isAdding else { return }
        isAdding = true
        errorText = nil
        Task {
            defer { isAdding = false }
            do {
                try await friendService.addCouple(code: coupleCode)
                coupleCode = ""
                HapticService.shared.success()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
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
