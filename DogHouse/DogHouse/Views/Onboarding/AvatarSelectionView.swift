//
//  AvatarSelectionView.swift
//  DogHouse
//
//  Step 3: Mandatory avatar selection during onboarding.
//  Saves selection to Firestore, which triggers OnboardingContainerView to advance.
//

import SwiftUI

struct AvatarSelectionView: View {
    @EnvironmentObject var authService: AuthService

    @State private var selectedId: String? = nil
    @State private var confirmScale: CGFloat = 1.0

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Your Dog")
                        .font(.dhTitle)
                    Text("This is you in the DogHouse")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Selected preview
                if let selectedId, let avatar = DogAvatar.allAvatars.first(where: { $0.id == selectedId }) {
                    VStack(spacing: 8) {
                        AvatarView(avatar: avatar, mood: .happy, size: 120)
                            .scaleEffect(confirmScale)
                        Text(avatar.name)
                            .font(.dhBodyBold)
                            .foregroundStyle(Color.dogHouseBrown)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 120)
                            .overlay {
                                Image(systemName: "questionmark")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                        Text("Pick one!")
                            .font(.dhBodyBold)
                            .foregroundStyle(.secondary)
                    }
                }

                // Avatar grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DogAvatar.allAvatars) { avatar in
                        VStack(spacing: 4) {
                            AvatarView(avatar: avatar, mood: .happy, size: 60, blinks: false)
                                .overlay(
                                    Circle()
                                        .stroke(selectedId == avatar.id ? Color.cozyOrange : .clear, lineWidth: 3)
                                        .frame(width: 64, height: 64)
                                )
                                .scaleEffect(selectedId == avatar.id ? 1.1 : 1.0)

                            Text(avatar.name)
                                .font(.dhBadge)
                                .foregroundStyle(selectedId == avatar.id ? Color.cozyOrange : .secondary)
                        }
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedId = avatar.id
                            }
                            HapticService.shared.lightTap()
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Confirm button
                Button {
                    guard let selectedId else { return }
                    withAnimation(.spring(duration: 0.2)) {
                        confirmScale = 1.15
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(duration: 0.2)) {
                            confirmScale = 1.0
                        }
                    }
                    authService.updateAvatar(id: selectedId)
                    HapticService.shared.success()
                    // Snapshot listener picks up avatarId change
                    // → OnboardingContainerView auto-advances
                } label: {
                    Text("This is me!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedId != nil ? Color.cozyOrange : Color.gray.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedId == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Step 2 of 4")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AvatarSelectionView()
        .environmentObject(AuthService())
}
