//
//  OnboardingContainerView.swift
//  DogHouse
//
//  Master onboarding router. Determines which step to show based on
//  the user's Firestore profile state. All transitions are driven by
//  real-time snapshot listeners — no manual navigation needed.
//

import SwiftUI

struct OnboardingContainerView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            switch currentStep {
            case .loading:
                ProfileLoadingView()

            case .nameEntry:
                NameEntryView()

            case .waitingForPartner:
                WaitingForPartnerView()

            case .avatarSelection:
                AvatarSelectionView()

            case .taskNegotiation:
                if let userId = authService.userProfile?.id,
                   let partnerId = authService.userProfile?.partnerId,
                   partnerId != "skipped" {
                    TaskNegotiationContainer(userId: userId, partnerId: partnerId)
                } else {
                    ProgressView("Setting up...")
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Step Determination

    private enum OnboardingStep: Equatable {
        case loading
        case nameEntry
        case waitingForPartner
        case avatarSelection
        case taskNegotiation
    }

    // The app tour is no longer a step here: it runs live inside MainTabView
    // (see TourCoordinator) once onboarding is done, so it can point at the
    // real controls instead of describing them.
    private var currentStep: OnboardingStep {
        // Signed in, profile not loaded yet. RootView normally holds the
        // loading screen itself; this is the belt to its braces.
        guard let profile = authService.userProfile else {
            return .loading
        }

        // Step 1: No usable name — email sign-up, Apple with the name
        // withheld, or Google without a profile name all land here.
        guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .nameEntry
        }

        // Step 2: No partner yet
        guard let partnerId = profile.partnerId, partnerId != "skipped" else {
            return .waitingForPartner
        }

        // Step 3: No avatar selected
        guard profile.hasSelectedAvatar else {
            return .avatarSelection
        }

        // Step 4: Task negotiation
        return .taskNegotiation
    }
}

// MARK: - Task Negotiation Container

/// Creates the OnboardingService and routes between 5A/5B/5C sub-phases.
private struct TaskNegotiationContainer: View {
    let userId: String
    let partnerId: String
    @StateObject private var onboardingService: OnboardingService
    @EnvironmentObject var authService: AuthService

    init(userId: String, partnerId: String) {
        self.userId = userId
        self.partnerId = partnerId
        _onboardingService = StateObject(wrappedValue:
            OnboardingService(userId: userId, partnerId: partnerId)
        )
    }

    var body: some View {
        NavigationStack {
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
            // A sync failure here used to be invisible: the screen simply waited
            // forever. Say so instead.
            .safeAreaInset(edge: .bottom) {
                if let error = onboardingService.errorMessage {
                    Text(error)
                        .font(.dhCaption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Step 4 of 4")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.3), value: onboardingService.taskDocument?.currentPhase)
        }
        .environmentObject(onboardingService)
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AuthService())
}
