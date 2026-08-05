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
import Combine
import FirebaseFirestore
import WidgetKit
import PhotosUI
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
    @ObservedObject var challengeService: ChallengeService

    @State private var showSendSheet = false
    @State private var activeGameSheet: GameSheet?
    @State private var photoPick: PhotosPickerItem?
    @State private var isSubmittingPhoto = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common)
    @State private var timerConnection: (any Cancellable)?
    @State private var currentDate = Date()
    @State private var showLevelUpToast = false
    @State private var lastSeenLevel: RoomLevel = .bareBones
    @State private var showSendAnimation = false
    @State private var showReleaseAnimation = false
    @State private var errorMessage: String?
    @State private var showTasksSheet = false
    @State private var coupleTasks: [CoupleTask] = []
    @State private var coupleTasksLoaded = false
    @State private var scenePageIndex = 0
    @State private var showBellyRubToast = false
    @State private var bellyRubSenderName = ""
    @State private var showRosesToast = false
    @State private var rosesSenderName = ""
    @State private var isSendingRoses = false
    @State private var showCameraPicker = false
    @State private var isAwardingTreats = false

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

    /// Time since I was last released (drives my room progression)
    private var timeSinceMyRelease: TimeInterval {
        doghouseService.timeSinceMyLastRelease()
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
        doghouseService.timeSincePartnerLastRelease()
    }

    private var partnerRoomLevel: RoomLevel {
        RoomLevel.level(for: partnerTimeSinceRelease)
    }

    /// Rose bouquets stay next to the dog for 5 hours after sending.
    /// currentDate ticks every second, so these flip off automatically.
    private static let rosesDisplayWindow: TimeInterval = 5 * 3600

    /// Whether anything on screen is actually counting.
    ///
    /// The 1 Hz tick invalidates this whole view, so it must not run when
    /// there is no elapsed-time label, immunity countdown, or rose bouquet
    /// to update — otherwise the Home tab re-renders once a second for the
    /// entire session, including while the user is on another tab.
    private var needsSecondTicks: Bool {
        if doghouseService.iAmInDoghouse || doghouseService.partnerIsInDoghouse { return true }
        if doghouseService.myRosesSentAt != nil || doghouseService.partnerRosesSentAt != nil { return true }
        if let immunityEnd = authService.userProfile?.immunityUntil, immunityEnd > currentDate { return true }
        return false
    }

    private func syncTimer() {
        if needsSecondTicks, timerConnection == nil {
            currentDate = Date()
            timerConnection = timer.connect()
        } else if !needsSecondTicks, timerConnection != nil {
            timerConnection?.cancel()
            timerConnection = nil
        }
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
            ScrollView {
                VStack(spacing: 20) {
                    // Notifications disabled — the app can't work without them
                    if notificationService.authStatus == .denied {
                        notificationsDeniedBanner
                    }

                    // Anniversary race — only on the day, until someone wins
                    if challengeService.isAnniversaryToday,
                       challengeService.anniversaryRaceResult == nil {
                        anniversaryRaceBanner
                    }

                    // App-triggered photo dash — first to send a pic wins
                    if let dash = challengeService.activePhotoDash {
                        photoDashBanner(dash)
                    }

                    // Result of the most recent photo dash (last 24h) —
                    // shows the winning photo to both partners
                    if let result = recentPhotoDashResult {
                        photoDashResultCard(result)
                    }

                    // ==========================================
                    // TOP SECTION: My own dog's status
                    // ==========================================
                    myStatusSection

                    // ==========================================
                    // BOTTOM SECTION: Partner controls
                    // ==========================================
                    partnerControlsSection
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("DogHouse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTasksSheet = true
                    } label: {
                        Label("Your Tasks", systemImage: "list.clipboard")
                    }
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
                }
            }
            .sheet(isPresented: $showTasksSheet) {
                TasksSheetView()
                    .environmentObject(authService)
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
            // The 1 Hz tick only refreshes elapsed-time labels, and runs only
            // while one is on screen.
            .onReceive(timer) { date in
                currentDate = date
            }
            // Level-ups are hours apart and treats accrue per whole hour, so
            // these poll once a minute instead of 60× more often than needed.
            .task {
                while !Task.isCancelled {
                    syncTimer()
                    currentDate = Date()
                    checkForLevelUp()
                    maybeAwardTreats()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .onChange(of: doghouseService.myDoghouseEvent?.id) { _, _ in syncTimer() }
            .onChange(of: doghouseService.partnerDoghouseEvent?.id) { _, _ in syncTimer() }
            .onChange(of: doghouseService.myRosesSentAt) { _, _ in syncTimer() }
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
                }
                .zIndex(10)
                .padding(.top, 8)
            }
            .onChange(of: doghouseService.receivedBellyRub) { _, senderName in
                guard let senderName else { return }
                bellyRubSenderName = senderName
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
            .onChange(of: doghouseService.iAmInDoghouse) { writeWidgetState() }
            .onChange(of: doghouseService.partnerIsInDoghouse) { writeWidgetState() }
            .onChange(of: authService.userProfile?.avatarId) { writeWidgetState() }
            .onChange(of: authService.partnerProfile?.avatarId) { writeWidgetState() }
        }
        .errorBanner($errorMessage)
        .sheet(isPresented: $showSendSheet) {
            SendToDoghouseSheet(doghouseService: doghouseService, partnerName: partnerName, onSent: {
                showSendAnimation = true
            })
            .presentationDetents([.large])
        }
        .overlay {
            if showSendAnimation {
                SendToDogHouseAnimation(partnerName: partnerName) {
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

    // MARK: - Notifications Denied Banner

    private var notificationsDeniedBanner: some View {
        Button {
            notificationService.openSystemSettings()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off")
                        .font(.dhBodyBold)
                        .foregroundStyle(.white)
                    Text("DogHouse can't work without them — tap to enable in Settings")
                        .font(.dhCaption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(Color.red.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel("Notifications are disabled. Tap to open Settings and enable them.")
    }

    // MARK: - Anniversary Race Banner

    private var anniversaryRaceBanner: some View {
        Button {
            Task {
                do {
                    try await challengeService.wishHappyAnniversary()
                    HapticService.shared.success()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text("💍 IT'S YOUR ANNIVERSARY! 💍")
                    .font(.headline)
                Text("Tap FIRST to wish it & win a Whatever-I-Want card!")
                    .font(.caption)
                    .opacity(0.95)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color.cozyOrange, Color(red: 0.9, green: 0.35, blue: 0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Photo Dash Banner

    private func photoDashBanner(_ dash: Challenge) -> some View {
        HStack(spacing: 12) {
            Text("📸").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo Dash!").font(.dhBodyBold)
                Text(dash.prompt).font(.dhCaption).foregroundStyle(.secondary)
            }
            Spacer()
            if isSubmittingPhoto {
                ProgressView()
            } else {
                // Snap with the camera — the true "dash" experience
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCameraPicker = true
                    } label: {
                        Image(systemName: "camera.fill").font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cozyOrange)
                }
                // Or pick from the library
                PhotosPicker(selection: $photoPick, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cozyOrange)
            }
        }
        .padding(14)
        .background(Color.cozyOrange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { image in
                submitDashPhoto(image)
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            isSubmittingPhoto = true
            Task {
                defer { photoPick = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        isSubmittingPhoto = false
                        errorMessage = "Couldn't load that photo"; return
                    }
                    submitDashPhoto(image)
                } catch {
                    isSubmittingPhoto = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

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

    @ViewBuilder
    private func photoDashResultCard(_ dash: Challenge) -> some View {
        let iWon = dash.winnerId == doghouseService.userId
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("📸").font(.title3)
                Text(iWon ? "You won the Photo Dash! 🎉"
                          : "\(partnerName) won the Photo Dash")
                    .font(.dhBodyBold)
                Spacer()
            }
            if let base64 = dash.photoData,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(dash.prompt)
                .font(.dhCaption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.freedomGreen.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: - My Status Section (TOP)
    // Swipeable scene window: page 0 = my placement, page 1 = partner's placement.
    // The info card below always reflects my own status.

    @ViewBuilder
    private var myStatusSection: some View {
        TabView(selection: $scenePageIndex) {
            mySceneView
                .tag(0)
            partnerSceneView
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 320)

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

        // Info card — always shows my own status data
        if let myEvent = doghouseService.myDoghouseEvent {
            myDoghouseInfoCard(event: myEvent)
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
                showRoses: myRosesActive
            )
            .accessibilityHidden(true)
        } else {
            LivingRoomScene(
                partnerName: authService.userProfile?.displayName ?? "You",
                isCurrentUser: true,
                level: currentRoomLevel,
                avatarId: myAvatarId,
                cosmetics: myCosmetics,
                showRoses: myRosesActive
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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleBellyRubSend() {
        HapticService.shared.success()
        Task {
            let name = authService.userProfile?.displayName ?? "Partner"
            try? await doghouseService.sendBellyRub(fromDisplayName: name)
        }
    }

    // MARK: My Living Room Info (I'm home)

    @ViewBuilder
    private var myLivingRoomInfoSection: some View {
        RoomProgressBar(
            level: currentRoomLevel,
            timeSinceRelease: timeSinceMyRelease
        )

        VStack(spacing: 4) {
            Text("You've been home for:")
                .font(.dhCaption)
                .foregroundStyle(.secondary)
            Text(timeSinceMyRelease.formattedTimer)
                .font(.dhTimer)
                .foregroundStyle(Color.freedomGreen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You've been home for \(timeSinceMyRelease.formattedDuration)")
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: My Doghouse Info Card (I'm sent to the doghouse)

    @ViewBuilder
    private func myDoghouseInfoCard(event: DoghouseEvent) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("You've been sent to the DogHouse!")
                    .font(.dhTitle)
                    .multilineTextAlignment(.center)

                Text(currentDate.timeIntervalSince(event.startedAt).formattedTimer)
                    .font(.dhTimer)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Reason", systemImage: "text.quote")
                    .font(.dhCaptionBold)
                    .foregroundStyle(.secondary)
                Text(event.reason)
                    .font(.dhBody)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 12) {
                Label("How to get out:", systemImage: "lightbulb.fill")
                    .font(.dhCaptionBold)
                    .foregroundStyle(Color.cozyOrange)

                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wait it out")
                            .font(.dhBodyBold)
                        Text("Stay here until \(partnerName) lets you out")
                            .font(.dhCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Redemption: mark the make-it-up suggestion as done
                if let suggestion = event.suggestion {
                    if event.redemptionRequested == true {
                        HStack(spacing: 10) {
                            Image(systemName: "hourglass")
                                .foregroundStyle(Color.cozyOrange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Redemption requested")
                                    .font(.dhBodyBold)
                                Text("Waiting for \(partnerName) to confirm...")
                                    .font(.dhCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.cozyOrange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Button {
                            HapticService.shared.success()
                            Task {
                                do {
                                    try await doghouseService.requestRedemption()
                                } catch {
                                    errorMessage = "Couldn't send: \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("🦴")
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("I did it!")
                                        .font(.dhBodyBold)
                                    Text("\"\(suggestion)\" — tell \(partnerName) you made it up")
                                        .font(.dhCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "paperplane.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.freedomGreen)
                            }
                            .padding(10)
                            .background(Color.freedomGreen.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark the make-it-up suggestion as done and notify \(partnerName)")
                    }
                }

                if coupleTasks.isEmpty && coupleTasksLoaded {
                    Button {
                        showTasksSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "list.clipboard.fill")
                                .foregroundStyle(Color.cozyOrange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Do a Task")
                                    .font(.dhBodyBold)
                                Text("No tasks set up yet — tap to propose tasks!")
                                    .font(.dhCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(Color.cozyOrange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else if !coupleTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "list.clipboard.fill")
                                .foregroundStyle(Color.cozyOrange)
                                .frame(width: 28)
                            Text("Do a Task")
                                .font(.dhBodyBold)
                            Spacer()
                        }

                        ForEach(coupleTasks) { task in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.cozyOrange)
                                    .frame(width: 6, height: 6)
                                Text(task.title)
                                    .font(.dhBody)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.cozyOrange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .task { await loadCoupleTasks() }
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
        // Divider between my status and partner controls
        HStack {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
            Text(partnerName)
                .font(.dhCaptionBold)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
        }
        .padding(.horizontal, 24)

        if let partnerEvent = doghouseService.partnerDoghouseEvent {
            // I sent my partner to the doghouse — show their status + release button
            partnerInDoghouseCard(event: partnerEvent)
        } else {
            // My partner is NOT in the doghouse — show send button
            partnerFreeSection
        }
    }

    // MARK: Partner In Doghouse Card

    @ViewBuilder
    private func partnerInDoghouseCard(event: DoghouseEvent) -> some View {
        VStack(spacing: 12) {
            // Partner's avatar + status
            HStack(spacing: 12) {
                AvatarView(
                    avatar: DogAvatar.avatar(for: partnerAvatarId),
                    mood: .sad,
                    size: 56,
                    cosmetics: partnerCosmetics
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partnerName) is in the DogHouse")
                        .font(.dhBodyBold)
                        .foregroundStyle(.red)
                    Text("Sent \(currentDate.timeIntervalSince(event.startedAt).formattedDuration) ago")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Reason
            VStack(alignment: .leading, spacing: 4) {
                Text("Reason: \(event.reason)")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                if let suggestion = event.suggestion {
                    Text("To get out: \(suggestion)")
                        .font(.dhCaption)
                        .foregroundStyle(Color.cozyOrange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Redemption requested — the dog says they made it up
            if event.redemptionRequested == true {
                HStack(spacing: 10) {
                    Text("🦴")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(partnerName) says they made it up!")
                            .font(.dhBodyBold)
                        if let suggestion = event.suggestion {
                            Text("\"\(suggestion)\"")
                                .font(.dhCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.cozyOrange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Release button — confirming a redemption also rewards treats
            Button {
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
            } label: {
                HStack {
                    Image(systemName: "lock.open.fill")
                    Text(event.redemptionRequested == true
                         ? "Confirm & Let \(partnerName) Out 🦴"
                         : "Let \(partnerName) Out 🏠")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.freedomGreen)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Release \(partnerName) from the doghouse")
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: Partner Free — Send Button

    @ViewBuilder
    private var partnerFreeSection: some View {
        // Partner info bar
        if let partner = authService.partnerProfile {
            HStack(spacing: 12) {
                AvatarView(
                    avatar: DogAvatar.avatar(for: partner.avatarId ?? "dog_1"),
                    mood: .happy,
                    size: 52,
                    cosmetics: partnerCosmetics
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(partner.displayName)
                        .font(.dhBodyBold)
                    Text("Home sweet home")
                        .font(.dhCaption)
                        .foregroundStyle(Color.freedomGreen)
                }

                Spacer()

                if partner.hasImmunity {
                    Label("Immune", systemImage: "shield.fill")
                        .font(.dhBadge)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }

        // Grace meter
        graceMeterView

        // Immunity banner
        if let partner = authService.partnerProfile, partner.hasImmunity,
           let immunityEnd = partner.immunityUntil {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partnerName) has immunity!")
                        .font(.dhCaptionBold)
                    Text("Expires in \(immunityEnd.timeIntervalSince(currentDate).formattedDuration)")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }

        // Send to doghouse button
        Button {
            showSendSheet = true
        } label: {
            HStack {
                Image(systemName: "house.fill")
                Text("Send \(partnerName) to the DogHouse 🐕")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(sendDisabled ? Color.gray.opacity(0.4) : Color.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(sendDisabled)
        .accessibilityLabel(sendDisabled
            ? partnerHasImmunity
                ? "\(partnerName) has immunity, cannot send to doghouse"
                : "No grace charges remaining"
            : "Send \(partnerName) to the doghouse")
        .padding(.horizontal, 20)
    }

    private var sendDisabled: Bool {
        partnerHasImmunity || myGraceCharges <= 0
    }

    // MARK: - Grace Meter

    private var graceMeterView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(myGraceCharges > 0 ? Color.cozyOrange : .red)
                Text("Grace")
                    .font(.dhCaptionBold)
                Spacer()
                Text("\(myGraceCharges) / \(UserProfile.maxGraceCharges)")
                    .font(.dhCaptionBold)
                    .foregroundStyle(myGraceCharges > 0 ? Color.primary : Color.red)
            }

            // Charge pips
            HStack(spacing: 6) {
                ForEach(0..<UserProfile.maxGraceCharges, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index < myGraceCharges ? Color.cozyOrange : Color(.systemGray4))
                        .frame(height: 8)
                }
            }
            // The pips encode the count purely through colour.
            .accessibilityHidden(true)

            if myGraceCharges < UserProfile.maxGraceCharges {
                Text("Recharges 1 per day")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        // Read as one sentence instead of four disconnected fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Grace: \(myGraceCharges) of \(UserProfile.maxGraceCharges) remaining."
            + (myGraceCharges < UserProfile.maxGraceCharges ? " Recharges one per day." : "")
        )
    }

    // MARK: - Level Up Detection

    private func checkForLevelUp() {
        // Only check level ups when I'm NOT in the doghouse
        guard doghouseService.myDoghouseEvent == nil else { return }

        let newLevel = currentRoomLevel
        if newLevel.rawValue > lastSeenLevel.rawValue {
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
    }

    // Awards treats per complete hour at home, scaled by room level (1-5/hr).
    private func maybeAwardTreats() {
        guard !isAwardingTreats,
              doghouseService.myDoghouseEvent == nil,
              let lastAward = authService.userProfile?.lastTreatAward else {
            // If lastTreatAward is nil the user has never been awarded — kick off on first hour.
            if !isAwardingTreats,
               doghouseService.myDoghouseEvent == nil,
               authService.userProfile?.lastTreatAward == nil,
               timeSinceMyRelease >= 3600 {
                isAwardingTreats = true
                Task {
                    try? await shopService.awardHomeTreats(lastAward: nil, treatsPerHour: currentRoomLevel.treatsPerHour)
                    isAwardingTreats = false
                }
            }
            return
        }
        guard Date().timeIntervalSince(lastAward) >= 3600 else { return }
        isAwardingTreats = true
        Task {
            try? await shopService.awardHomeTreats(lastAward: lastAward, treatsPerHour: currentRoomLevel.treatsPerHour)
            isAwardingTreats = false
        }
    }

    private func writeWidgetState() {
        let defaults = UserDefaults(suiteName: "group.com.harrisonkrampe.doghouse")
        defaults?.set(authService.userProfile?.avatarId ?? "dog_1", forKey: "widget_myAvatarId")
        defaults?.set(authService.partnerProfile?.avatarId ?? "dog_1", forKey: "widget_partnerAvatarId")
        defaults?.set(doghouseService.iAmInDoghouse, forKey: "widget_myInDoghouse")
        defaults?.set(doghouseService.partnerIsInDoghouse, forKey: "widget_partnerInDoghouse")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var levelUpToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("\(currentRoomLevel.unlockMessage)")
                .font(.dhCaptionBold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
    }

    private var bellyRubReceivedToast: some View {
        HStack(spacing: 8) {
            Text("🐾")
            Text("\(bellyRubSenderName) gave you a belly rub!")
                .font(.dhCaptionBold)
            Text("❤️")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
    }

    private var rosesReceivedToast: some View {
        HStack(spacing: 8) {
            Text("🌹")
            Text("\(rosesSenderName) sent you roses!")
                .font(.dhCaptionBold)
            Text("❤️")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
    }
}

#Preview("Living Room") {
    HomeView(challengeService: ChallengeService(userId: "mock_user", partnerId: "mock_partner"))
        .environmentObject(AuthService())
}
