//
//  TaskSubmissionView.swift
//  DogHouse
//
//  Step 5A: Each partner submits 4 tasks for their partner to do
//  when in the doghouse. Waits for both to submit before advancing.
//

import SwiftUI

struct TaskSubmissionView: View {
    @EnvironmentObject var onboardingService: OnboardingService
    @EnvironmentObject var authService: AuthService

    @State private var task1 = ""
    @State private var task2 = ""
    @State private var task3 = ""
    @State private var task4 = ""
    @State private var showError = false
    @State private var errorText = ""

    private var allFilled: Bool {
        !task1.trimmed.isEmpty && !task2.trimmed.isEmpty &&
        !task3.trimmed.isEmpty && !task4.trimmed.isEmpty
    }

    private var partnerName: String {
        authService.partnerProfile?.displayName ?? "Partner"
    }

    var body: some View {
        let iSubmitted = onboardingService.taskDocument?.iSubmitted(userId: onboardingService.userId) ?? false
        let partnerSubmitted = onboardingService.taskDocument?.partnerSubmitted(userId: onboardingService.userId) ?? false

        ScrollView {
            VStack(spacing: 24) {
                // Driven purely by the document, never by a local "I tapped it"
                // flag. Firestore echoes a write to the local cache immediately,
                // so this flips without waiting for the server — and if the write
                // is ultimately rejected, the rollback brings the form back
                // instead of stranding the user on a spinner forever.
                if iSubmitted {
                    // Submitted — waiting for partner
                    submittedView(partnerSubmitted: partnerSubmitted)
                } else {
                    // Not yet submitted — show form
                    formView
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Form View

    @ViewBuilder
    private var formView: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.cozyOrange)

            Text("Set the Rules")
                .font(.dhTitle)

            Text("Suggest 4 tasks that \(partnerName) can do to earn their freedom when you send them to the DogHouse.")
                .font(.dhBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }

        VStack(spacing: 16) {
            taskField(number: 1, text: $task1, placeholder: "e.g., Do the dishes")
            taskField(number: 2, text: $task2, placeholder: "e.g., Cook dinner")
            taskField(number: 3, text: $task3, placeholder: "e.g., Give a back massage")
            taskField(number: 4, text: $task4, placeholder: "e.g., Write a love letter")
        }
        .padding(.horizontal, 24)

        Button {
            Task { await submit() }
        } label: {
            Group {
                if onboardingService.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Submit Tasks")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(allFilled ? Color.cozyOrange : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!allFilled || onboardingService.isLoading)
        .padding(.horizontal, 24)

        if showError {
            Text(errorText)
                .font(.dhCaption)
                .foregroundStyle(.red)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func taskField(number: Int, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Task \(number)")
                .font(.dhCaptionBold)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Submitted View

    @ViewBuilder
    private func submittedView(partnerSubmitted: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.freedomGreen)

            Text("Tasks Submitted!")
                .font(.dhTitle)

            if !partnerSubmitted {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.cozyOrange)
                    Text("Waiting for \(partnerName) to submit their tasks...")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            }
        }

        // Show submitted tasks
        if let doc = onboardingService.taskDocument {
            let myTasks = doc.myTasks(userId: onboardingService.userId)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your tasks for \(partnerName):")
                    .font(.dhCaptionBold)
                    .foregroundStyle(.secondary)

                ForEach(myTasks) { task in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.freedomGreen)
                            .font(.system(size: 16))
                        Text(task.title)
                            .font(.dhBody)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Submit

    private func submit() async {
        showError = false
        let tasks = [
            OnboardingTask(id: UUID().uuidString, title: task1.trimmed),
            OnboardingTask(id: UUID().uuidString, title: task2.trimmed),
            OnboardingTask(id: UUID().uuidString, title: task3.trimmed),
            OnboardingTask(id: UUID().uuidString, title: task4.trimmed),
        ]
        do {
            try await onboardingService.submitMyTasks(tasks)
            HapticService.shared.success()
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }
}

#Preview {
    TaskSubmissionView()
        .environmentObject(OnboardingService(userId: "u1", partnerId: "u2"))
        .environmentObject(AuthService())
}
