//
//  TasksSheetView.swift
//  DogHouse
//
//  Shows the couple's agreed-upon tasks, or prompts the user to propose
//  tasks if none have been set up yet. When proposing, the full task
//  negotiation flow (submit → review → confirm) is presented inline.
//

import SwiftUI
import FirebaseFirestore
import OSLog

struct TasksSheetView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var coupleTasks: [CoupleTask] = []
    @State private var isLoading = true
    @State private var showNegotiation = false

    private let fs = FirebaseService.shared

    private var coupleKey: String? {
        guard let userId = authService.userProfile?.id,
              let partnerId = authService.userProfile?.partnerId,
              partnerId != "skipped" else { return nil }
        return fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if showNegotiation {
                    negotiationView
                } else if coupleTasks.isEmpty {
                    noTasksView
                } else {
                    taskListView
                }
            }
            .navigationTitle("Your Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadTasks() }
    }

    // MARK: - Task List (tasks already defined)

    @ViewBuilder
    private var taskListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.cozyOrange)

                    Text("DogHouse Tasks")
                        .font(.dhTitle)

                    Text("These tasks can be assigned when someone is in the DogHouse.")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)

                VStack(spacing: 8) {
                    ForEach(coupleTasks) { task in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(task.isAppSuggestion ? Color.cozyOrange : Color.dogHouseBrown)
                                .frame(width: 8, height: 8)

                            Text(task.title)
                                .font(.dhBody)

                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - No Tasks (propose tasks)

    @ViewBuilder
    private var noTasksView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "list.clipboard")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("No Tasks Yet")
                .font(.dhTitle)

            Text("You and your partner haven't set up DogHouse tasks yet. Propose tasks that your partner can do to earn their freedom!")
                .font(.dhBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showNegotiation = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Propose Tasks")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cozyOrange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Negotiation Flow (reuses onboarding views)

    @ViewBuilder
    private var negotiationView: some View {
        if let userId = authService.userProfile?.id,
           let partnerId = authService.userProfile?.partnerId,
           partnerId != "skipped" {
            TaskNegotiationFlowView(userId: userId, partnerId: partnerId)
        } else {
            Text("Unable to start task negotiation.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Load Tasks

    private func loadTasks() async {
        guard let key = coupleKey else {
            isLoading = false
            return
        }

        do {
            let doc = try await fs.coupleTasksCollection.document(key).getDocument()
            if doc.exists, let data = doc.data(),
               let tasksArray = data["tasks"] as? [[String: Any]] {
                coupleTasks = tasksArray.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let title = dict["title"] as? String,
                          let suggestedBy = dict["suggestedBy"] as? String,
                          let isApp = dict["isAppSuggestion"] as? Bool else { return nil }
                    return CoupleTask(id: id, title: title, suggestedBy: suggestedBy, isAppSuggestion: isApp)
                }
            }
        } catch {
            Logger.data.error("Couple task load failed: \(error.localizedDescription, privacy: .public)")
        }

        isLoading = false
    }
}

// MARK: - Task Negotiation Flow (embedded in sheet)

/// Wraps the onboarding task views for use outside onboarding.
private struct TaskNegotiationFlowView: View {
    let userId: String
    let partnerId: String
    @StateObject private var onboardingService: OnboardingService

    init(userId: String, partnerId: String) {
        self.userId = userId
        self.partnerId = partnerId
        _onboardingService = StateObject(wrappedValue:
            OnboardingService(userId: userId, partnerId: partnerId)
        )
    }

    var body: some View {
        Group {
            switch onboardingService.taskDocument?.currentPhase ?? .submission {
            case .submission:
                TaskSubmissionView()
            case .review:
                TaskReviewView()
            case .confirmation, .complete:
                TaskConfirmationView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingService.taskDocument?.currentPhase)
        .environmentObject(onboardingService)
    }
}

#Preview {
    TasksSheetView()
        .environmentObject(AuthService())
}
