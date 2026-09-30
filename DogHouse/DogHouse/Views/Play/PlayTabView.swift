//
//  PlayTabView.swift
//  DogHouse
//
//  The Play tab: start a game, the games waiting on you, the ones waiting
//  on your partner, the scorecard with the Whatever-I-Want wallet, and the
//  trophy shelf.
//

import SwiftUI

struct PlayTabView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var challengeService: ChallengeService
    @ObservedObject var achievements: AchievementService
    @StateObject private var doghouseService = DoghouseService(userId: "mock_user", partnerId: "mock_partner")

    @State private var composing: GameKind?
    @State private var playing: Challenge?
    @State private var legacyQuiz: Challenge?
    @State private var showCards = false
    @State private var showAchievements = false
    @State private var showCouplesSoon = false
    @State private var showPaywall = false
    @ObservedObject private var purchases = PurchaseService.shared

    private var myName: String { authService.userProfile?.displayName ?? "You" }
    private var partnerName: String { authService.partnerProfile?.displayName ?? "Partner" }
    private var myWishCards: Int { authService.userProfile?.wishCards ?? 0 }
    private var myId: String { challengeService.userId }
    private var isCouplePremium: Bool {
        purchases.isCouplePremium(me: authService.userProfile, partner: authService.partnerProfile)
    }

    /// Who is sitting in the doghouse, if anyone. Play is locked until it's resolved.
    private var doghouseLockMessage: String? {
        let me = doghouseService.myDoghouseEvent != nil
        let partner = doghouseService.partnerDoghouseEvent != nil
        guard me || partner else { return nil }
        let who = me && partner ? "You're both" : me ? "You're" : "\(partnerName) is"
        return "\(who) in the doghouse. Resolve the issue and you can play!"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    gameTiles
                    yourTurn
                    theirTurn
                    scorecard
                    trophies
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .disabled(doghouseLockMessage != nil)
            .toolbar(.hidden, for: .navigationBar)
            .dhPageBackground()
            .overlay(alignment: .top) {
                Color.canvasTop.ignoresSafeArea(edges: .top).frame(height: 0)
            }
            .overlay {
                if let message = doghouseLockMessage {
                    doghouseLock(message)
                }
            }
            .sheet(item: $composing) { kind in
                GameComposerSheet(kind: kind, challengeService: challengeService, partnerName: partnerName)
            }
            .sheet(item: $playing) { game in
                GamePlaySheet(game: game, challengeService: challengeService,
                              myName: myName, partnerName: partnerName)
            }
            .sheet(item: $legacyQuiz) { quiz in
                NavigationStack {
                    QuizPlaySheet(challenge: quiz, challengeService: challengeService, partnerName: partnerName)
                }
            }
            .sheet(isPresented: $showCards) {
                MyCardsSheet(challengeService: challengeService, cardCount: myWishCards, partnerName: partnerName)
            }
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallSheet(reason: .generic)
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showAchievements) {
                AchievementsSheet(achievements: achievements, snapshot: achievements.lastSnapshot)
            }
            .alert("Couples Challenge", isPresented: $showCouplesSoon) {
                Button("Can't wait", role: .cancel) {}
            } message: {
                Text("Soon you'll be able to take on other couples from your Friends list. Warm up here first.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Play").font(.largeTitle.bold())
            Spacer()
            Button { showCards = true } label: {
                HStack(spacing: 6) {
                    Text("🎟️")
                    Text("\(myWishCards)").font(.dhCaptionBold).monospacedDigit()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(myWishCards) Whatever-I-Want cards")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Start a game

    private var gameTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Start a game")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GameKind.allCases) { kind in
                        Button { composing = kind } label: {
                            GameTile(emoji: kind.emoji, title: kind.title, tagline: kind.tagline,
                                     tint: tint(for: kind))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showCouplesSoon = true } label: {
                        GameTile(emoji: "⚔️", title: "Couples Challenge", tagline: "You two vs. another couple",
                                 tint: .dogHouseBlue, badge: "SOON")
                            .opacity(0.75)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
            .tourAnchor(.playTiles)

            if !isCouplePremium {
                freeGameHint
            }
        }
    }

    private func doghouseLock(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("🏚️").font(.system(size: 56))
            Text(message)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .combine)
    }

    /// Free couples start one new game a day (answering is never limited).
    private var freeGameHint: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").foregroundStyle(Color.cozyOrange)
                Text("1 free game a day")
                    .foregroundStyle(.secondary)
                Text("· Go unlimited")
                    .foregroundStyle(Color.cozyOrange)
            }
            .font(.dhCaption)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel("One free game a day. Get DogHouse Premium for unlimited games.")
    }

    private func tint(for kind: GameKind) -> Color {
        switch kind {
        case .preference: .cozyOrange
        case .ballKnowledge: .dogHouseBrown
        case .twoTruths: .freedomGreen
        case .likelyTo: .pink
        }
    }

    // MARK: - Your turn

    private var yourTurn: some View {
        let games = challengeService.myTurn
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Your turn", count: games.count)
            if games.isEmpty {
                emptyCard("All caught up", "Nothing waiting on you. Send \(partnerName) something!")
            } else {
                card {
                    ForEach(Array(games.enumerated()), id: \.element.id) { i, game in
                        Button { open(game) } label: {
                            GameRow(game: game, subtitle: "from \(partnerName) · \(ago(game.createdAt))") {
                                Text("Play")
                                    .font(.dhCaptionBold)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(Color.cozyOrange)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        if i < games.count - 1 { Divider().padding(.leading, 64) }
                    }
                }
            }
        }
    }

    private func open(_ game: Challenge) {
        if game.isGame { playing = game } else { legacyQuiz = game }
    }

    // MARK: - Waiting on them

    @ViewBuilder private var theirTurn: some View {
        let games = challengeService.theirTurn
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Waiting on \(partnerName)", count: games.count)
                card {
                    ForEach(Array(games.enumerated()), id: \.element.id) { i, game in
                        GameRow(game: game, subtitle: "sent \(ago(game.createdAt))") {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.secondary)
                        }
                        if i < games.count - 1 { Divider().padding(.leading, 64) }
                    }
                }
            }
        }
    }

    // MARK: - Scorecard

    private var scorecard: some View {
        let stats = challengeService.gameStats
        let mine = challengeService.myWins
        let theirs = challengeService.partnerWins
        let progress = challengeService.myCardProgress
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Scorecard")
            card {
                VStack(spacing: 16) {
                    HStack(alignment: .bottom) {
                        scoreColumn(name: "You", wins: mine, leading: mine > theirs)
                        Text("vs").font(.dhCaptionBold).foregroundStyle(.secondary).padding(.bottom, 20)
                        scoreColumn(name: partnerName, wins: theirs, leading: theirs > mine)
                    }
                    HStack(spacing: 0) {
                        statPill("\(stats.played)", "played")
                        statPill(stats.likelyToPlayed > 0 ? "\(stats.inSync)/\(stats.likelyToPlayed)" : "–", "in sync")
                        statPill(streakText, "last 5")
                    }
                    Divider()
                    Button { showCards = true } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🎟️ Next Whatever-I-Want card")
                                    .font(.dhBodyBold)
                                Spacer()
                                Text("\(progress)/\(GameStats.cardEvery) wins")
                                    .font(.dhBadge).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 5) {
                                ForEach(0..<GameStats.cardEvery, id: \.self) { i in
                                    Capsule()
                                        .fill(i < progress ? Color.cozyOrange : Color(.systemGray4))
                                        .frame(height: 6)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
    }

    /// My last five finished guess-mode games, oldest first: ● won, ○ lost.
    private var streakText: String {
        let recent = challengeService.recentResults
            .filter { $0.gameKind?.isMatchMode == false }
            .prefix(5)
        guard !recent.isEmpty else { return "–" }
        return recent.reversed().map { $0.winnerId == myId ? "●" : "○" }.joined()
    }

    private func scoreColumn(name: String, wins: Int, leading: Bool) -> some View {
        VStack(spacing: 2) {
            Text(leading ? "👑" : " ").font(.title3)
            Text("\(wins)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(leading ? Color.cozyOrange : .primary)
            Text(name).font(.dhCaptionBold).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(wins) wins")
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.dhBodyBold).monospacedDigit()
            Text(label).font(.dhBadge).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trophies

    private var trophies: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Trophies")
            Button { showAchievements = true } label: {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("🏆").font(.title2)
                            Text("\(achievements.unlockedCount) of \(Achievement.all.count) unlocked")
                                .font(.dhHeading)
                            Spacer()
                            Text("See all").font(.dhCaptionBold).foregroundStyle(Color.cozyOrange)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        if let next = achievements.nextUp {
                            HStack(spacing: 12) {
                                Text(next.achievement.emoji)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.systemGray5))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next up: \(next.achievement.title)").font(.dhBodyBold)
                                    Text(next.achievement.description)
                                        .font(.dhCaption).foregroundStyle(.secondary)
                                    ProgressView(value: Double(next.progress),
                                                 total: Double(next.achievement.target))
                                        .tint(Color.cozyOrange)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String, count: Int = 0) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.dhSubtitle)
            if count > 0 {
                Text("\(count)")
                    .font(.dhBadge)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.cozyOrange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20)
    }

    private func emptyCard(_ title: String, _ body: String) -> some View {
        card {
            VStack(spacing: 4) {
                Text(title).font(.dhBodyBold)
                Text(body).font(.dhCaption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
        }
    }

    private func ago(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Tile

private struct GameTile: View {
    let emoji: String
    let title: String
    let tagline: String
    let tint: Color
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(emoji).font(.system(size: 34))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.dhBadge)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.white.opacity(0.9))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(title)
                .font(.dhHeading)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(tagline)
                .font(.dhCaption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 150, height: 160, alignment: .leading)
        .background(tint.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: tint.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Row

private struct GameRow<Trailing: View>: View {
    let game: Challenge
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    private var emoji: String { game.gameKind?.emoji ?? "🧠" }
    private var title: String { game.gameKind?.title ?? "Couple Quiz" }

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color(.systemGray5))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.dhBodyBold)
                Text(game.gameKind == .twoTruths ? subtitle : "\(game.displayPrompt)")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if game.gameKind != .twoTruths {
                    Text(subtitle).font(.dhBadge).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}
