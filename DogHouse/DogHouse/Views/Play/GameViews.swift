//
//  GameViews.swift
//  DogHouse
//
//  The Play tab's games: one composer for all four kinds, and the sheet
//  the partner plays it in. Answers are checked by the answerGame
//  callable; the author's answer never reaches the guesser's phone first.
//

import SwiftUI

extension Challenge {
    /// The question as the guesser reads it.
    var displayPrompt: String {
        gameKind == .likelyTo ? "Who's more likely to \(prompt.replacingOccurrences(of: "...", with: ""))" : prompt
    }

    /// likelyTo options from the viewer's side. Stored as ["me", "you"]
    /// from the author's side; the guesser's 0 is themselves.
    func optionLabels(viewerIsAuthor: Bool, authorName: String, guesserName: String) -> [String] {
        guard gameKind == .likelyTo else { return options ?? [] }
        return viewerIsAuthor ? ["Me", guesserName] : ["Me", authorName]
    }
}

// MARK: - Compose

struct GameComposerSheet: View {
    let kind: GameKind
    @ObservedObject var challengeService: ChallengeService
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var options: [String] = []
    @State private var answerIndex: Int?
    @State private var bankIndex = 0
    @State private var isSending = false
    @State private var error: String?

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        guard let answerIndex, answerIndex < options.count, !isSending else { return false }
        if kind == .likelyTo { return !trimmed(prompt).isEmpty }
        return options.allSatisfy { !trimmed($0).isEmpty }
            && (kind == .twoTruths || !trimmed(prompt).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .preference: preferenceForm
                case .ballKnowledge: ballKnowledgeForm
                case .twoTruths: twoTruthsForm
                case .likelyTo: likelyToForm
                }
                if let error {
                    Text(error).font(.dhCaption).foregroundStyle(.red)
                }
            }
            .navigationTitle("\(kind.emoji) \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .dhPageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() } else {
                        Button("Send", action: send).disabled(!canSend)
                    }
                }
            }
            .onAppear(perform: setUp)
        }
    }

    private func setUp() {
        switch kind {
        case .preference:
            bankIndex = Int.random(in: 0..<QuizQuestion.bank.count)
            loadBankQuestion()
        case .ballKnowledge:
            options = ["", ""]
        case .twoTruths:
            prompt = "Two truths and a lie"
            options = ["", "", ""]
        case .likelyTo:
            prompt = LikelyToBank.prompts.randomElement() ?? ""
            options = ["me", "you"]
        }
    }

    private func loadBankQuestion() {
        let q = QuizQuestion.bank[bankIndex]
        prompt = q.prompt
        options = [q.optionA, q.optionB]
        answerIndex = nil
    }

    // MARK: Forms

    @ViewBuilder private var preferenceForm: some View {
        Section {
            Text(prompt).font(.dhHeading)
            Button {
                bankIndex = (bankIndex + 1) % QuizQuestion.bank.count
                loadBankQuestion()
            } label: {
                Label("Another question", systemImage: "shuffle")
            }
        } footer: {
            Text("\(partnerName) sees this question and has to guess what you picked.")
        }
        Section("Your honest pick") {
            choiceRows(labels: options)
        }
    }

    @ViewBuilder private var ballKnowledgeForm: some View {
        Section {
            TextField("What was the name of my first pet?", text: $prompt, axis: .vertical)
                .lineLimit(1...3)
        } header: { Text("Your question") }
        Section {
            ForEach(options.indices, id: \.self) { i in
                HStack {
                    correctToggle(i)
                    TextField("Answer \(i + 1)", text: $options[i])
                }
            }
            .onDelete { set in
                guard options.count - set.count >= 2 else { return }
                options.remove(atOffsets: set)
                answerIndex = nil
            }
            if options.count < 4 {
                Button { options.append("") } label: { Label("Add an answer", systemImage: "plus") }
            }
        } header: { Text("Answers") } footer: {
            Text("Tap the circle next to the right one. Stump \(partnerName) and the point is yours.")
        }
    }

    @ViewBuilder private var twoTruthsForm: some View {
        Section {
            ForEach(options.indices, id: \.self) { i in
                HStack {
                    correctToggle(i)
                    TextField("Statement \(i + 1)", text: $options[i], axis: .vertical)
                        .lineLimit(1...3)
                }
            }
        } header: { Text("Three things about you") } footer: {
            Text("Two true, one made up. Tap the circle next to the lie.")
        }
    }

    @ViewBuilder private var likelyToForm: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Who's more likely to").foregroundStyle(.secondary)
                TextField("...burn toast?", text: $prompt, axis: .vertical)
            }
            Button {
                prompt = LikelyToBank.prompts.filter { $0 != prompt }.randomElement() ?? prompt
            } label: {
                Label("Another one", systemImage: "shuffle")
            }
        } footer: {
            Text("\(partnerName) answers too. Name the same person and you're in sync.")
        }
        Section("Your answer") {
            choiceRows(labels: ["Me", partnerName])
        }
    }

    private func choiceRows(labels: [String]) -> some View {
        ForEach(labels.indices, id: \.self) { i in
            Button {
                answerIndex = i
                HapticService.shared.lightTap()
            } label: {
                HStack {
                    Text(labels[i]).foregroundStyle(.primary)
                    Spacer()
                    if answerIndex == i {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cozyOrange)
                    }
                }
            }
        }
    }

    private func correctToggle(_ i: Int) -> some View {
        Button {
            answerIndex = i
            HapticService.shared.lightTap()
        } label: {
            Image(systemName: answerIndex == i ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(answerIndex == i ? Color.cozyOrange : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .twoTruths ? "Mark as the lie" : "Mark as correct")
    }

    private func send() {
        guard let answerIndex else { return }
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                try await challengeService.createGame(
                    kind,
                    prompt: trimmed(prompt),
                    options: options.map(trimmed),
                    answerIndex: answerIndex
                )
                HapticService.shared.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Play

struct GamePlaySheet: View {
    let game: Challenge
    @ObservedObject var challengeService: ChallengeService
    let myName: String
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    @State private var guess: Int?
    @State private var result: ChallengeService.GameResult?
    @State private var isSending = false
    @State private var error: String?

    private var kind: GameKind { game.gameKind ?? .preference }
    private var labels: [String] {
        game.optionLabels(viewerIsAuthor: false, authorName: partnerName, guesserName: myName)
    }

    private var question: String {
        switch kind {
        case .preference: "Which did \(partnerName) pick?"
        case .ballKnowledge: "\(partnerName) asks:"
        case .twoTruths: "Which one is the lie?"
        case .likelyTo: "What do you say?"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(kind.emoji).font(.system(size: 48))
                        Text(question).font(.dhCaptionBold).foregroundStyle(.secondary)
                        if kind != .twoTruths {
                            Text(game.displayPrompt)
                                .font(.dhTitle)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 12)

                    VStack(spacing: 10) {
                        ForEach(labels.indices, id: \.self) { i in
                            optionButton(i)
                        }
                    }

                    if let result { resultCard(result) }
                    if let error {
                        Text(error).font(.dhCaption).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .dhPageBackground()
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if result != nil {
                        Button("Done") { dismiss() }
                    } else if isSending {
                        ProgressView()
                    } else {
                        Button("Lock in", action: submit).disabled(guess == nil)
                    }
                }
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(isSending)
        }
    }

    private func optionButton(_ i: Int) -> some View {
        let isGuess = guess == i
        let revealed = result?.answerIndex
        // likelyTo: the author's pick is from their side, so "you" (1)
        // is me — the same person as my 0.
        let isAnswer: Bool = {
            guard let revealed else { return false }
            return kind == .likelyTo ? revealed != i : revealed == i
        }()
        let fill: Color = {
            guard result != nil else { return isGuess ? Color.cozyOrange.opacity(0.2) : Color(.systemGray6) }
            if isAnswer { return Color.freedomGreen.opacity(0.25) }
            return isGuess ? Color.red.opacity(0.18) : Color(.systemGray6)
        }()
        return Button {
            guard result == nil else { return }
            guess = i
            HapticService.shared.lightTap()
        } label: {
            HStack {
                Text(labels[i])
                    .font(.dhBodyBold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if result != nil, isAnswer {
                    Text(kind == .twoTruths ? "the lie" : kind == .likelyTo ? "\(partnerName)'s pick" : "answer")
                        .font(.dhBadge).foregroundStyle(Color.freedomGreen)
                } else if isGuess {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cozyOrange)
                }
            }
            .padding(16)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isGuess && result == nil ? Color.cozyOrange : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func resultCard(_ r: ChallengeService.GameResult) -> some View {
        let (emoji, title, body): (String, String, String) = {
            if kind == .likelyTo {
                return r.correct
                    ? ("💞", "In sync!", "You both pointed at the same person.")
                    : ("😅", "Agree to disagree", "Time to talk about it.")
            }
            return r.correct
                ? ("🎯", "You know them!", "Point to you.")
                : ("😵", "Stumped!", "Point to \(partnerName).")
        }()
        return VStack(spacing: 6) {
            Text(emoji).font(.system(size: 44))
            Text(title).font(.dhTitle)
            Text(body).font(.dhBody).foregroundStyle(.secondary)
            if r.cardEarned, let winner = r.winnerId {
                Label(winner == challengeService.userId
                      ? "You earned a Whatever-I-Want card 🎟️"
                      : "\(partnerName) earned a Whatever-I-Want card 🎟️",
                      systemImage: "sparkles")
                    .font(.dhBodyBold)
                    .foregroundStyle(Color.cozyOrange)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .transition(.scale.combined(with: .opacity))
    }

    private func submit() {
        guard let guess else { return }
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                let r = try await challengeService.answerGame(game, guessIndex: guess)
                withAnimation(.spring(duration: 0.45)) { result = r }
                if r.correct { HapticService.shared.success() } else { HapticService.shared.warning() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
