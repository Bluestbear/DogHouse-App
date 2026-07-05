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
            case .waitingForPartner:
                WaitingForPartnerView()

            case .avatarSelection:
                AvatarSelectionView()

            case .appTour:
                AppTourView()

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
        case waitingForPartner
        case avatarSelection
        case appTour
        case taskNegotiation
    }

    private var currentStep: OnboardingStep {
        guard let profile = authService.userProfile else {
            return .waitingForPartner
        }

        // Step 2: No partner yet
        guard let partnerId = profile.partnerId, partnerId != "skipped" else {
            return .waitingForPartner
        }

        // Step 3: No avatar selected
        guard profile.hasSelectedAvatar else {
            return .avatarSelection
        }

        // Step 4: Tour not complete
        guard profile.isTourComplete else {
            return .appTour
        }

        // Step 5: Task negotiation
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
