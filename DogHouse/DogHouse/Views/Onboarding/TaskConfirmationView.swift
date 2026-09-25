//
//  TaskConfirmationView.swift
//  DogHouse
//
//  Step 5C: Both partners see the final 8-task list and confirm.
//  When both confirm, onboardingComplete is set and both transition to MainTabView.
//

import SwiftUI

struct TaskConfirmationView: View {
    @EnvironmentObject var onboardingService: OnboardingService
    @EnvironmentObject var authService: AuthService

    @State private var showError = false
    @State private var errorText = ""

    private var partnerName: String {
        authService.partnerProfile?.displayName ?? "Partner"
    }

    var body: some View {
        let iConfirmed = onboardingService.taskDocument?.iConfirmed(userId: onboardingService.userId) ?? false
        let partnerConfirmed = onboardingService.taskDocument?.partnerConfirmed(userId: onboardingService.userId) ?? false
        let finalTasks = onboardingService.taskDocument?.finalTasks ?? []

        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.freedomGreen)

                    Text("Your DogHouse Tasks")
                        .font(.dhTitle)

                    Text("Here's the final list. When one of you is in the DogHouse, doing a task the other asked for is a way to make it up.")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)

                // Task list
                VStack(spacing: 8) {
                    ForEach(finalTasks) { task in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(task.isAppSuggestion ? Color.cozyOrange : Color.dogHouseBrown)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.dhBody)

                                Text(task.isAppSuggestion ? "App suggestion" : "Suggested by \(displayName(for: task.suggestedBy))")
                                    .font(.dhCaption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 24)

                // Confirm button or waiting state
                // Document-driven, not local-flag-driven — see TaskSubmissionView.
                if iConfirmed {
                    if !partnerConfirmed {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(Color.cozyOrange)
                            Text("Waiting for \(partnerName) to confirm...")
                                .font(.dhBody)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "party.popper.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.cozyOrange)
                            Text("You're all set!")
                                .font(.dhTitle)
                        }
                        .padding(.top, 8)
                    }
                } else {
                    Button {
                        Task { await confirm() }
                    } label: {
                        Group {
                            if onboardingService.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Looks Good, Let's Go!")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(onboardingService.isLoading)
                    .padding(.horizontal, 24)
                }

                if showError {
                    Text(errorText)
                        .font(.dhCaption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 40)
        }
        // Keyed on emptiness rather than run-once, so a build that failed on the
        // first attempt (offline, say) is retried when the document next changes
        // instead of leaving both partners staring at an empty list. Building
        // twice is harmless: the array is a pure function of the document.
        .task(id: finalTasks.isEmpty) {
            guard finalTasks.isEmpty else { return }
            try? await onboardingService.buildFinalTaskListIfNeeded()
        }
    }

    private func displayName(for userId: String) -> String {
        if userId == authService.userProfile?.id {
            return authService.userProfile?.displayName ?? "You"
        } else {
            return authService.partnerProfile?.displayName ?? "Partner"
        }
    }

    private func confirm() async {
        showError = false
        do {
            try await onboardingService.confirmFinalList()
            HapticService.shared.success()
            SoundService.shared.playItemUnlock()
            // If both confirmed, finalizeOnboarding sets onboardingComplete = true
            // → RootView transitions to MainTabView
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    TaskConfirmationView()
        .environmentObject(OnboardingService(userId: "u1", partnerId: "u2"))
        .environmentObject(AuthService())
}
