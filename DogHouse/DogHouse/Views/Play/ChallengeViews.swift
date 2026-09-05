//
//  ChallengeViews.swift
//  DogHouse
//
//  Sheets for the couple games, reached from the Home "+" menu:
//  create/pick/answer quizzes and the Whatever-I-Want card wallet.
//

import SwiftUI

// MARK: - Answer picker (shared)

private struct OptionPicker: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        ForEach(options, id: \.self) { option in
            Button {
                selection = option
            } label: {
                HStack {
                    Text(option).foregroundStyle(.primary)
                    Spacer()
                    if selection == option {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.freedomGreen)
                    }
                }
            }
        }
    }
}

// MARK: - Create Quiz (author your own question)

struct CreateQuizSheet: View {
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var optionA = ""
    @State private var optionB = ""
    @State private var own: String?
    @State private var isSending = false
    @State private var error: String?

    private var options: [String] { [optionA, optionB].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var ready: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty
            && options.count == 2 && own != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your question") {
                    TextField("e.g. Cats or dogs?", text: $prompt, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Option A", text: $optionA)
                    TextField("Option B", text: $optionB)
                }
                if options.count == 2 {
                    Section("Your answer") {
                        OptionPicker(options: options, selection: $own)
                    }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Create a Quiz")
            .dhPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() }
                    else {
                        Button("Send") { submit() }.disabled(!ready)
                    }
                }
            }
        }
    }

    private func submit() {
        guard let own else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await challengeService.createQuiz(
                    prompt: prompt.trimmingCharacters(in: .whitespaces),
                    optionA: optionA.trimmingCharacters(in: .whitespaces),
                    optionB: optionB.trimmingCharacters(in: .whitespaces),
                    own: own)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Pick Quiz (browse the bank)

struct PickQuizSheet: View {
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(QuizQuestion.bank.indices, id: \.self) { i in
                let q = QuizQuestion.bank[i]
                NavigationLink {
                    BankAnswerView(question: q, challengeService: challengeService,
                                   partnerName: partnerName, onDone: { dismiss() })
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.prompt).font(.subheadline.bold())
                        Text("\(q.optionA)  vs  \(q.optionB)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Pick a Quiz")
            .dhPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct BankAnswerView: View {
    let question: QuizQuestion
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    let onDone: () -> Void

    @State private var own: String?
    @State private var isSending = false
    @State private var error: String?

    private var options: [String] { [question.optionA, question.optionB] }

    var body: some View {
        Form {
            Section { Text(question.prompt).font(.headline) }
            Section("Your answer") { OptionPicker(options: options, selection: $own) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .navigationTitle("Answer")
        .dhPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSending { ProgressView() }
                else {
                    Button("Send") {
                        guard let own else { return }
                        isSending = true
                        Task {
                            defer { isSending = false }
                            do {
                                try await challengeService.createQuiz(
                                    prompt: question.prompt, optionA: question.optionA,
                                    optionB: question.optionB, own: own)
                                onDone()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(own == nil)
                }
            }
        }
    }
}

// MARK: - Answer pending quizzes (partner started these)

struct AnswerQuizzesSheet: View {
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if challengeService.pendingQuizzes.isEmpty {
                    EmptyStateView(icon: "checkmark.circle",
                                   title: "All caught up!",
                                   subtitle: "No quizzes waiting for your answer.")
                } else {
                    List(challengeService.pendingQuizzes) { quiz in
                        NavigationLink {
                            QuizPlaySheet(challenge: quiz, challengeService: challengeService,
                                          partnerName: partnerName, onDone: {})
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quiz.prompt).font(.subheadline.bold())
                                Text("from \(partnerName)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Answer Quizzes")
            .dhPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Quiz play (answer a single quiz)

struct QuizPlaySheet: View {
    let challenge: Challenge
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var own: String?
    @State private var isSending = false

    private var options: [String] { challenge.options ?? [] }

    var body: some View {
        Form {
            Section { Text(challenge.prompt).font(.headline) }
            Section("Your answer") { OptionPicker(options: options, selection: $own) }
            Section {
                Button {
                    guard let own else { return }
                    isSending = true
                    Task {
                        defer { isSending = false }
                        try? await challengeService.answerQuiz(challenge, own: own)
                        onDone(); dismiss()
                    }
                } label: {
                    if isSending { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Lock it in 🔒").frame(maxWidth: .infinity) }
                }
                .disabled(own == nil || isSending)
            } footer: {
                Text("Once you've both answered, you'll find out if you and \(partnerName) match.")
            }
        }
        .navigationTitle("Couple Quiz")
        .dhPageBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Whatever-I-Want card wallet

struct MyCardsSheet: View {
    @ObservedObject var challengeService: ChallengeService
    let cardCount: Int
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    @State private var showRedeem = false

    private var owed: [Wish] { challengeService.receivedWishes.filter { $0.fulfilled != true } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Text("🎟️").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(cardCount) card\(cardCount == 1 ? "" : "s")")
                                .font(.title3.bold())
                            Text(cardCount > 0 ? "\(partnerName) can't say no." : "Win a challenge to earn one!")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if cardCount > 0 {
                            Button("Redeem") { showRedeem = true }
                                .buttonStyle(.borderedProminent).tint(Color.cozyOrange)
                        }
                    }
                }

                if !owed.isEmpty {
                    Section("You Owe 😅") {
                        ForEach(owed) { wish in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(wish.fromName) wants:").font(.caption.bold()).foregroundStyle(.secondary)
                                Text("“\(wish.text)”").font(.subheadline)
                                Button {
                                    Task { try? await challengeService.markWishFulfilled(wish) }
                                } label: {
                                    Label("Mark as done", systemImage: "checkmark.circle").font(.caption.bold())
                                }
                                .tint(Color.freedomGreen)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Whatever-I-Want")
            .dhPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showRedeem) {
                RedeemWishSheet(challengeService: challengeService, partnerName: partnerName)
            }
        }
    }
}

// MARK: - Redeem a card

struct RedeemWishSheet: View {
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
                    TextField("I want...", text: $wishText, axis: .vertical).lineLimit(2...4)
                } header: { Text("Your wish") } footer: {
                    Text("\(partnerName) gets notified — and a card's a card. No take-backs.")
                }
                Section("Need ideas?") {
                    ForEach(ideas, id: \.self) { idea in
                        Button(idea) { wishText = idea }.foregroundStyle(.primary)
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle("Redeem Card 🎟️")
            .dhPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() }
                    else {
                        Button("Redeem") {
                            isSending = true
                            Task {
                                defer { isSending = false }
                                do {
                                    try await challengeService.redeemWishCard(
                                        text: wishText.trimmingCharacters(in: .whitespacesAndNewlines))
                                    HapticService.shared.success(); dismiss()
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .disabled(wishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
