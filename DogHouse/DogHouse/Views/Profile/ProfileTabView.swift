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
            let history = doghouseService.doghouseHistory

            StatRow(label: "Times in the DogHouse", value: "\(history.filter { $0.receiverId == myUserId }.count)", icon: "house.fill", color: .red)
            StatRow(label: "Times you sent them", value: "\(history.filter { $0.senderId == myUserId }.count)", icon: "arrow.right.circle.fill", color: Color.cozyOrange)
            StatRow(label: "Current streak outside", value: doghouseService.timeSinceMyLastRelease().formattedDuration, icon: "flame.fill", color: Color.freedomGreen)
            StatRow(label: "Times saved by squad", value: "0", icon: "person.3.fill", color: Color.dogHouseBlue)
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
            Button(role: .destructive) {
                showSignOutAlert = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
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
