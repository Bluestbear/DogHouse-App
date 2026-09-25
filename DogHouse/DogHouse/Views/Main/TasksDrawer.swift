//
//  TasksDrawer.swift
//  DogHouse
//
//  The couple's agreed tasks, in a panel that slides in from the right
//  edge of Home (the clipboard button, or the tab on the edge). Either
//  partner can ask to renegotiate; once the other agrees, the negotiation
//  flow from onboarding runs again and its result replaces the list.
//

import SwiftUI
import FirebaseFirestore
import OSLog

struct TasksDrawer: View {
    @Binding var isOpen: Bool
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @EnvironmentObject var authService: AuthService

    @State private var coupleTasks: [CoupleTask] = []
    @State private var isLoading = true
    @State private var showNegotiation = false
    @State private var isBusy = false
    @State private var error: String?
    @State private var dragOffset: CGFloat = 0

    private let fs = FirebaseService.shared

    private var renegotiation: TaskRenegotiation? { challengeService.taskRenegotiation }
    private var partnerAsked: Bool {
        guard let renegotiation, !renegotiation.accepted else { return false }
        return renegotiation.requestedBy != challengeService.userId
    }

    /// The profile id, not challengeService.userId: that one stays
    /// "mock_user" in demo mode, which would file every task under "you".
    private var myId: String? { authService.userProfile?.id }

