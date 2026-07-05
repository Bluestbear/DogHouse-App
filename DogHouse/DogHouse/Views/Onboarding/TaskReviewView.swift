//
//  TaskReviewView.swift
//  DogHouse
//
//  Step 5B: Review the tasks your partner suggested for YOU.
//  You can strike up to 4 (all of them). Struck tasks are replaced
//  with app-suggested alternatives.
//

import SwiftUI

struct TaskReviewView: View {
    @EnvironmentObject var onboardingService: OnboardingService
    @EnvironmentObject var authService: AuthService

    @State private var strikes: [String: String] = [:]  // taskId → replacement title
    @State private var hasReviewed = false
    @State private var showError = false
    @State private var errorText = ""

    private var partnerName: String {
        authService.partnerProfile?.displayName ?? "Partner"
    }

    private var tasksForMe: [OnboardingTask] {
        onboardingService.taskDocument?.partnerTasks(userId: onboardingService.userId) ?? []
    }

    private var maxStrikes: Int { 4 }

    private var usedReplacements: Set<String> {
        Set(strikes.values)
    }

    var body: some View {
        let myReviewDone = onboardingService.taskDocument?.myReviewComplete(userId: onboardingService.userId) ?? false
        let partnerReviewDone = onboardingService.taskDocument?.partnerReviewComplete(userId: onboardingService.userId) ?? false

        ScrollView {
            VStack(spacing: 24) {
                if myReviewDone || hasReviewed {
                    waitingView(partnerReviewDone: partnerReviewDone)
                } else {
                    reviewFormView
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Review Form

    @ViewBuilder
    private var reviewFormView: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.cozyOrange)

            Text("Review \(partnerName)'s Tasks")
                .font(.dhTitle)

            Text("These are the tasks \(partnerName) wants you to do when you're in the DogHouse. Don't like one? Strike it out!")
                .font(.dhBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }

        // Strike counter
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text("Strikes used: \(strikes.count) of \(maxStrikes)")
                .font(.dhCaptionBold)
            Spacer()
        }
        .padding(.horizontal, 24)

        // Task cards
        VStack(spacing: 12) {
            ForEach(tasksForMe) { task in
                taskCard(task: task)
            }
        }
        .padding(.horizontal, 24)

        // Confirm review button
        Button {
            Task { await submitReview() }
        } label: {
            Group {
                if onboardingService.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Accept Tasks")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.freedomGreen)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(onboardingService.isLoading)
        .padding(.horizontal, 24)

        if showError {
            Text(errorText)
                .font(.dhCaption)
                .foregroundStyle(.red)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Task Card

    @ViewBuilder
    private func taskCard(task: OnboardingTask) -> some View {
        let isStruck = strikes[task.id] != nil

        VStack(alignment: .leading, spacing: 8) {
            // Original task
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.dhBody)
                        .strikethrough(isStruck, color: .red)
                        .foregroundStyle(isStruck ? .secondary : .primary)
                }

                Spacer()

                if !isStruck {
                    Button {
                        strikeTask(task)
                    } label: {
                        Label("Strike", systemImage: "xmark.circle.fill")
                            .font(.dhCaptionBold)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            // Replacement (if struck)
            if isStruck, let replacement = strikes[task.id] {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.cozyOrange)
                    Text(replacement)
                        .font(.dhBody)
                        .foregroundStyle(Color.cozyOrange)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.spring(duration: 0.3), value: isStruck)
    }

    // MARK: - Strike Logic

    private func strikeTask(_ task: OnboardingTask) {
        guard strikes.count < maxStrikes else { return }

        // Get all existing titles to exclude from suggestions
        let existingTitles = Set(tasksForMe.map { $0.title })
            .union(usedReplacements)

        let replacement = AppSuggestedTasks.randomSuggestion(excluding: existingTitles)
        withAnimation {
            strikes[task.id] = replacement
        }
        HapticService.shared.rigidImpact()
    }

    // MARK: - Waiting View

    @ViewBuilder
    private func waitingView(partnerReviewDone: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.freedomGreen)

            Text("Review Complete!")
                .font(.dhTitle)

            if !partnerReviewDone {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.cozyOrange)
                    Text("Waiting for \(partnerName) to finish their review...")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Submit

    private func submitReview() async {
        showError = false
        let strikeList = strikes.map { TaskStrike(originalTaskId: $0.key, replacementTitle: $0.value) }
        do {
            try await onboardingService.submitReview(strikes: strikeList)
            hasReviewed = true
            HapticService.shared.success()
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    TaskReviewView()
        .environmentObject(OnboardingService(userId: "u1", partnerId: "u2"))
        .environmentObject(AuthService())
}
