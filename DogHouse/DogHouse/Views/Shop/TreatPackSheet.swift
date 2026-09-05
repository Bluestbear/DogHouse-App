//
//  TreatPackSheet.swift
//  DogHouse
//
//  Buy treats with real money. Presented from the Shop tab's balance pill.
//
//  Nothing here credits treats. A completed purchase flips to a waiting state
//  and the balance arrives on AuthService's user-document listener once the
//  RevenueCat webhook has credited it server-side.
//

import SwiftUI

struct TreatPackSheet: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var purchases = PurchaseService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    /// Balance when the purchase started, so we can tell when the credit lands.
    @State private var treatsBeforePurchase: Int?

    private var treats: Int { authService.userProfile?.effectiveTreats ?? 100 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    balanceHeader

                    if purchases.isLoading && purchases.packs.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if purchases.packs.isEmpty {
                        EmptyStateView(
                            icon: "bag",
                            title: "No packs available",
                            subtitle: "Treat packs couldn't be loaded right now. Please try again later."
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(purchases.packs) { pack in
                            packCard(pack)
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("Get Treats")
            .navigationBarTitleDisplayMode(.inline)
            .dhPageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await purchases.loadPacks() }
        // The credit arrives asynchronously from the server — watch the
        // balance rather than assuming the purchase call's return means treats.
        .onChange(of: treats) { _, newValue in
            if let before = treatsBeforePurchase, newValue > before {
                treatsBeforePurchase = nil
                purchases.creditSettled()
            }
        }
    }

    // MARK: - Header

    private var balanceHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("🦴").font(.title3)
                Text("\(treats)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.cozyOrange)
                Text("treats")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

            if purchases.isAwaitingCredit {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Adding your treats…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: purchases.isAwaitingCredit)
        .padding(.top, 8)
    }

    // MARK: - Pack card

    private func packCard(_ pack: TreatPack) -> some View {
        let isBusy = purchases.purchasingProductId == pack.id
        let anyBusy = purchases.purchasingProductId != nil

        return HStack(spacing: 14) {
            Text("🦴")
                .font(.system(size: 34))
                .frame(width: 56, height: 56)
                .background(Color.cozyOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(pack.treats) treats")
                    .font(.headline)
                if pack.isBestValue {
                    Text("Best value")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.freedomGreen.opacity(0.18))
                        .foregroundStyle(Color.freedomGreen)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Button {
                buy(pack)
            } label: {
                Group {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text(pack.displayPrice).font(.subheadline.bold())
                    }
                }
                .frame(minWidth: 74)
                .padding(.vertical, 9)
                .background(anyBusy ? Color(.systemGray4) : Color.cozyOrange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(anyBusy)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var footnote: some View {
        Text("Treats are added by our server once Apple confirms the purchase — usually within a few seconds.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }

    // MARK: - Actions

    private func buy(_ pack: TreatPack) {
        Task {
            withAnimation { errorMessage = nil }
            treatsBeforePurchase = treats
            do {
                let paid = try await purchases.buy(pack)
                if !paid { treatsBeforePurchase = nil }
            } catch {
                treatsBeforePurchase = nil
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }
}
