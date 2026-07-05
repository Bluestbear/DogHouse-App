//
//  ProfileTabView.swift
//  DogHouse
//

import SwiftUI

struct ProfileTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var doghouseService = DoghouseService(userId: "mock_user", partnerId: "mock_partner")
    @State private var showAvatarPicker = false
    @State private var showSignOutAlert = false
    @State private var showDeleteAlert = false
    @State private var deleteConfirmationText = ""
    @State private var isDeleting = false
    @State private var showUnpairAlert = false
    @State private var showRepairSheet = false
    @State private var unpairError: String?
    @State private var soundEnabled = SoundService.shared.isEnabled
    @State private var hapticEnabled = HapticService.shared.isEnabled

    var body: some View {
        NavigationStack {
            List {
                // User card
                userCardSection

                // Stats
                statsSection

                // History
                historySection

                // Relationship
                relationshipSection

                // Settings
                settingsSection

                // Account actions
                accountSection
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView(currentAvatarId: authService.userProfile?.avatarId ?? "dog_1")
                    .environmentObject(authService)
            }
            .alert("Sign Out?", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    authService.signOut()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Unpair from Partner?", isPresented: $showUnpairAlert) {
                Button("Unpair", role: .destructive) {
                    Task {
                        do {
                            try await authService.unpairFromPartner()
                        } catch {
                            unpairError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will disconnect you from your partner. You can pair with someone new afterwards.")
            }
            .sheet(isPresented: $showRepairSheet) {
                PairingView()
                    .environmentObject(authService)
            }
            .errorBanner($unpairError)
        }
    }

    // MARK: - User Card

    private var userCardSection: some View {
        Section {
            VStack(spacing: 12) {
                AvatarView(
                    avatar: DogAvatar.avatar(for: authService.userProfile?.avatarId ?? "dog_1"),
                    mood: .happy,
                    size: 90
                )
                .onTapGesture { showAvatarPicker = true }

                Text(authService.userProfile?.displayName ?? "User")
                    .font(.title2.bold())

                if let code = authService.userProfile?.partnerCode {
                    HStack(spacing: 6) {
                        Text("Code:")
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .bold()

                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                    }
                    .font(.subheadline)
                }

                HStack(spacing: 16) {
                    Label("Paired", systemImage: authService.userProfile?.partnerId != nil ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundStyle(authService.userProfile?.partnerId != nil ? Color.cozyOrange : .secondary)

                    if let created = authService.userProfile?.createdAt {
                        Label("Since \(created.formatted(.dateTime.month().year()))", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Stats

    private var myUserId: String {
        authService.userProfile?.id ?? ""
    }

    private var statsSection: some View {
        Section("Stats") {
            let stats = DoghouseStats(
                history: doghouseService.doghouseHistory,
                userId: myUserId,
                accountCreatedAt: authService.userProfile?.createdAt
            )

            StatRow(label: "Times in the DogHouse", value: "\(stats.timesInDoghouse)", icon: "house.fill", color: .red)
            StatRow(label: "Times you sent them", value: "\(stats.timesSentPartner)", icon: "arrow.right.circle.fill", color: Color.cozyOrange)
            StatRow(label: "Current clean streak", value: stats.currentCleanStreak.formattedDuration, icon: "flame.fill", color: Color.freedomGreen)
            StatRow(label: "Longest clean streak", value: stats.longestCleanStreak.formattedDuration, icon: "trophy.fill", color: .yellow)
            if stats.timesInDoghouse > 0 {
                StatRow(label: "Total time served", value: stats.totalTimeServed.formattedDuration, icon: "hourglass", color: .secondary)
            }
            if stats.timesSavedByVote > 0 {
                StatRow(label: "Times saved by the people", value: "\(stats.timesSavedByVote)", icon: "person.3.fill", color: Color.dogHouseBlue)
            }
            if stats.timesRedeemed > 0 {
                StatRow(label: "Times redeemed", value: "\(stats.timesRedeemed)", icon: "checkmark.seal.fill", color: Color.freedomGreen)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section("DogHouse History") {
            if doghouseService.doghouseHistory.isEmpty {
                EmptyStateView(
                    icon: "checkmark.shield",
                    title: "Clean Record!",
                    subtitle: "No doghouse history yet. Keep it up!"
                )
            } else {
                ForEach(doghouseService.doghouseHistory) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: event.senderId == myUserId ? "arrow.right.circle" : "arrow.left.circle")
                                .foregroundStyle(event.senderId == myUserId ? Color.cozyOrange : .red)
                            Text(event.senderId == myUserId ? "You sent them" : "You were sent")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(event.startedAt.formatted(.dateTime.month().day()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(event.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let duration = event.endedAt?.timeIntervalSince(event.startedAt) {
                            Text("Duration: \(duration.formattedDuration)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section("Settings") {
            Toggle(isOn: $soundEnabled) {
                Label("Sound Effects", systemImage: "speaker.wave.2.fill")
            }
            .onChange(of: soundEnabled) { _, newValue in
                SoundService.shared.isEnabled = newValue
            }

            Toggle(isOn: $hapticEnabled) {
                Label("Haptic Feedback", systemImage: "hand.tap.fill")
            }
            .onChange(of: hapticEnabled) { _, newValue in
                HapticService.shared.isEnabled = newValue
            }

            Button {
                showAvatarPicker = true
            } label: {
                Label("Change Avatar", systemImage: "pawprint.fill")
            }
        }
    }

    // MARK: - Relationship

    private var relationshipSection: some View {
        Section("Relationship") {
            if let partner = authService.partnerProfile {
                HStack {
                    AvatarView(
                        avatar: DogAvatar.avatar(for: partner.avatarId ?? "dog_1"),
                        mood: .happy,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partner.displayName)
                            .font(.subheadline.bold())
                        Text("Paired")
                            .font(.caption)
                            .foregroundStyle(Color.freedomGreen)
                    }
                    Spacer()
                }

                Button(role: .destructive) {
                    showUnpairAlert = true
                } label: {
                    Label("Unpair", systemImage: "heart.slash")
                }
            } else if authService.userProfile?.partnerId == "skipped" {
                Button {
                    showRepairSheet = true
                } label: {
                    Label("Pair with Partner", systemImage: "heart.fill")
                        .foregroundStyle(Color.cozyOrange)
                }
            } else {
                Label("Not paired", systemImage: "heart")
                    .foregroundStyle(.secondary)

                Button {
                    showRepairSheet = true
                } label: {
                    Label("Pair with Partner", systemImage: "heart.fill")
                        .foregroundStyle(Color.cozyOrange)
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            Link(destination: URL(string: "https://doghouse-5e80e.web.app/privacy.html")!) {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }

            Button(role: .destructive) {
                showSignOutAlert = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Button(role: .destructive) {
                deleteConfirmationText = ""
                showDeleteAlert = true
            } label: {
                if isDeleting {
                    HStack {
                        ProgressView()
                        Text("Deleting account...")
                    }
                } else {
                    Label("Delete Account", systemImage: "trash.fill")
                }
            }
            .disabled(isDeleting)
            .alert("Delete your account?", isPresented: $showDeleteAlert) {
                TextField("Type DELETE to confirm", text: $deleteConfirmationText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("Delete Forever", role: .destructive) {
                    guard deleteConfirmationText == "DELETE" else { return }
                    isDeleting = true
                    Task {
                        do {
                            try await authService.deleteAccount()
                        } catch {
                            unpairError = error.localizedDescription
                            isDeleting = false
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases your profile, history, friendships, and feed posts, and unpairs your partner. It cannot be undone. Type DELETE to confirm.")
            }
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    var label: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ProfileTabView()
        .environmentObject(AuthService())
}
