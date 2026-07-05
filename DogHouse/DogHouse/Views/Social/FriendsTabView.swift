//
//  FriendsTabView.swift
//  DogHouse
//

import SwiftUI

struct FriendsTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var friendService = FriendService(userId: "mock_user")
    @StateObject private var voteService = VoteService(userId: "mock_user")
    @StateObject private var feedService = FeedService(userId: "mock_user")

    @State private var friendCode = ""
    @State private var showCreateGroup = false
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            List {
                // Jailbreak votes — two friends in the doghouse at once
                ForEach(voteService.activeJointVotes) { vote in
                    JointVoteBanner(
                        vote: vote,
                        voteService: voteService,
                        friendService: friendService
                    )
                }

                // Friends feed — public sendings
                if !feedService.posts.isEmpty {
                    feedSection
                }

                // Add a Friend
                addFriendSection

                // Pending Requests
                if !friendService.pendingRequests.isEmpty {
                    pendingSection
                }

                // Friends list
                friendsSection

                // Groups
                groupsSection
            }
            .navigationTitle("Friends")
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet(friendService: friendService)
            }
            .onChange(of: friendService.groups, initial: true) { _, newGroups in
                voteService.listenForVotes(inGroupIds: newGroups.map { $0.id })
            }
        }
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        Section {
            ForEach(feedService.posts) { post in
                FeedPostCard(post: post, feedService: feedService)
            }
        } header: {
            Text("The Feed 📣")
        }
    }

    // MARK: - Add Friend Section

    private var addFriendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Enter friend code", text: $friendCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    Button("Add") {
                        Task {
                            do {
                                try await friendService.sendFriendRequest(toCode: friendCode)
                                friendCode = ""
                            } catch {
                                errorText = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                    .disabled(friendCode.count != 6)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cozyOrange)
                }

                if let code = authService.userProfile?.partnerCode {
                    Text("Your code: **\(code)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showError {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Add a Friend")
        }
    }

    // MARK: - Pending Requests

    private var pendingSection: some View {
        Section {
            ForEach(friendService.pendingRequests) { request in
                HStack {
                    AvatarView(
                        avatar: DogAvatar.avatar(for: "dog_2"),
                        mood: .happy,
                        size: 40
                    )

                    VStack(alignment: .leading) {
                        Text("Friend Request")
                            .font(.subheadline.bold())
                        Text("From: \(request.fromUserId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { try? await friendService.acceptFriendRequest(friendshipId: request.id) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.freedomGreen)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { try? await friendService.rejectFriendRequest(friendshipId: request.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Friend Requests (\(friendService.pendingRequests.count))")
        }
    }

    // MARK: - Friends List

    private var friendsSection: some View {
        Section {
            if friendService.friends.isEmpty {
                EmptyStateView(
                    icon: "person.2.slash",
                    title: "No Friends Yet",
                    subtitle: "Share your partner code above to connect with friends!",
                    actionTitle: "Copy Code"
                ) {
                    if let code = authService.userProfile?.partnerCode {
                        UIPasteboard.general.string = code
                        HapticService.shared.success()
                    }
                }
            } else {
                ForEach(friendService.friends) { friend in
                    FriendRow(friend: friend)
                }
            }
        } header: {
            Text("Your Friends")
        }
    }

    // MARK: - Groups

    private var groupsSection: some View {
        Section {
            if friendService.groups.isEmpty {
                EmptyStateView(
                    icon: "person.3",
                    title: "No Groups Yet",
                    subtitle: "Create a group to unlock\nWho Let The Dogs Out voting!"
                )
            } else {
                ForEach(friendService.groups) { group in
                    NavigationLink {
                        GroupDetailView(
                            group: group,
                            friendService: friendService,
                            voteService: voteService
                        )
                    } label: {
                        GroupRow(
                            group: group,
                            hasActiveVote: voteService.activeVoteEvent(forGroupId: group.id) != nil
                        )
                    }
                }
            }

            Button {
                showCreateGroup = true
            } label: {
                Label("Create Group", systemImage: "plus.circle.fill")
            }
            .tint(Color.cozyOrange)
        } header: {
            Text("Groups")
        }
    }
}

// MARK: - Friend Row

struct FriendRow: View {
    var friend: UserProfile

    // Mock: randomly assign doghouse status for demo
    private var isInDoghouse: Bool { false }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                avatar: DogAvatar.avatar(for: friend.avatarId ?? "dog_1"),
                mood: isInDoghouse ? .sad : .happy,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.subheadline.bold())

                HStack(spacing: 4) {
                    Circle()
                        .fill(isInDoghouse ? Color.red : Color.freedomGreen)
                        .frame(width: 8, height: 8)
                    Text(isInDoghouse ? "In the DogHouse" : "Home")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Group Row

struct GroupRow: View {
    var group: FriendGroup
    var hasActiveVote: Bool = false

    var body: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundStyle(Color.dogHouseBrown)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline.bold())
                Text("\(group.memberIds.count) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hasActiveVote {
                Label("Voting", systemImage: "hand.raised.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cozyOrange)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Group Detail View

struct GroupDetailView: View {
    var group: FriendGroup
    @ObservedObject var friendService: FriendService
    @ObservedObject var voteService: VoteService

    @State private var memberProfiles: [UserProfile] = []
    @State private var isLoadingMembers = true
    @State private var showStartVote = false

    private var activeVote: VoteEvent? {
        voteService.activeVoteEvent(forGroupId: group.id)
    }

    var body: some View {
        List {
            Section("Members (\(group.memberIds.count))") {
                if isLoadingMembers {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(memberProfiles) { profile in
                        HStack(spacing: 12) {
                            AvatarView(
                                avatar: DogAvatar.avatar(for: profile.avatarId ?? "dog_1"),
                                mood: .happy,
                                size: 40
                            )
                            Text(profile.displayName)
                                .font(.subheadline.bold())
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Squad Vote") {
                if let vote = activeVote {
                    NavigationLink {
                        VoteEventView(
                            voteService: voteService,
                            voteEvent: vote,
                            doghousedUsers: memberProfiles.filter { vote.doghousedUserIds.contains($0.id) }
                        )
                    } label: {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(Color.cozyOrange)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vote in Progress")
                                    .font(.subheadline.bold())
                                Text("Tap to cast your vote")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(vote.endsAt, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Button {
                        showStartVote = true
                    } label: {
                        Label("Start a Vote", systemImage: "hand.raised")
                            .foregroundStyle(Color.cozyOrange)
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showStartVote) {
            StartVoteSheet(
                group: group,
                members: memberProfiles,
                voteService: voteService
            )
        }
        .task {
            memberProfiles = (try? await friendService.fetchProfiles(for: group.memberIds)) ?? []
            isLoadingMembers = false
        }
    }
}

// MARK: - Start Vote Sheet

struct StartVoteSheet: View {
    var group: FriendGroup
    var members: [UserProfile]
    @ObservedObject var voteService: VoteService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMemberIds: Set<String> = []
    @State private var durationMinutes = 30
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Select the group members currently in the DogHouse — the squad will vote to free one of them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Who's in the DogHouse?") {
                    ForEach(members) { member in
                        Button {
                            if selectedMemberIds.contains(member.id) {
                                selectedMemberIds.remove(member.id)
                            } else {
                                selectedMemberIds.insert(member.id)
                            }
                        } label: {
                            HStack {
                                AvatarView(
                                    avatar: DogAvatar.avatar(for: member.avatarId ?? "dog_1"),
                                    mood: selectedMemberIds.contains(member.id) ? .sad : .happy,
                                    size: 36
                                )
                                Text(member.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedMemberIds.contains(member.id) {
                                    Image(systemName: "house.fill")
                                        .foregroundStyle(Color.dogHouseBrown)
                                }
                            }
                        }
                    }
                }

                Section("Vote Duration") {
                    Picker("Duration", selection: $durationMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Start a Vote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Start") {
                            Task {
                                isCreating = true
                                try? await voteService.createVoteEvent(
                                    groupId: group.id,
                                    doghousedUserIds: Array(selectedMemberIds),
                                    durationMinutes: durationMinutes
                                )
                                isCreating = false
                                dismiss()
                            }
                        }
                        .disabled(selectedMemberIds.isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - Create Group Sheet

struct CreateGroupSheet: View {
    @ObservedObject var friendService: FriendService
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var selectedFriendIds: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g., The Squad", text: $groupName)
                }

                Section("Select Members") {
                    ForEach(friendService.friends) { friend in
                        Button {
                            if selectedFriendIds.contains(friend.id) {
                                selectedFriendIds.remove(friend.id)
                            } else {
                                selectedFriendIds.insert(friend.id)
                            }
                        } label: {
                            HStack {
                                AvatarView(
                                    avatar: DogAvatar.avatar(for: friend.avatarId ?? "dog_1"),
                                    mood: .happy,
                                    size: 36
                                )
                                Text(friend.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedFriendIds.contains(friend.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.freedomGreen)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            try? await friendService.createGroup(
                                name: groupName,
                                memberIds: Array(selectedFriendIds)
                            )
                            dismiss()
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || selectedFriendIds.isEmpty)
                }
            }
        }
    }
}

#Preview {
    FriendsTabView()
        .environmentObject(AuthService())
}
