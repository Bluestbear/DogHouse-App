//
//  ProfileLoadingView.swift
//  DogHouse
//
//  Shown while the account is signed in but its profile document has not
//  arrived yet — first launch after a reinstall, a slow connection, or a
//  profile being recreated after an interrupted sign-up.
//
//  Before this existed, that window fell through to the pairing screen with a
//  blank "------" code, which looked like a broken account. Firestore keeps
//  retrying on its own, so this screen mostly just needs to be honest about
//  what is happening and offer a way out if it never resolves.
//

import SwiftUI

struct ProfileLoadingView: View {
    @EnvironmentObject var authService: AuthService
    @State private var isTakingLong = false

    var body: some View {
        ZStack {
            Color.cozyOrange.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("🐕")
                    .font(.system(size: 60))
                    .accessibilityHidden(true)

                ProgressView()
                    .tint(Color.dogHouseBrown)

                Text("Fetching your DogHouse…")
                    .font(.dhBody)
                    .foregroundStyle(.secondary)

                if isTakingLong {
                    VStack(spacing: 12) {
                        Text("This is taking longer than usual. Check your connection — we'll keep trying in the background.")
                            .font(.dhCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button("Sign out") {
                            authService.signOut()
                        }
                        .font(.dhCaptionBold)
                        .foregroundStyle(Color.dogHouseBrown)
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut, value: isTakingLong)
        .task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            isTakingLong = true
        }
    }
}

#Preview {
    ProfileLoadingView()
        .environmentObject(AuthService())
}
