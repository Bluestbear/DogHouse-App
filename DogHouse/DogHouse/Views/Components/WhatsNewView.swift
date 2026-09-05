//
//  WhatsNewView.swift
//  DogHouse
//
//  One-time "what's new" sheet for existing users after an update.
//  MainTabView decides when to show it (existing account + not seen yet,
//  tracked via UserDefaults). Bump `WhatsNew.version` for future updates.
//

import SwiftUI

enum WhatsNew {
    /// Bump this string for the next update round; the sheet reappears once.
    static let version = "2026-07"
    static var seenKey: String { "whatsNewSeen_\(version)" }
    /// Accounts created before this date are "existing users" who get the sheet.
    static let releaseDate = ISO8601DateFormatter().date(from: "2026-07-21T00:00:00Z")!
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        let id = UUID()
        let emoji: String
        let title: String
        let detail: String
    }

    private let items: [Item] = [
        Item(emoji: "🌹", title: "Send Roses",
             detail: "New! On your partner's room, tap the rose button to send them roses for 5 treats. They get a push and an in-app surprise — belly rubs' fancier cousin."),
        Item(emoji: "📱", title: "Widgets",
             detail: "Add the DogHouse widget to your Home Screen and Lock Screen to always know who's in the doghouse. Long-press your Home Screen → Edit → Add Widget → DogHouse."),
        Item(emoji: "🐾", title: "Belly Rubs",
             detail: "Swipe to your partner's room and hold their dog to send a belly rub. They feel it instantly."),
        Item(emoji: "🧠", title: "Couple Quizzes",
             detail: "Quizzes are simpler now: you both just answer the question and find out if you match. Start one from the + menu on Home."),
        Item(emoji: "📸", title: "Photo Dash",
             detail: "Surprise photo races pop up during the day — first to send a pic wins a Whatever-I-Want card. You can now use the camera directly, and the winning photo is shown to both of you."),
        Item(emoji: "💍", title: "Anniversary Race",
             detail: "Set your anniversary date in Profile. On the day, the first of you to wish a happy anniversary in the app wins a Whatever-I-Want card."),
        Item(emoji: "📬", title: "Input Tab",
             detail: "Got a complaint or a feature idea? The new Input tab sends it straight to the developer. Every message gets read!"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        Text("🎉")
                            .font(.system(size: 56))
                            .frame(maxWidth: .infinity)
                        Text("What's New in DogHouse")
                            .font(.dhTitle)
                            .frame(maxWidth: .infinity)
                        Text("A quick tour of everything new since your last visit")
                            .font(.dhCaption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 24)

                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Text(item.emoji).font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.dhBodyBold)
                                Text(item.detail)
                                    .font(.dhCaption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .dhPageBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Got it!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .background(.bar)
            }
        }
    }
}

#Preview {
    WhatsNewView()
}
