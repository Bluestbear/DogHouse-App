//
//  AppTourView.swift
//  DogHouse
//
//  Step 4: Swipeable walkthrough explaining how the app works.
//  Includes an inline anniversary picker page. On completion, writes
//  tourComplete = true to Firestore.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import OSLog

struct AppTourView: View {
    @EnvironmentObject var authService: AuthService
    @State private var currentPage = 0

    // Anniversary page state
    @State private var anniversaryDraft = Date()
    @State private var anniversarySaved = false
    @State private var isSavingAnniversary = false

    private let pages: [TourPage] = [
        TourPage(
            icon: "house.fill",
            iconColor: .freedomGreen,
            title: "The Living Room",
            description: "When things are good, your dog chills at home. The longer you stay out of trouble, the cozier it gets!",
            backgroundEmoji: "🏠"
        ),
        TourPage(
            icon: "cloud.rain.fill",
            iconColor: .red,
            title: "The DogHouse",
            description: "Mess up and your partner sends you here. The longer you stay, the worse it gets...",
            backgroundEmoji: "🐕"
        ),
        TourPage(
            icon: "list.clipboard.fill",
            iconColor: .cozyOrange,
            title: "Tasks & Freedom",
            description: "When you're in the DogHouse, complete tasks your partner set to earn your freedom. Choose wisely!",
            backgroundEmoji: "📋"
        ),
        TourPage(
            icon: "pawprint.fill",
            iconColor: Color(red: 0.62, green: 0.18, blue: 0.88),
            title: "Earn Treats Together",
            description: "As long as you're out of the DogHouse, you each earn 🦴 treats every hour at home. Spend them in the Shop on your own dog — or spoil your partner's with a gift. Land in the DogHouse and the treats stop, so be good to each other!",
            backgroundEmoji: "🦴"
        ),
        TourPage(
            icon: "hand.raised.fingers.spread.fill",
            iconColor: .cozyOrange,
            title: "Belly Rubs & Roses",
            description: "Swipe to your partner's room and hold their dog for a belly rub — they feel it instantly. Feeling extra sweet? Tap the 🌹 button to send them roses for 5 treats.",
            backgroundEmoji: "🐾"
        ),
        TourPage(
            icon: "brain.head.profile",
            iconColor: .dogHouseBlue,
            title: "Quizzes & Games",
            description: "Start couple quizzes from the + menu on Home and see if your answers match. Watch out for surprise Photo Dashes — winners earn a Whatever-I-Want card your partner can't refuse!",
            backgroundEmoji: "🧠"
        ),
        TourPage(
            icon: "heart.circle.fill",
            iconColor: .red,
            title: "Your Anniversary",
            description: "On the day itself, the first of you to wish a happy anniversary in the app wins a Whatever-I-Want card. Set your date now so the race is on!",
            backgroundEmoji: "💍",
            isAnniversaryPage: true
        ),
        TourPage(
            icon: "square.grid.2x2.fill",
            iconColor: .cozyOrange,
            title: "Widgets",
            description: "Add the DogHouse widget to your Home Screen and Lock Screen to always know who's in the doghouse — without even opening the app. Long-press your Home Screen → Edit → Add Widget → DogHouse.",
            backgroundEmoji: "📱"
        ),
        TourPage(
            icon: "person.2.fill",
            iconColor: .dogHouseBlue,
            title: "The Squad",
            description: "Connect with friends. When multiple dogs are in the house, the squad votes on who gets out first!",
            backgroundEmoji: "👥"
        ),
        TourPage(
            icon: "envelope.fill",
            iconColor: .freedomGreen,
            title: "Your Input Matters",
            description: "Got a complaint or an idea for a feature? The Input tab sends your message straight to the developer. Every message gets read!",
            backgroundEmoji: "📬"
        ),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        tourPageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.dogHouseBrown : Color(.systemGray4))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 20)

                // Button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        completeTour()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Let's Go!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Step 3 of 5")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            completeTour()
                        }
                        .font(.dhCaption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tourPageView(_ page: TourPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Background emoji
            Text(page.backgroundEmoji)
                .font(.system(size: 80))

            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 50))
                .foregroundStyle(page.iconColor)

            // Title
            Text(page.title)
                .font(.dhTitle)

            // Description
            Text(page.description)
                .font(.dhBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if page.isAnniversaryPage {
                anniversaryPicker
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Anniversary Picker

    private var anniversaryPicker: some View {
        VStack(spacing: 12) {
            DatePicker("Anniversary date", selection: $anniversaryDraft, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()

            Button {
                saveAnniversary()
            } label: {
                Group {
                    if isSavingAnniversary {
                        ProgressView()
                    } else if anniversarySaved {
                        Label("Saved!", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Save date", systemImage: "heart.fill")
                    }
                }
                .font(.dhCaptionBold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(anniversarySaved ? Color.freedomGreen.opacity(0.2) : Color(.systemGray5))
                .foregroundStyle(anniversarySaved ? Color.freedomGreen : .primary)
                .clipShape(Capsule())
            }
            .disabled(isSavingAnniversary || anniversarySaved)

            Text("You can change this anytime in Profile.")
                .font(.dhCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .onChange(of: anniversaryDraft) {
            anniversarySaved = false
        }
    }

    private func saveAnniversary() {
        guard let uid = Auth.auth().currentUser?.uid,
              let partnerId = authService.userProfile?.partnerId,
              partnerId != "skipped" else { return }
        isSavingAnniversary = true
        Task {
            defer { isSavingAnniversary = false }
            let fs = FirebaseService.shared
            let key = fs.coupleKey(userId1: uid, userId2: partnerId)
            do {
                try await fs.coupleMetaCollection.document(key).setData([
                    "anniversary": Timestamp(date: anniversaryDraft),
                    "userIds": [uid, partnerId]
                ], merge: true)
                anniversarySaved = true
                HapticService.shared.success()
            } catch {
                Logger.data.error("Anniversary save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func completeTour() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await FirebaseService.shared.usersCollection
                .document(uid)
                .updateData(["tourComplete": true])
        }
        // Snapshot listener picks up change → OnboardingContainerView advances
    }
}

private struct TourPage {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let backgroundEmoji: String
    var isAnniversaryPage: Bool = false
}

#Preview {
    AppTourView()
        .environmentObject(AuthService())
}
