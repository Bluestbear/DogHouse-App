//
//  AppTourView.swift
//  DogHouse
//
//  Step 4: Swipeable walkthrough explaining how the app works.
//  On completion, writes tourComplete = true to Firestore.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AppTourView: View {
    @State private var currentPage = 0

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
            icon: "person.2.fill",
            iconColor: .dogHouseBlue,
            title: "The Squad",
            description: "Connect with friends. When multiple dogs are in the house, the squad votes on who gets out first!",
            backgroundEmoji: "👥"
        ),
        TourPage(
            icon: "bag.fill",
            iconColor: Color(red: 0.62, green: 0.18, blue: 0.88),
            title: "Earn Treats & Shop",
            description: "You earn 🦴 10 treats for every hour you spend at home. Use them in the Shop to dress up your dog — or your partner's! Sending your partner to the DogHouse costs them treats, so use your grace charges wisely.",
            backgroundEmoji: "🛍️"
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

            Spacer()
            Spacer()
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
}

#Preview {
    AppTourView()
}
