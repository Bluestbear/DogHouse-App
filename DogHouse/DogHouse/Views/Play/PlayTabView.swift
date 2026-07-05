//
//  PlayTabView.swift
//  DogHouse
//
//  Couple games: the anniversary race, quizzes, photo dashes, and the
//  "Whatever I Want" card wallet.
//

import SwiftUI
import PhotosUI

struct PlayTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var challengeService = ChallengeService(userId: "mock_user", partnerId: "mock_partner")

    @State private var showAnniversaryPicker = false
    @State private var anniversaryDraft = Date()
    @State private var showRedeemSheet = false
    @State private var quizToPlay: Challenge?
    @State private var errorMessage: String?
    @State private var raceWonAnimation = false

    private var partnerName: String {
        authService.partnerProfile?.displayName ?? "your partner"
    }

    private var myWishCards: Int {
        authService.userProfile?.wishCards ?? 0
    }

    private var activeChallenges: [Challenge] {
        challengeService.challenges.filter { $0.isActive }
    }

    private var completedChallenges: [Challenge] {
        challengeService.challenges.filter { !$0.isActive }.prefix(10).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                anniversarySection
                wishCardSection
                startSection

                if !activeChallenges.isEmpty {
                    Section("Active Challenges") {
                        ForEach(activeChallenges) { challenge in
                            activeChallengeRow(challenge)
                        }
                    }
                }

                if !challengeService.receivedWishes.filter({ $0.fulfilled != true }).isEmpty {
                    wishesOwedSection
                }

                if !completedChallenges.isEmpty {
                    Section("History") {
                        ForEach(completedChallenges) { challenge in
                            completedChallengeRow(challenge)
                        }
                    }
                }
            }
            .navigationTitle("Play")
            .errorBanner($errorMessage)
            .sheet(isPresented: $showAnniversaryPicker) {
                anniversaryPickerSheet
            }
            .sheet(isPresented: $showRedeemSheet) {
                RedeemWishSheet(challengeService: challengeService, partnerName: partnerName)
            }
            .sheet(item: $quizToPlay) { quiz in
                QuizPlaySheet(challenge: quiz, challengeService: challengeService, partnerName: partnerName)
            }
            .overlay {
                if raceWonAnimation {
                    ConfettiView().allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Anniversary

    @ViewBuilder
    private var anniversarySection: some View {
        Section {
            if let anniversary = challengeService.anniversary {
                if challengeService.isAnniversaryToday {
                    anniversaryRaceCard
                } else {
                    HStack(spacing: 12) {
                        Text("💍")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anniversary: \(anniversary.formatted(.dateTime.month(.wide).day()))")
                                .font(.subheadline.bold())
                            Text(daysUntilText(anniversary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") {
                            anniversaryDraft = anniversary
                            showAnniversaryPicker = true
                        }
                        .font(.caption)
                    }
                }
            } else {
                Button {
                    showAnniversaryPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Text("💍")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set your anniversary")
                                .font(.subheadline.bold())
                            Text("On the day, first to wish it in the app wins a card!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Anniversary")
        }
    }

    @ViewBuilder
    private var anniversaryRaceCard: some View {
        if let result = challengeService.anniversaryRaceResult {
            // Someone already won this year
            let iWon = result.winnerId == challengeService.userId
            HStack(spacing: 12) {
                Text(iWon ? "🏆" : "🐌")
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(iWon ? "You won the race!" : "\(partnerName) beat you to it!")
                        .font(.subheadline.bold())
                        .foregroundStyle(iWon ? Color.freedomGreen : .red)
                    Text("Happy Anniversary! 💕")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            Button {
                Task {
                    do {
                        try await challengeService.wishHappyAnniversary()
                        HapticService.shared.success()
                        withAnimation { raceWonAnimation = true }
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { raceWonAnimation = false }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                VStack(spacing: 6) {
                    Text("💍 IT'S YOUR ANNIVERSARY! 💍")
                        .font(.headline)
                    Text("Tap FIRST to win a Whatever-I-Want card!")
                        .font(.caption)
                        .opacity(0.9)
                    Text("Happy Anniversary! 🎉")
                        .font(.title3.bold())
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
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    private var anniversaryPickerSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Anniversary date", selection: $anniversaryDraft, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Your Anniversary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAnniversaryPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await challengeService.setAnniversary(anniversaryDraft)
                                showAnniversaryPicker = false
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func daysUntilText(_ anniversary: Date) -> String {
        let cal = Calendar.current
        var next = cal.dateComponents([.month, .day], from: anniversary)
        next.year = cal.component(.year, from: Date())
        guard var date = cal.date(from: next) else { return "" }
        if date < cal.startOfDay(for: Date()) {
            date = cal.date(byAdding: .year, value: 1, to: date) ?? date
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: date).day ?? 0
        return days == 0 ? "Today!" : "\(days) day\(days == 1 ? "" : "s") to go — don't forget!"
    }

    // MARK: - Wish Cards

    private var wishCardSection: some View {
        Section {
            HStack(spacing: 12) {
                Text("🎟️")
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(myWishCards) Whatever-I-Want card\(myWishCards == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                    Text(myWishCards > 0
                         ? "Redeem one — \(partnerName) can't say no."
                         : "Win a challenge to earn one!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if myWishCards > 0 {
                    Button("Redeem") { showRedeemSheet = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.cozyOrange)
                        .font(.caption.bold())
                }
            }
        } header: {
            Text("Your Cards")
        }
    }

    private var wishesOwedSection: some View {
        Section {
            ForEach(challengeService.receivedWishes.filter { $0.fulfilled != true }) { wish in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(wish.fromName) wants:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("“\(wish.text)”")
                        .font(.subheadline)
                    Button {
                        Task { try? await challengeService.markWishFulfilled(wish) }
                    } label: {
                        Label("Mark as done", systemImage: "checkmark.circle")
                            .font(.caption.bold())
                    }
                    .tint(Color.freedomGreen)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("You Owe 😅")
        }
    }

    // MARK: - Start a Challenge

    private var startSection: some View {
        Section {
            Button {
                Task {
                    do { try await challengeService.startQuiz() }
                    catch { errorMessage = error.localizedDescription }
                }
            } label: {
                Label("Start a Couple Quiz", systemImage: "brain.head.profile")
            }
            .disabled(activeChallenges.contains { $0.type == "quiz" })

            Button {
                Task {
                    do { try await challengeService.startPhotoDash() }
                    catch { errorMessage = error.localizedDescription }
                }
            } label: {
                Label("Start a Photo Dash", systemImage: "camera.fill")
            }
            .disabled(activeChallenges.contains { $0.type == "photo" })
        } header: {
            Text("New Challenge")
        } footer: {
            Text("Winner gets a Whatever-I-Want card 🎟️")
        }
    }

    // MARK: - Challenge Rows

    @ViewBuilder
    private func activeChallengeRow(_ challenge: Challenge) -> some View {
        if challenge.type == "quiz" {
            let answered = challenge.hasAnswered(challengeService.userId)
            Button {
                if !answered { quizToPlay = challenge }
            } label: {
                HStack(spacing: 12) {
                    Text("🧠")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.prompt)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(answered
                             ? "Waiting for \(partnerName) to answer..."
                             : "Tap to answer!")
                            .font(.caption)
                            .foregroundStyle(answered ? .secondary : Color.cozyOrange)
                    }
                    Spacer()
                    if !answered {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if challenge.type == "photo" {
            PhotoDashRow(challenge: challenge, challengeService: challengeService, errorMessage: $errorMessage)
        }
    }

    @ViewBuilder
    private func completedChallengeRow(_ challenge: Challenge) -> some View {
        let iWon = challenge.winnerId == challengeService.userId
        HStack(spacing: 12) {
            Text(challenge.type == "quiz" ? "🧠" : challenge.type == "photo" ? "📸" : "💍")
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(.caption.bold())
                Text(challenge.isTie ? "It's a tie 🤝" : iWon ? "You won 🏆" : "\(partnerName) won")
                    .font(.caption2)
                    .foregroundStyle(challenge.isTie ? Color.secondary : iWon ? Color.freedomGreen : .red)
            }
            Spacer()
            if challenge.type == "photo", let b64 = challenge.photoData,
               let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(challenge.createdAt.formatted(.dateTime.month().day()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Photo Dash Row

private struct PhotoDashRow: View {
    let challenge: Challenge
    @ObservedObject var challengeService: ChallengeService
    @Binding var errorMessage: String?

    @State private var pickedItem: PhotosPickerItem?
    @State private var isUploading = false

    var body: some View {
        HStack(spacing: 12) {
            Text("📸")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.prompt)
                    .font(.subheadline.bold())
                Text("First photo in wins!")
                    .font(.caption)
                    .foregroundStyle(Color.cozyOrange)
            }
            Spacer()
            if isUploading {
                ProgressView()
            } else {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cozyOrange)
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            isUploading = true
            Task {
                defer { isUploading = false; pickedItem = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        errorMessage = "Couldn't load that photo"
                        return
                    }
                    try await challengeService.submitPhoto(challenge, image: image)
                    HapticService.shared.success()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Quiz Play Sheet

private struct QuizPlaySheet: View {
    let challenge: Challenge
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    @State private var ownChoice: String?
    @State private var guessChoice: String?
    @State private var isSubmitting = false

    private var options: [String] { challenge.options ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(challenge.prompt)
                        .font(.headline)
                }

                Section("Your own answer") {
                    optionPicker(selection: $ownChoice)
                }

                Section("What will \(partnerName) pick?") {
                    optionPicker(selection: $guessChoice)
                }

                Section {
                    Button {
                        guard let ownChoice, let guessChoice else { return }
                        isSubmitting = true
                        Task {
                            defer { isSubmitting = false }
                            do {
                                try await challengeService.answerQuiz(challenge, own: ownChoice, guess: guessChoice)
                                dismiss()
                            } catch {
                                // surfaced via list error banner on next open
                                dismiss()
                            }
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Lock it in 🔒")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(ownChoice == nil || guessChoice == nil || isSubmitting)
                } footer: {
                    Text("Guess your partner's answer right (while they get yours wrong) to win the card.")
                }
            }
            .navigationTitle("Couple Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
    }

    private func optionPicker(selection: Binding<String?>) -> some View {
        ForEach(options, id: \.self) { option in
            Button {
                selection.wrappedValue = option
            } label: {
                HStack {
                    Text(option)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.wrappedValue == option {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.freedomGreen)
                    }
                }
            }
        }
    }
}

// MARK: - Redeem Wish Sheet

private struct RedeemWishSheet: View {
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    @State private var wishText = ""
    @State private var isSending = false
    @State private var error: String?

    private let ideas = [
        "Breakfast in bed this weekend",
        "You pick the next 3 movies",
        "A full back massage",
        "Dishes are yours for a week",
        "Plan me a surprise date",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("I want...", text: $wishText, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Your wish")
                } footer: {
                    Text("\(partnerName) gets notified — and a card's a card. No take-backs.")
                }

                Section("Need ideas?") {
                    ForEach(ideas, id: \.self) { idea in
                        Button(idea) { wishText = idea }
                            .foregroundStyle(.primary)
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Redeem Card 🎟️")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Redeem") {
                            isSending = true
                            Task {
                                defer { isSending = false }
                                do {
                                    try await challengeService.redeemWishCard(
                                        text: wishText.trimmingCharacters(in: .whitespacesAndNewlines))
                                    HapticService.shared.success()
                                    dismiss()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        }
                        .disabled(wishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

#Preview {
    PlayTabView()
        .environmentObject(AuthService())
}
