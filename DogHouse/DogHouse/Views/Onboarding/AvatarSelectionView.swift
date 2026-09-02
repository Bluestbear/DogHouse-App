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

    // The dial always has a dog centered, so start on the first one.
    @State private var selectedId: String = DogAvatar.allAvatars[0].id
    @State private var confirmScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Your Dog")
                        .font(.dhTitle)
                    Text("Turn the wheel to meet them all")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                Spacer(minLength: 0)

                AvatarDialView(selectedId: $selectedId)
                    .scaleEffect(confirmScale)

                Spacer(minLength: 0)

                // Confirm button
                Button {
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
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Step 3 of 4")
            .navigationBarTitleDisplayMode(.inline)
            // The wheel draws nothing behind the dogs, so this shows through:
            // a warm wash with the faint rim of the wheel the dogs ride on.
            .background(WheelBackdrop().ignoresSafeArea())
        }
    }
}

/// Soft gradient plus a ghosted arc suggesting the wheel's rim.
private struct WheelBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.cozyOrange.opacity(0.22), Color(.systemBackground), Color.dogHouseBrown.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { geo in
                // A big circle whose top sits where the chosen dog does.
                let radius = geo.size.width * 0.95
                Circle()
                    .strokeBorder(
                        Color.dogHouseBrown.opacity(0.12),
                        style: StrokeStyle(lineWidth: 26, dash: [6, 14])
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.56 + radius)
            }
        }
    }
}

#Preview {
    AvatarSelectionView()
        .environmentObject(AuthService())
}