    private var coupleKey: String? {
        guard let userId = authService.userProfile?.id,
              let partnerId = authService.userProfile?.partnerId,
              partnerId != "skipped" else { return nil }
        return fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                if isOpen {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .transition(.opacity)
                    panel
                        .frame(width: min(340, geo.size.width * 0.84))
                        .offset(x: dragOffset)
                        .gesture(dragToClose)
                        .transition(.move(edge: .trailing))
                } else {
                    handle
                        .frame(maxHeight: .infinity, alignment: .top)
                        // Top of the scene window, clear of the greeting.
                        .padding(.top, geo.size.height * 0.2)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .onChange(of: isOpen, initial: true) { _, open in
            if open { Task { await loadTasks() } }
        }
        .sheet(isPresented: $showNegotiation, onDismiss: finishNegotiation) {
            NavigationStack {
                negotiationFlow
                    .navigationTitle("New Tasks")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showNegotiation = false }
                        }
                    }
            }
            .environmentObject(authService)
        }
    }

    // MARK: - Edge handle

    private var handle: some View {
        Button { open() } label: {
            VStack(spacing: 6) {
                Image(systemName: "list.clipboard.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Tasks")
                    .font(.dhBadge)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 12, height: 36)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .background(Color.dogHouseBrown, in: UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 14))
            .overlay(alignment: .topLeading) {
                if renegotiation != nil {
                    Circle().fill(Color.cozyOrange).frame(width: 10, height: 10).offset(x: -3, y: -3)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 6, x: -2, y: 2)
        }
        .buttonStyle(.plain)
        .tourAnchor(.tasksButton)
        .accessibilityLabel("Open your tasks")
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Tasks").font(.dhTitle)
                    Text("How the one in the DogHouse earns their way out.")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if coupleTasks.isEmpty {
                        Text("You haven't agreed on any tasks yet.")
                            .font(.dhBody)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        // A task is done by the partner of whoever asked
                        // for it, so each partner's wishes are the other's
                        // ways out. App suggestions work for either.
                        taskGroup("For you to do", tasks: coupleTasks.filter {
                            !$0.isAppSuggestion && $0.suggestedBy != myId
                        })
                        taskGroup("For \(partnerName) to do", tasks: coupleTasks.filter {
                            !$0.isAppSuggestion && $0.suggestedBy == myId
                        })
                        taskGroup("Either of you", tasks: coupleTasks.filter(\.isAppSuggestion))
                    }
                }
                .padding(.horizontal, 20)
            }

            renegotiationBox
                .padding(20)
        }
        .frame(maxHeight: .infinity)
        .background(
            Color.canvasTop
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24))
                .shadow(color: .black.opacity(0.2), radius: 16, x: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder private func taskGroup(_ title: String, tasks: [CoupleTask]) -> some View {
        if !tasks.isEmpty {
            Text(title)
                .font(.dhCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            ForEach(tasks) { task in
                HStack(spacing: 12) {
                    Circle()
                        .fill(task.isAppSuggestion ? Color.cozyOrange : Color.dogHouseBrown)
                        .frame(width: 8, height: 8)
                    Text(task.title).font(.dhBody)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Renegotiation

    @ViewBuilder private var renegotiationBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let renegotiation {
                if renegotiation.accepted {
                    note("🤝", "You both agreed to new tasks.")
                    primaryButton("Negotiate new tasks") { showNegotiation = true }
                    secondaryButton("Keep the old list") { act(.cancel) }
                } else if partnerAsked {
                    note("✍️", "\(partnerName) wants to renegotiate your tasks.")
                    primaryButton("Let's do it") { act(.accept) }
                    secondaryButton("Not now") { act(.decline) }
                } else {
                    note("⏳", "Waiting for \(partnerName) to agree to new tasks.")
                    secondaryButton("Cancel request") { act(.cancel) }
                }
            } else if coupleTasks.isEmpty, !isLoading {
                primaryButton("Propose tasks") { showNegotiation = true }
            } else if !isLoading {
                secondaryButton("Ask to renegotiate") { act(.request) }
                Text("\(partnerName) has to agree first. Your current tasks stay until you both confirm new ones.")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.dhCaption).foregroundStyle(.red)
            }
        }
        .disabled(isBusy)
        .animation(.easeInOut(duration: 0.2), value: renegotiation)
    }

    private func note(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji)
            Text(text).font(.dhBodyBold)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dhHeading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.cozyOrange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dhBodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Color.dogHouseBrown)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.dogHouseBrown.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private func act(_ action: ChallengeService.RenegotiationAction) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do {
                try await challengeService.renegotiateTasks(action)
                HapticService.shared.lightTap()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Negotiation

    @ViewBuilder private var negotiationFlow: some View {
        if let userId = authService.userProfile?.id,
           let partnerId = authService.userProfile?.partnerId,
           partnerId != "skipped" {
            TaskNegotiationFlowView(userId: userId, partnerId: partnerId)
        } else {
            Text("Unable to start task negotiation.")
                .foregroundStyle(.secondary)
        }
    }

    /// The sheet closed: if the new list was confirmed, close out the
    /// renegotiation (the server checks it really was) and show the list.
    private func finishNegotiation() {
        Task {
            if renegotiation?.accepted == true {
                try? await challengeService.renegotiateTasks(.complete)
            }
            await loadTasks()
        }
    }

    // MARK: - Open / close

    private func open() {
        HapticService.shared.lightTap()
        withAnimation(.spring(duration: 0.4)) { isOpen = true }
    }

    private func close() {
        withAnimation(.spring(duration: 0.4)) {
            isOpen = false
            dragOffset = 0
        }
    }

    private var dragToClose: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max(0, $0.translation.width) }
            .onEnded { value in
                if value.translation.width > 90 || value.predictedEndTranslation.width > 200 {
                    close()
                } else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Load

    private func loadTasks() async {
        #if DEBUG
        if AuthService.isDemo {
            coupleTasks = [
                CoupleTask(id: "d1", title: "Do the dishes for a week", suggestedBy: "app", isAppSuggestion: true),
                CoupleTask(id: "d2", title: "Plan a surprise date", suggestedBy: "demo_me", isAppSuggestion: false),
                CoupleTask(id: "d3", title: "Breakfast in bed", suggestedBy: "demo_partner", isAppSuggestion: false),
            ]
            isLoading = false
            return
        }
        #endif
        guard let key = coupleKey else {
            isLoading = false
            return
        }
        do {
            let doc = try await fs.coupleTasksCollection.document(key).getDocument()
            if let tasksArray = doc.data()?["tasks"] as? [[String: Any]] {
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

// MARK: - Task Negotiation Flow (embedded in a sheet)

/// Wraps the onboarding task views for use outside onboarding.
struct TaskNegotiationFlowView: View {
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
