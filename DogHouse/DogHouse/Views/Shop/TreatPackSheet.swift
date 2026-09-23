//
//  TreatPackSheet.swift
//  DogHouse
//
//  The treat store: buy treats with real money, presented from the Shop
//  tab's "Get treats" button.
//
//  Nothing here credits treats. A completed purchase flips to a waiting
//  state and the balance arrives on AuthService's user-document listener
//  once the RevenueCat webhook has credited it server-side. (In the debug
//  demo the Shop credits locally so the same waiting state resolves.)
//

import SwiftUI

struct TreatPackSheet: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var purchases = PurchaseService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    /// Balance when the purchase started, so we can tell when the credit lands.
    @State private var treatsBeforePurchase: Int?
    /// Briefly shown once the credit has arrived.
    @State private var justCredited: Int?
    /// True from a completed purchase until the server-credited balance lands
    /// or the watchdog gives up. Sheet-local on purpose: dismissing the sheet
    /// must not leave a stale "Adding…" for the next time it opens.
    @State private var isAwaitingCredit = false
    /// Gives up waiting after `creditTimeout`; the credit still arrives on the
    /// listener whenever the webhook gets round to it.
    @State private var creditWatchdog: Task<Void, Never>?
    /// Shown when the credit took longer than we are willing to spin for.
    @State private var pendingMessage: String?

    /// How long to show "Adding…" before handing over to `pendingMessage`.
    /// The webhook normally lands in a few seconds; 20 s covers a slow
    /// receipt check without making the sheet feel stuck.
    private let creditTimeout: Duration = .seconds(20)

    private var treats: Int { authService.userProfile?.effectiveTreats ?? 100 }
    private var partnerName: String? { authService.partnerProfile?.displayName }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    balanceCard

                    if purchases.isLoading && purchases.packs.isEmpty {
                        ProgressView().padding(.top, 30)
                    } else if purchases.packs.isEmpty {
                        EmptyStateView(
                            icon: "bag",
                            title: "No packs available",
                            subtitle: "Treat packs couldn't be loaded right now. Please try again later."
                        )
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(purchases.packs) { pack in
                                packCard(pack)
                            }
                        }
                    }

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

                    if let pending = pendingMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.checkmark")
                            Text(pending).font(.dhCaption)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.cozyOrange)
                        .padding(12)
                        .background(Color.cozyOrange.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity)
                    }

                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Treat Store")
            .navigationBarTitleDisplayMode(.inline)
            .dhPageBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await purchases.loadPacks() }
        // The credit arrives asynchronously from the server — watch the
        // balance rather than assuming the purchase call's return means treats.
        .onChange(of: treats) { oldValue, newValue in
            if let before = treatsBeforePurchase, newValue > before {
                creditWatchdog?.cancel()
                creditWatchdog = nil
                treatsBeforePurchase = nil
                isAwaitingCredit = false
                HapticService.shared.success()
                withAnimation(.snappy) {
                    pendingMessage = nil
                    justCredited = newValue - oldValue
                }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { justCredited = nil }
                }
            }
        }
        .onDisappear {
            creditWatchdog?.cancel()
            creditWatchdog = nil
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
                Text("🦴")
                    .font(.system(size: 58))
                    .rotationEffect(.degrees(-18))
            }
            .frame(height: 110)

            Text("Top up your treats")
                .font(.dhTitle)

            Text(partnerName.map {
                "Treats buy hats, glasses and necklaces — for your dog or \($0)'s."
            } ?? "Treats buy hats, glasses and necklaces for your dog.")
                .font(.dhCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Balance

    private var balanceCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your balance")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("🦴").font(.title3)
                    Text("\(treats)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.cozyOrange)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: treats)
                    Text("treats")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isAwaitingCredit {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Adding…")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if let added = justCredited {
                Text("+\(added) 🦴")
                    .font(.dhHeading)
                    .foregroundStyle(Color.freedomGreen)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .animation(.easeInOut, value: isAwaitingCredit)
    }

    // MARK: - Pack card

    private func packCard(_ pack: TreatPack) -> some View {
        let isBusy = purchases.purchasingProductId == pack.id
        let anyBusy = purchases.purchasingProductId != nil || isAwaitingCredit
        let highlighted = pack.isBestValue

        return HStack(spacing: 14) {
            tierBadge(pack)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pack.tierName)
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                    if pack.isBestValue {
                        tag("Best value", color: .cozyOrange)
                    } else if pack.isMostPopular {
                        tag("Most popular", color: .freedomGreen)
                    }
                }
                Text("\(pack.treats) treats")
                    .font(.dhHeading)
                if let bonus = pack.bonusLabel {
                    Text(bonus)
                        .font(.dhCaption)
                        .foregroundStyle(Color.freedomGreen)
                }
            }

            Spacer(minLength: 8)

            Button {
                buy(pack)
            } label: {
                Group {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text(pack.displayPrice)
                            .font(.dhBodyBold)
                    }
                }
                .frame(minWidth: 72)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .background(anyBusy && !isBusy ? Color(.systemGray4) : Color.cozyOrange)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(anyBusy)
            .accessibilityLabel("Buy \(pack.treats) treats for \(pack.displayPrice)")
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.cozyOrange.opacity(highlighted ? 0.9 : 0), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    /// One, two or three bones on a warm tile — the tier at a glance.
    private func tierBadge(_ pack: TreatPack) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.cozyOrange.opacity(0.28), Color.cozyOrange.opacity(0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            switch pack.tierBones {
            case 1:
                Text("🦴").font(.system(size: 28))
            case 2:
                ZStack {
                    Text("🦴").font(.system(size: 24)).offset(x: -7, y: -6).rotationEffect(.degrees(-20))
                    Text("🦴").font(.system(size: 24)).offset(x: 7, y: 6).rotationEffect(.degrees(15))
                }
            default:
                ZStack {
                    Text("🦴").font(.system(size: 22)).offset(x: -10, y: 6).rotationEffect(.degrees(-25))
                    Text("🦴").font(.system(size: 22)).offset(x: 10, y: 6).rotationEffect(.degrees(25))
                    Text("🦴").font(.system(size: 22)).offset(y: -9)
                }
            }
        }
        .frame(width: 64, height: 64)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.dhBadge)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var footnote: some View {
        VStack(spacing: 6) {
            Text("Treats are added by our server once Apple confirms the purchase — usually within a few seconds.")
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

    // MARK: - Actions

    private func buy(_ pack: TreatPack) {
        Task {
            withAnimation {
                errorMessage = nil
                pendingMessage = nil
            }
            treatsBeforePurchase = treats
            do {
                let paid = try await purchases.buy(pack)
                if !paid {
                    treatsBeforePurchase = nil
                    return
                }
                startAwaitingCredit()
                #if DEBUG
                if purchases.isDemo {
                    // Stand in for the webhook: a short delay, then the credit
                    // lands on the profile exactly as the listener would deliver it.
                    try? await Task.sleep(for: .seconds(0.7))
                    authService.demoAddTreats(pack.treats)
                }
                #endif
            } catch {
                treatsBeforePurchase = nil
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    /// Paid, now waiting on the server. If the credit has not shown up on the
    /// listener by `creditTimeout`, stop spinning and re-enable the packs: the
    /// money is taken and the webhook will still credit it, so the message is
    /// reassuring rather than an error.
    private func startAwaitingCredit() {
        isAwaitingCredit = true
        creditWatchdog?.cancel()
        creditWatchdog = Task {
            try? await Task.sleep(for: creditTimeout)
            guard !Task.isCancelled, isAwaitingCredit else { return }
            treatsBeforePurchase = nil
            HapticService.shared.lightTap()
            withAnimation {
                isAwaitingCredit = false
                pendingMessage = "Your treats are on the way — check back in a minute."
            }
        }
    }
}
