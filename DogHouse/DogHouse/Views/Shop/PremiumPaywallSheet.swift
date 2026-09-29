//
//  PremiumPaywallSheet.swift
//  DogHouse
//
//  DogHouse Premium: one subscription for the couple. Presented when the
//  daily free game is used up, when a free couple taps Save on a Photo Dash,
//  and from Settings.
//
//  Nothing here grants premium. A completed purchase flips the device's
//  RevenueCat entitlement at once (optimistic, so the buyer can carry on);
//  the RevenueCat webhook then writes `premiumUntil` server-side, which is
//  what lifts the game limit and what unlocks the partner's phone through
//  their user-document listener.
//

import SwiftUI

struct PremiumPaywallSheet: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject private var purchases = PurchaseService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Why the sheet opened, for the subtitle.
    var reason: Reason = .generic

    enum Reason {
        case gameLimit, savePhoto, generic
    }

    @State private var selectedPlanId: String = PremiumPlan.yearlyId
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    /// From a completed purchase until the server's `premiumUntil` lands on
    /// my profile or the watchdog gives up. Sheet-local, like the treat store.
    @State private var isAwaitingServer = false
    @State private var serverWatchdog: Task<Void, Never>?
    @State private var justSubscribed = false

    /// The webhook normally lands in a few seconds; 20 s covers a slow one
    /// without making the sheet feel stuck. The local entitlement already
    /// counts as premium meanwhile.
    private let serverTimeout: Duration = .seconds(20)

    private var partnerName: String? { authService.partnerProfile?.displayName }
    private var isCouplePremium: Bool {
        purchases.isCouplePremium(me: authService.userProfile, partner: authService.partnerProfile)
    }
    private var selectedPlan: PremiumPlan? {
        purchases.premiumPlans.first { $0.id == selectedPlanId } ?? purchases.premiumPlans.last
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    perks

                    if justSubscribed || isCouplePremium {
                        activeCard
                    } else if purchases.isLoadingPremium && purchases.premiumPlans.isEmpty {
                        ProgressView().padding(.top, 30)
                    } else if purchases.premiumPlans.isEmpty {
                        EmptyStateView(
                            icon: "crown",
                            title: "Premium isn't available right now",
                            subtitle: "Plans couldn't be loaded. Please try again later."
                        )
                        .padding(.top, 12)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(purchases.premiumPlans) { plan in
                                planCard(plan)
                            }
                        }
                        subscribeButton
                    }

                    messages
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("DogHouse Premium")
            .navigationBarTitleDisplayMode(.inline)
            .dhPageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await purchases.refreshEntitlement()
            await purchases.loadPremium()
        }
        // The server's word arrives on the profile listener.
        .onChange(of: authService.userProfile?.isPremiumActive ?? false) { _, active in
            guard active, isAwaitingServer else { return }
            serverWatchdog?.cancel()
            serverWatchdog = nil
            withAnimation { isAwaitingServer = false }
        }
        .onDisappear {
            serverWatchdog?.cancel()
            serverWatchdog = nil
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cozyOrange.opacity(0.30), Color.cozyOrange.opacity(0)],
                            center: .center, startRadius: 6, endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                Image(systemName: "crown.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Color.cozyOrange)
                    .rotationEffect(.degrees(-10))
            }
            .frame(height: 110)

            Text("DogHouse Premium, for both of you")
                .font(.dhTitle)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.dhCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var subtitle: String {
        switch reason {
        case .gameLimit: "You've played today's free game. Go unlimited and keep the fun going."
        case .savePhoto: "Keep your Photo Dash moments. Premium saves them straight to Photos."
        case .generic: "One subscription covers your whole couple."
        }
    }

    // MARK: - Perks

    private var perks: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The Play tab's own bone, so the perk reads as "more of that tab".
            perkRow(Image("TabBone"), "Unlimited games", "Free couples get one new game a day")
            perkRow(Image(systemName: "square.and.arrow.down.fill"), "Save Photo Dashes", "Keep the winning photos in your library")
            perkRow(Image(systemName: "heart.circle.fill"),
                    "One subscription, two phones",
                    partnerName.map { "Covers \($0) too, no second purchase" } ?? "Covers your partner too")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private func perkRow(_ icon: Image, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            // Resizable so the bone asset and the SF Symbols share one size.
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.cozyOrange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.dhBodyBold)
                Text(detail).font(.dhCaption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plans

    private func planCard(_ plan: PremiumPlan) -> some View {
        let selected = selectedPlan?.id == plan.id
        return Button {
            selectedPlanId = plan.id
            HapticService.shared.lightTap()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.cozyOrange : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(.dhHeading)
                        if plan.isYearly {
                            tag(plan.trialLabel.map { "\($0) · best value" } ?? "Best value",
                                color: .cozyOrange)
                        }
                    }
                    if let perMonth = plan.perMonthLabel {
                        Text(perMonth)
                            .font(.dhCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.displayPrice).font(.dhBodyBold)
                    Text(plan.periodLabel).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.cozyOrange.opacity(selected ? 0.9 : 0), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("\(plan.title), \(plan.displayPrice) \(plan.periodLabel)"
                            + (plan.trialLabel.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var isBusy: Bool {
        purchases.subscribingPlanId != nil || purchases.isRestoring || isAwaitingServer
    }

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                if let plan = selectedPlan { subscribe(plan) }
            } label: {
                Group {
                    if purchases.subscribingPlanId != nil {
                        ProgressView().tint(.white)
                    } else {
                        Text(selectedPlan?.trialLabel != nil ? "Start free trial" : "Subscribe")
                            .font(.dhBodyBold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isBusy ? Color(.systemGray4) : Color.cozyOrange)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || selectedPlan == nil)

            // Apple requires the price after the trial to be stated clearly.
            if let plan = selectedPlan {
                Text(priceTerms(plan))
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Restore Purchases") { restore() }
                .font(.dhCaption)
                .disabled(isBusy)
        }
        .padding(.top, 4)
    }

    private func priceTerms(_ plan: PremiumPlan) -> String {
        if let trial = plan.trialLabel {
            return "\(trial), then \(plan.displayPrice) \(plan.periodLabel). Cancel anytime."
        }
        return "\(plan.displayPrice) \(plan.periodLabel). Cancel anytime."
    }

    // MARK: - Active

    private var activeCard: some View {
        VStack(spacing: 10) {
            if isAwaitingServer {
                ProgressView()
                Text(partnerName.map { "You're in! Unlocking Premium for you and \($0)…" }
                     ?? "You're in! Unlocking Premium…")
                    .font(.dhBodyBold)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.freedomGreen)
                Text("Premium is on")
                    .font(.dhHeading)
                Text(activeDetail)
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    dismiss()
                } label: {
                    Text("Let's play")
                        .font(.dhBodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.freedomGreen.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .transition(.opacity)
    }

    private var activeDetail: String {
        let viaPartner = !(authService.userProfile?.isPremiumActive ?? false)
            && !purchases.hasPremiumEntitlement
            && (authService.partnerProfile?.isPremiumActive ?? false)
        if viaPartner, let partnerName {
            return "\(partnerName)'s subscription covers you both. Unlimited games and Photo Dash saves are unlocked."
        }
        return partnerName.map { "Unlimited games and Photo Dash saves, for you and \($0)." }
            ?? "Unlimited games and Photo Dash saves are unlocked."
    }

    // MARK: - Messages & footnote

    @ViewBuilder
    private var messages: some View {
        if let err = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(err).font(.dhCaption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.red)
            .padding(12)
            .background(Color.red.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        if let info = infoMessage {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text(info).font(.dhCaption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.cozyOrange)
            .padding(12)
            .background(Color.cozyOrange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .transition(.opacity)
        }
    }

    private var footnote: some View {
        VStack(spacing: 6) {
            Text("One subscription covers your partner too.")
                .font(.dhCaptionBold)
            Text("Payment is charged to your Apple Account. The subscription renews automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel it in your App Store settings.")
            HStack(spacing: 14) {
                Button("Terms of Use") { openURL(Legal.termsURL) }
                Button("Privacy Policy") { openURL(Legal.privacyURL) }
            }
            .font(.caption2.weight(.semibold))
            #if DEBUG
            if purchases.isDemo {
                Text("Preview mode — no real purchase is made.")
                    .foregroundStyle(Color.cozyOrange)
            }
            #endif
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.dhBadge)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Actions

    private func subscribe(_ plan: PremiumPlan) {
        Task {
            withAnimation {
                errorMessage = nil
                infoMessage = nil
            }
            do {
                guard try await purchases.subscribe(plan) else { return }
                HapticService.shared.success()
                withAnimation(.snappy) { justSubscribed = true }
                startAwaitingServer()
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    private func restore() {
        Task {
            withAnimation {
                errorMessage = nil
                infoMessage = nil
            }
            do {
                if try await purchases.restorePurchases() {
                    HapticService.shared.success()
                    withAnimation(.snappy) { justSubscribed = true }
                } else {
                    withAnimation { infoMessage = "No active subscription was found for this Apple Account." }
                }
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    /// Paid; now wait for the webhook's `premiumUntil`. The local entitlement
    /// already unlocks this phone, so giving up after `serverTimeout` is not
    /// an error, only a note that the partner's phone may take a moment.
    private func startAwaitingServer() {
        #if DEBUG
        // No webhook in the demo: the local entitlement is the whole story.
        if purchases.isDemo { return }
        #endif
        guard !(authService.userProfile?.isPremiumActive ?? false) else { return }
        isAwaitingServer = true
        serverWatchdog?.cancel()
        serverWatchdog = Task {
            try? await Task.sleep(for: serverTimeout)
            guard !Task.isCancelled, isAwaitingServer else { return }
            withAnimation {
                isAwaitingServer = false
                infoMessage = partnerName.map { "Premium is on for this phone. \($0)'s app will unlock within a minute." }
                    ?? "Premium is on for this phone. It can take a minute to sync."
            }
        }
    }
}
