//
//  HomeView.swift
//  DogHouse
//
//  The main screen shows TWO separate sections:
//
//  TOP: My dog's status — Am I in the doghouse or the living room?
//       Driven by doghouseService.myDoghouseEvent (where I am the receiver).
//
//  BOTTOM: Partner controls — Did I send my partner to the doghouse?
//       Driven by doghouseService.partnerDoghouseEvent (where I am the sender).
//       Shows "Let them out" or "Send to DogHouse" button.
//

import SwiftUI
import FirebaseFirestore
import WidgetKit
import OSLog

/// Which game sheet is presented from the Home "+" menu.
enum GameSheet: Identifiable {
    case createQuiz, pickQuiz, answerQuizzes, myCards
    var id: Int { hashValue }
}

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var doghouseService = DoghouseService(userId: "mock_user", partnerId: "mock_partner")
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var achievements = AchievementService()
    @ObservedObject var challengeService: ChallengeService
    /// The live tour drives the scene page and scroll position so the
    /// control it is pointing at is actually on screen.
    @ObservedObject private var tour = TourCoordinator.shared

    @State private var showSendSheet = false
    @State private var activeGameSheet: GameSheet?
    @State private var isSubmittingPhoto = false
    /// Coarse "now" for everything that changes over minutes and hours: room
    /// level, treat accrual, the 5-hour rose window, "sent 2 hours ago", the
    /// immunity countdown. Refreshed once a minute and on foregrounding.
    /// Seconds counters do not use this — see `ElapsedTimeText`.
    @State private var currentDate = Date()
    @State private var showLevelUpToast = false
    /// nil until the first level reading of the session — see checkForLevelUp.
    @State private var lastSeenLevel: RoomLevel?
    @State private var showSendAnimation = false
    /// Set when a send succeeds; the kick starts once the sheet is gone, so
    /// it doesn't play underneath the sheet as it slides away.
    @State private var sendAnimationPending = false
    @State private var showReleaseAnimation = false
    @State private var errorMessage: String?
    @State private var showTasksSheet = false
    @State private var showAchievementsSheet = false
    @State private var showAchievementToast = false
    @State private var unlockedAchievement: Achievement?
    @State private var coupleTasks: [CoupleTask] = []
    @State private var coupleTasksLoaded = false
    @State private var scenePageIndex = 0
    @State private var showBellyRubToast = false
    @State private var bellyRubSenderName = ""
    /// Bumped when a belly rub arrives so my dog hops.
    @State private var myJumpTrigger = 0
    @State private var showRosesToast = false
    @State private var rosesSenderName = ""
    @State private var isSendingRoses = false
    @State private var isAwardingTreats = false
    @Environment(\.scenePhase) private var scenePhase

    private let shopService = ShopService()

    private var partnerName: String {
        authService.partnerProfile?.displayName ?? "Partner"
    }

    private var myAvatarId: String {
        authService.userProfile?.avatarId ?? "dog_1"
    }

    private var partnerAvatarId: String {
        authService.partnerProfile?.avatarId ?? "dog_1"
    }

    private var myCosmetics: AvatarCosmetics {
        authService.userProfile?.cosmetics ?? .none
    }

    private var partnerCosmetics: AvatarCosmetics {
        authService.partnerProfile?.cosmetics ?? .none
    }

    /// Time since I was last released (drives my room progression and treat
    /// accrual — both change over hours, so the minute-resolution
    /// `currentDate` is the right clock here).
    private var timeSinceMyRelease: TimeInterval {
        doghouseService.timeSinceMyLastRelease(
            accountCreatedAt: authService.userProfile?.createdAt,
            now: currentDate
        )
    }

    private var currentRoomLevel: RoomLevel {
        RoomLevel.level(for: timeSinceMyRelease)
    }

    private var partnerHasImmunity: Bool {
        authService.partnerProfile?.hasImmunity ?? false
    }

    private var myGraceCharges: Int {
        authService.userProfile?.effectiveGraceCharges ?? UserProfile.maxGraceCharges
    }

    private var myWishCards: Int {
        authService.userProfile?.wishCards ?? 0
    }

    private var partnerTimeSinceRelease: TimeInterval {
        doghouseService.timeSincePartnerLastRelease(
            accountCreatedAt: authService.partnerProfile?.createdAt,
            now: currentDate
        )
    }

    private var partnerRoomLevel: RoomLevel {
        RoomLevel.level(for: partnerTimeSinceRelease)
    }

    /// Rose bouquets stay next to the dog for 5 hours after sending.
    /// The minute poll refreshes `currentDate`, so these flip off on their own.
    private static let rosesDisplayWindow: TimeInterval = 5 * 3600

    /// When my current stay at home began — the anchor for the live counter.
    /// nil only in the moment before the profile has loaded.
    private var myHomeStart: Date? {
        DoghouseService.homeStartDate(
            history: doghouseService.doghouseHistory,
            receiverId: doghouseService.userId,
            accountCreatedAt: authService.userProfile?.createdAt
        )
    }

    private var myRosesActive: Bool {
        guard let sentAt = doghouseService.myRosesSentAt else { return false }
        return currentDate.timeIntervalSince(sentAt) < Self.rosesDisplayWindow
    }

    private var partnerRosesActive: Bool {
        guard let sentAt = doghouseService.partnerRosesSentAt else { return false }
        return currentDate.timeIntervalSince(sentAt) < Self.rosesDisplayWindow
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    greetingHeader

                    // Notifications disabled — the app can't work without them
                    if notificationService.authStatus == .denied {
                        NotificationsDeniedBanner {
                            notificationService.openSystemSettings()
                        }
                    }

                    // Anniversary race — only on the day, until someone wins
                    if challengeService.isAnniversaryToday,
                       challengeService.anniversaryRaceResult == nil {
                        AnniversaryRaceBanner(onTap: wishHappyAnniversary)
                    }

                    // App-triggered photo dash — first to send a pic wins
                    if let dash = challengeService.activePhotoDash {
                        PhotoDashBanner(
                            dash: dash,
                            onSubmit: submitDashPhoto,
                            onError: { errorMessage = $0 },
                            isSubmitting: isSubmittingPhoto
                        )
                    }

                    // Result of the most recent photo dash (last 24h) —
                    // shows the winning photo to both partners
                    if let result = recentPhotoDashResult {
                        PhotoDashResultCard(
                            dash: result,
                            iWon: result.winnerId == doghouseService.userId,
                            partnerName: partnerName,
                            partnerId: authService.userProfile?.partnerId
                        )
                    }

                    // The swipeable window: page 0 is my dog, page 1 is
                    // my partner's.
                    sceneSection

                    // Whichever dog you are looking at, that is whose
                    // controls you get. Swiping to your partner drops your
                    // own timer and reason, and the send button and grace
                    // meter take their place directly under the window.
                    VStack(spacing: 20) {
                        if scenePageIndex == 0 {
                            myStatusDetail
                        } else {
                            partnerControlsSection
                        }
                    }
                    .animation(.spring(duration: 0.35), value: scenePageIndex)
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .dhPageBackground()
            // Bring the tour's target into view before the spotlight lands.
            .onChange(of: tour.currentStep) { _, step in
                guard let step else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    if let page = step.scenePage {
                        scenePageIndex = page
                    }
                    switch step {
                    case .sendButton:
                        proxy.scrollTo("tour-send", anchor: .bottom)
                    case .treats:
                        proxy.scrollTo("tour-progress", anchor: .center)
                    case .welcome, .myRoom, .partnerRoom, .roses, .tasks, .games, .widgets:
                        proxy.scrollTo("tour-scene", anchor: .top)
                    default:
                        break
                    }
                }
            }
            // The greeting header stands in for the title.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTasksSheet = true
                    } label: {
                        Label("Your Tasks", systemImage: "list.clipboard")
                    }
                    .tourAnchor(.tasksButton)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Quizzes") {
                            Button { activeGameSheet = .createQuiz } label: {
                                Label("Create Quiz", systemImage: "square.and.pencil")
                            }
                            Button { activeGameSheet = .pickQuiz } label: {
                                Label("Pick Quiz", systemImage: "list.bullet.rectangle")
                            }
                            if !challengeService.pendingQuizzes.isEmpty {
                                Button { activeGameSheet = .answerQuizzes } label: {
                                    Label("Answer Quizzes (\(challengeService.pendingQuizzes.count))",
                                          systemImage: "questionmark.bubble")
                                }
                            }
                        }
                        Button { activeGameSheet = .myCards } label: {
                            Label("My Cards (\(myWishCards))", systemImage: "ticket")
                        }
                    } label: {
                        Label("Games", systemImage: "plus.circle")
                    }
                    .tourAnchor(.gamesMenu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAchievementsSheet = true
                    } label: {
                        Label("Achievements", systemImage: "trophy")
                    }
                }
            }
            .sheet(isPresented: $showTasksSheet) {
                TasksSheetView()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showAchievementsSheet) {
                AchievementsSheet(achievements: achievements, snapshot: achievementSnapshot)
            }
            .sheet(item: $activeGameSheet) { sheet in
                switch sheet {
                case .createQuiz:
                    CreateQuizSheet(challengeService: challengeService, partnerName: partnerName)
                case .pickQuiz:
                    PickQuizSheet(challengeService: challengeService, partnerName: partnerName)
                case .answerQuizzes:
                    AnswerQuizzesSheet(challengeService: challengeService, partnerName: partnerName)
                case .myCards:
                    MyCardsSheet(challengeService: challengeService, cardCount: myWishCards, partnerName: partnerName)
                }
            }
            // Level-ups are hours apart and treats accrue per whole hour, so
            // these poll once a minute. The seconds counters tick themselves
            // (ElapsedTimeText) rather than invalidating this whole body.
            .task {
                while !Task.isCancelled {
                    currentDate = Date()
                    checkForLevelUp()
                    maybeAwardTreats()
                    evaluateAchievements()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            #if DEBUG
            // `-demoKick` (with `-demoOnboarding -demoHome`): play the send
            // animation once the splash is gone, for recording it on the sim.
            .task {
                guard AuthService.isDemo,
                      ProcessInfo.processInfo.arguments.contains("-demoKick") else { return }
                try? await Task.sleep(for: .seconds(2.5))
                showSendAnimation = true
            }
            #endif
            // Coming back from the background: the clock moved on without us,
            // so refresh immediately instead of showing a stale reading until
            // the next minute poll comes round.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                currentDate = Date()
                checkForLevelUp()
                maybeAwardTreats()
                evaluateAchievements()
            }
            .animation(.spring(duration: 0.5), value: doghouseService.myDoghouseEvent?.id)
            .animation(.spring(duration: 0.5), value: doghouseService.partnerDoghouseEvent?.id)
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if showBellyRubToast {
                        bellyRubReceivedToast
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if showRosesToast {
                        rosesReceivedToast
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if showLevelUpToast {
                        levelUpToast
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if showAchievementToast, let unlockedAchievement {
                        achievementToast(unlockedAchievement)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .zIndex(10)
                .padding(.top, 8)
            }
            .onChange(of: doghouseService.receivedBellyRub) { _, senderName in
                guard let senderName else { return }
                bellyRubSenderName = senderName
                myJumpTrigger += 1
                HapticService.shared.success()
                withAnimation(.spring(duration: 0.4)) { showBellyRubToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showBellyRubToast = false }
                    doghouseService.receivedBellyRub = nil
                }
            }
            .onChange(of: doghouseService.receivedRoses) { _, senderName in
                guard let senderName else { return }
                rosesSenderName = senderName
                HapticService.shared.success()
                withAnimation(.spring(duration: 0.4)) { showRosesToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { showRosesToast = false }
                    doghouseService.receivedRoses = nil
                }
            }
            .task { writeWidgetState() }
            // Push action buttons ("Let them out", "Belly rub back")
            .onChange(of: notificationService.pendingAction, initial: true) { _, action in
                guard let action else { return }
                notificationService.pendingAction = nil
                switch action {
                case .releasePartner:
                    showReleaseAnimation = true
                    Task {
                        try? await doghouseService.releasePartner(releasedBy: "redemption")
                        SoundService.shared.playRelease()
                    }
                case .bellyRubBack:
                    handleBellyRubSend()
                }
            }
            .onChange(of: widgetSyncKey) { writeWidgetState() }
            } // ScrollViewReader
        }
        .errorBanner($errorMessage)
        // Badges are judged whenever the inputs move: pairing known,
        // a stay ends, a quiz resolves, counters tick.
        .onChange(of: authService.userProfile?.partnerId, initial: true) { _, _ in
            if let userId = authService.userProfile?.id {
                achievements.configure(userId: userId, partnerId: authService.userProfile?.partnerId)
            }
            evaluateAchievements()
        }
        .onChange(of: doghouseService.doghouseHistory.count) { evaluateAchievements() }
        .onChange(of: doghouseService.myDoghouseEvent?.id) { evaluateAchievements() }
        .onChange(of: doghouseService.partnerDoghouseEvent?.id) { evaluateAchievements() }
        .onChange(of: challengeService.challenges.count) { evaluateAchievements() }
        .onChange(of: achievements.counters) { evaluateAchievements() }
        .onChange(of: achievements.justUnlocked?.id) { _, id in
            guard id != nil, let unlocked = achievements.justUnlocked else { return }
            unlockedAchievement = unlocked
            achievements.justUnlocked = nil
            HapticService.shared.success()
            withAnimation(.spring(duration: 0.4)) { showAchievementToast = true }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showAchievementToast = false }
            }
        }
        .sheet(isPresented: $showSendSheet, onDismiss: {
            guard sendAnimationPending else { return }
            sendAnimationPending = false
            showSendAnimation = true
        }) {
            SendToDoghouseSheet(doghouseService: doghouseService, partnerName: partnerName, onSent: {
                sendAnimationPending = true
            })
            .presentationDetents([.large])
        }
        .overlay {
            if showSendAnimation {
                SendToDogHouseAnimation(
                    partnerName: partnerName,
                    avatarId: partnerAvatarId,
                    cosmetics: partnerCosmetics
                ) {
                    showSendAnimation = false
                }
                .zIndex(100)
            }
            if showReleaseAnimation {
                ReleaseFromDogHouseAnimation(partnerName: partnerName) {
                    showReleaseAnimation = false
                }
                .zIndex(100)
            }
        }
    }

    private func wishHappyAnniversary() {
        Task {
            do {
                try await challengeService.wishHappyAnniversary()
                HapticService.shared.success()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Photo Dash

    private func submitDashPhoto(_ image: UIImage) {
        guard let dash = challengeService.activePhotoDash else { return }
        isSubmittingPhoto = true
        Task {
            defer { isSubmittingPhoto = false }
            do {
                try await challengeService.submitPhoto(dash, image: image)
                HapticService.shared.success()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Photo Dash Result (winning photo, shown for 24h)

    private var recentPhotoDashResult: Challenge? {
        challengeService.challenges.first {
            $0.type == "photo" && $0.status == "completed"
                && $0.photoData != nil
                && ($0.completedAt.map { Date().timeIntervalSince($0) < 86_400 } ?? false)
        }
    }

    // MARK: - My Status Section (TOP)
    // Swipeable scene window: page 0 = my placement, page 1 = partner's
    // placement. What sits below it follows the page.

    @ViewBuilder
    private var sceneSection: some View {
        TabView(selection: $scenePageIndex) {
            mySceneView
                .tag(0)
            partnerSceneView
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 320)
        .tourAnchor(.sceneWindow, horizontalInset: 20)
        .id("tour-scene")

        // Page indicator: name labels flanking the dots
        HStack(spacing: 8) {
            Spacer()
            Text(authService.userProfile?.displayName ?? "You")
                .font(.dhCaption)
                .foregroundStyle(scenePageIndex == 0 ? Color.primary : Color.secondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(scenePageIndex == 0 ? Color.primary : Color(.systemGray4))
                    .frame(width: 7, height: 7)
                Circle()
                    .fill(scenePageIndex == 1 ? Color.primary : Color(.systemGray4))
                    .frame(width: 7, height: 7)
            }
            Text(partnerName)
                .font(.dhCaption)
                .foregroundStyle(scenePageIndex == 1 ? Color.primary : Color.secondary)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: scenePageIndex)
    }

    // MARK: My Status (page 0) — my stay, or my room while I'm home

    @ViewBuilder
    private var myStatusDetail: some View {
        if let myEvent = doghouseService.myDoghouseEvent {
            MyDoghouseInfoCard(
                event: myEvent,
                partnerName: partnerName,
                coupleTasks: coupleTasks,
                coupleTasksLoaded: coupleTasksLoaded,
                onRequestRedemption: requestRedemption,
                onShowTasks: { showTasksSheet = true }
            )
            .task { await loadCoupleTasks() }
        } else {
            myLivingRoomInfoSection
        }
    }

    // MARK: My Scene (just the visual scene for me)

    @ViewBuilder
    private var mySceneView: some View {
        if let myEvent = doghouseService.myDoghouseEvent {
            DoghouseScene(
                isCurrentUser: true,
                partnerName: authService.userProfile?.displayName ?? "You",
                duration: currentDate.timeIntervalSince(myEvent.startedAt),
                avatarId: myAvatarId,
                cosmetics: myCosmetics,
                showRoses: myRosesActive,
                jumpTrigger: myJumpTrigger
            )
            .accessibilityHidden(true)
        } else {
            LivingRoomScene(
                partnerName: authService.userProfile?.displayName ?? "You",
                isCurrentUser: true,
                level: currentRoomLevel,
                avatarId: myAvatarId,
                cosmetics: myCosmetics,
                showRoses: myRosesActive,
                jumpTrigger: myJumpTrigger
            )
            .accessibilityHidden(true)
        }
    }

    // MARK: Partner Scene (visible by swiping left)

    @ViewBuilder
    private var partnerSceneView: some View {
        Group {
            if let partnerEvent = doghouseService.partnerDoghouseEvent {
                DoghouseScene(
                    isCurrentUser: false,
                    partnerName: partnerName,
                    duration: currentDate.timeIntervalSince(partnerEvent.startedAt),
                    avatarId: partnerAvatarId,
                    cosmetics: partnerCosmetics,
                    onBellyRub: handleBellyRubSend,
                    showRoses: partnerRosesActive
                )
                .accessibilityHidden(true)
            } else {
                LivingRoomScene(
                    partnerName: partnerName,
                    isCurrentUser: false,
                    level: partnerRoomLevel,
                    avatarId: partnerAvatarId,
                    cosmetics: partnerCosmetics,
                    onBellyRub: handleBellyRubSend,
                    showRoses: partnerRosesActive
                )
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            sendRosesButton
                .padding(.trailing, 32)
                .padding(.top, 16)
        }
    }

    // MARK: - Roses

    private var sendRosesButton: some View {
        Button {
            handleRosesSend()
        } label: {
            VStack(spacing: 2) {
                if isSendingRoses {
                    ProgressView()
                } else {
                    Text("🌹").font(.title2)
                }
                Text("5 🦴")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .shadow(radius: 3)
            // Anchored on the puck itself, not the Button: the button's
            // frame carries extra hit padding and the spotlight came out as a
            // lopsided rectangle around a circle.
            .tourAnchor(.rosesButton)
        }
        .disabled(isSendingRoses)
        // The label is a bare emoji, which VoiceOver reads as "rose" with no
        // indication of what the control does or what it costs.
        .accessibilityLabel("Send roses to \(partnerName)")
        .accessibilityHint("Costs 5 treats")
    }

    private func handleRosesSend() {
        isSendingRoses = true
        HapticService.shared.success()
        Task {
            defer { isSendingRoses = false }
            do {
                try await doghouseService.sendRoses()
                achievements.record(.roses)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleBellyRubSend() {
        HapticService.shared.success()
        Task {
            let name = authService.userProfile?.displayName ?? "Partner"
            if (try? await doghouseService.sendBellyRub(fromDisplayName: name)) != nil {
                achievements.record(.bellyRubs)
            }
        }
    }

    // MARK: My Living Room Info (I'm home)

    @ViewBuilder
    private var myLivingRoomInfoSection: some View {
        RoomProgressBar(
            level: currentRoomLevel,
            timeSinceRelease: timeSinceMyRelease
        )
        .tourAnchor(.roomProgress, horizontalInset: 20)
        .id("tour-progress")

        if let myHomeStart {
            TimeAtHomeCard(start: myHomeStart, elapsed: timeSinceMyRelease)
        }
    }

    /// Tell the sender the make-it-up suggestion is done; they get a push
    /// asking to confirm.
    private func requestRedemption() {
        HapticService.shared.success()
        Task {
            do {
                try await doghouseService.requestRedemption()
            } catch {
                errorMessage = "Couldn't send: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Load Couple Tasks

    private func loadCoupleTasks() async {
        guard !coupleTasksLoaded,
              let userId = authService.userProfile?.id,
              let partnerId = authService.userProfile?.partnerId,
              partnerId != "skipped" else { return }

        let fs = FirebaseService.shared
        let key = fs.coupleKey(userId1: userId, userId2: partnerId)

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

        coupleTasksLoaded = true
    }

    // MARK: - Partner Controls Section (BOTTOM)
    // Shows either:
    //   A) "Partner is in the doghouse" card with release button (if I sent them)
    //   B) "Send to DogHouse" button (if partner is free)

    @ViewBuilder
    private var partnerControlsSection: some View {
        if let partnerEvent = doghouseService.partnerDoghouseEvent {
            // I sent my partner to the doghouse — show their status + release button
            PartnerInDoghouseCard(
                event: partnerEvent,
                partnerName: partnerName,
                avatarId: partnerAvatarId,
                cosmetics: partnerCosmetics,
                now: currentDate,
                onRelease: { releasePartner(event: partnerEvent) }
            )
        } else {
            // My partner is NOT in the doghouse — show send button
            partnerFreeSection
        }
    }

    // MARK: Partner Free — Send Button

    @ViewBuilder
    private var partnerFreeSection: some View {
        // The "Marie · Home sweet home" bar used to sit here. The partner's
        // window right above already shows their dog at home, so the bar only
        // repeated it and cost a row of space.
        GraceMeterView(charges: myGraceCharges)

        if let partner = authService.partnerProfile, partner.hasImmunity,
           let immunityEnd = partner.immunityUntil {
            PartnerImmunityBanner(
                partnerName: partnerName,
                immunityEnd: immunityEnd,
                now: currentDate
            )
        }

        SendToDoghouseButton(
            partnerName: partnerName,
            partnerHasImmunity: partnerHasImmunity,
            hasGraceCharges: myGraceCharges > 0,
            onTap: { showSendSheet = true }
        )
        .tourAnchor(.sendButton, horizontalInset: 20)
        .id("tour-send")
    }

    /// Let the partner out. Confirming a redemption claim also rewards treats,
    /// which is why the server needs to know which of the two this was.
    private func releasePartner(event: DoghouseEvent) {
        showReleaseAnimation = true
        let byRedemption = event.redemptionRequested == true
        Task {
            do {
                try await doghouseService.releasePartner(
                    releasedBy: byRedemption ? "redemption" : "sender"
                )
                SoundService.shared.playRelease()
            } catch {
                errorMessage = "Failed to release: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Greeting

    private var myFirstName: String {
        Self.firstName(of: authService.userProfile?.displayName, fallback: "there")
    }

    private var partnerFirstName: String {
        Self.firstName(of: authService.partnerProfile?.displayName, fallback: "Your partner")
    }

    private static func firstName(of displayName: String?, fallback: String) -> String {
        let first = (displayName ?? "").split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? fallback : first
    }

    /// "Good morning" / "Good afternoon" / "Good evening", "Hey" overnight.
    static func salutation(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hey"
        }
    }

    /// Whose status the greeting describes, and what it says. Page 1 of the
    /// scene window is the partner's, so swiping there swaps the line —
    /// otherwise you'd be looking at their room under a status about you.
    private var sceneStatus: (text: String, inDoghouse: Bool) {
        if scenePageIndex == 1 {
            let inDoghouse = doghouseService.partnerDoghouseEvent != nil
            return (inDoghouse
                    ? "\(partnerFirstName) is in the doghouse"
                    : "\(partnerFirstName) is doing good", inDoghouse)
        }
        let inDoghouse = doghouseService.myDoghouseEvent != nil
        return (inDoghouse ? "You're in the doghouse" : "You're doing good", inDoghouse)
    }

    private var greetingHeader: some View {
        let status = sceneStatus
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(Self.salutation(at: currentDate)), \(myFirstName)")
                .font(.dhLargeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(status.text)
                .font(.dhBodyBold)
                .foregroundStyle(status.inDoghouse ? Color.red : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: status.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same gutter as the scene card and the cards below it.
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Achievements

    /// The couple's current standing, from the services Home already holds.
    private var achievementSnapshot: AchievementSnapshot? {
        guard let me = authService.userProfile,
              let partnerId = me.partnerId, partnerId != "skipped" else { return nil }
        let partner = authService.partnerProfile
        let active = [doghouseService.myDoghouseEvent, doghouseService.partnerDoghouseEvent].compactMap { $0 }
        let bothHome = active.isEmpty ? min(timeSinceMyRelease, partnerTimeSinceRelease) : 0
        return AchievementSnapshot(
            userId: me.id,
            partnerId: partnerId,
            events: doghouseService.doghouseHistory + active,
            now: currentDate,
            bothHomeFor: bothHome,
            myLevel: currentRoomLevel,
            partnerLevel: partnerRoomLevel,
            challenges: challengeService.challenges,
            maxWishCards: max(me.wishCards ?? 0, partner?.wishCards ?? 0),
            dressedCount: [me, partner].compactMap { $0 }.filter { !($0.equippedItemIds ?? [:]).isEmpty }.count,
            maxTreats: max(me.effectiveTreats, partner?.effectiveTreats ?? 0),
            friendCount: me.friendIds.count,
            counters: achievements.counters
        )
    }

    private func evaluateAchievements() {
        guard let snapshot = achievementSnapshot else { return }
        achievements.evaluate(snapshot)
    }

    private func achievementToast(_ achievement: Achievement) -> some View {
        HomeToast {
            Text(achievement.emoji)
            VStack(alignment: .leading, spacing: 1) {
                Text("Achievement unlocked")
                    .font(.dhBadge)
                    .foregroundStyle(.secondary)
                Text(achievement.title)
                    .font(.dhCaptionBold)
            }
        }
    }

    // MARK: - Level Up Detection

    private func checkForLevelUp() {
        // Only check level ups when I'm NOT in the doghouse
        guard doghouseService.myDoghouseEvent == nil else { return }

        let newLevel = currentRoomLevel

        // First reading of the session establishes where the user already is.
        // Seeding this to level 1 instead meant every launch looked like a
        // level-up from the bottom of the ladder, so a user who had been home
        // for a month was congratulated on reaching "VIP Lounge" every time
        // they opened the app.
        guard let previous = lastSeenLevel else {
            lastSeenLevel = newLevel
            return
        }

        guard newLevel.rawValue > previous.rawValue else { return }

        lastSeenLevel = newLevel
        withAnimation(.spring(duration: 0.4)) {
            showLevelUpToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                showLevelUpToast = false
            }
        }
    }

    /// Claims treats for whole hours spent at home, scaled by room level
    /// (1-5/hr). The server computes the actual amount from event history and
    /// is the authority — this only avoids calling it more than once an hour.
    private func maybeAwardTreats() {
        // Treats are the couple's reward for BOTH being home. Nobody earns
        // while their partner is in the doghouse — the server enforces this
        // too; skipping the call here just avoids a pointless round trip.
        guard !isAwardingTreats,
              doghouseService.myDoghouseEvent == nil,
              !doghouseService.partnerIsInDoghouse else { return }

        let due: Bool
        if let lastAward = authService.userProfile?.lastTreatAward {
            due = Date().timeIntervalSince(lastAward) >= Self.treatAwardInterval
        } else {
            // Never claimed — wait for the first full hour at home to accrue.
            due = timeSinceMyRelease >= Self.treatAwardInterval
        }
        guard due else { return }

        isAwardingTreats = true
        Task {
            try? await shopService.awardHomeTreats()
            isAwardingTreats = false
        }
    }

    private static let treatAwardInterval: TimeInterval = 3600

    /// Everything the widget shows, folded into one value so a single
    /// `.onChange` keeps HomeView's body within the type-checker's budget.
    private var widgetSyncKey: String {
        [
            doghouseService.myDoghouseEvent?.id ?? "",
            doghouseService.partnerDoghouseEvent?.id ?? "",
            authService.userProfile?.avatarId ?? "",
            authService.partnerProfile?.avatarId ?? "",
            authService.userProfile?.displayName ?? "",
            authService.partnerProfile?.displayName ?? "",
        ].joined(separator: "|")
    }

    private func writeWidgetState() {
        let defaults = UserDefaults(suiteName: "group.com.harrisonkrampe.doghouse")
        defaults?.set(authService.userProfile?.avatarId ?? "dog_1", forKey: "widget_myAvatarId")
        defaults?.set(authService.partnerProfile?.avatarId ?? "dog_1", forKey: "widget_partnerAvatarId")
        defaults?.set(doghouseService.iAmInDoghouse, forKey: "widget_myInDoghouse")
        defaults?.set(doghouseService.partnerIsInDoghouse, forKey: "widget_partnerInDoghouse")
        // Extra fields for the character widget: who, since when, and how long at home.
        defaults?.set(authService.userProfile?.displayName ?? "", forKey: "widget_myName")
        defaults?.set(authService.partnerProfile?.displayName ?? "", forKey: "widget_partnerName")
        defaults?.set(doghouseService.myDoghouseEvent?.startedAt.timeIntervalSince1970 ?? 0,
                      forKey: "widget_myDoghouseSince")
        defaults?.set(doghouseService.partnerDoghouseEvent?.startedAt.timeIntervalSince1970 ?? 0,
                      forKey: "widget_partnerDoghouseSince")
        defaults?.set(Date().addingTimeInterval(-timeSinceMyRelease).timeIntervalSince1970,
                      forKey: "widget_myHomeSince")
        defaults?.set(Date().addingTimeInterval(-partnerTimeSinceRelease).timeIntervalSince1970,
                      forKey: "widget_partnerHomeSince")
        defaults?.set(authService.partnerProfile != nil, forKey: "widget_hasPartner")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var levelUpToast: some View {
        HomeToast {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("\(currentRoomLevel.unlockMessage)")
                .font(.dhCaptionBold)
        }
    }

    private var bellyRubReceivedToast: some View {
        HomeToast {
            Text("🐾")
            Text("\(bellyRubSenderName) gave you a belly rub!")
                .font(.dhCaptionBold)
            Text("❤️")
        }
    }

    private var rosesReceivedToast: some View {
        HomeToast {
            Text("🌹")
            Text("\(rosesSenderName) sent you roses!")
                .font(.dhCaptionBold)
            Text("❤️")
        }
    }
}

#Preview("Living Room") {
    HomeView(challengeService: ChallengeService(userId: "mock_user", partnerId: "mock_partner"))
        .environmentObject(AuthService())
}
