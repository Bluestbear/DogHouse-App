//
//  ShopTabView.swift
//  DogHouse
//

import SwiftUI

struct ShopTabView: View {
    @EnvironmentObject var authService: AuthService

    @State private var selectedCategory: CosmeticCategory = .necklace
    @State private var shopTarget: ShopTarget = .me
    @State private var errorMessage: String?
    @State private var busyItemId: String?

    private let shopService = ShopService()
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var profile: UserProfile? { authService.userProfile }
    private var partnerProfile: UserProfile? { authService.partnerProfile }
    private var treats: Int { profile?.effectiveTreats ?? 100 }
    private var owned: Set<String> { profile?.ownedItemSet ?? [] }

    private var myCosmetics: AvatarCosmetics {
        AvatarCosmetics(equippedItemIds: profile?.equippedItemIds ?? [:])
    }

    private var partnerCosmetics: AvatarCosmetics {
        AvatarCosmetics(equippedItemIds: partnerProfile?.equippedItemIds ?? [:])
    }

    private var displayedCosmetics: AvatarCosmetics {
        shopTarget == .me ? myCosmetics : partnerCosmetics
    }

    private var displayedAvatarId: String {
        shopTarget == .me
            ? (profile?.avatarId ?? "dog_1")
            : (partnerProfile?.avatarId ?? "dog_1")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    targetPicker
                    categoryPicker
                    itemGrid
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Avatar preview
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

                VStack(spacing: 8) {
                    AvatarView(
                        avatar: DogAvatar.avatar(for: displayedAvatarId),
                        mood: .happy,
                        size: 110,
                        cosmetics: displayedCosmetics
                    )
                    Text(shopTarget == .me
                         ? (profile?.displayName ?? "My Dog")
                         : (partnerProfile?.displayName ?? "Partner's Dog"))
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }
            .padding(.horizontal, 20)

            // Treat balance
            HStack(spacing: 6) {
                Text("🦴")
                    .font(.title3)
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

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Target Picker (Me / Partner)

    @ViewBuilder
    private var targetPicker: some View {
        if partnerProfile != nil {
            Picker("Dress", selection: $shopTarget) {
                Text("My Dog").tag(ShopTarget.me)
                Text("\(partnerProfile?.displayName ?? "Partner")'s Dog").tag(ShopTarget.partner)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CosmeticCategory.allCases, id: \.self) { cat in
                    categoryChip(cat)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryChip(_ cat: CosmeticCategory) -> some View {
        let isSelected = cat == selectedCategory
        return Button { selectedCategory = cat } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.systemImage)
                Text(cat.displayName)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.cozyOrange : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: selectedCategory)
    }

    // MARK: - Item Grid

    private var itemGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(CosmeticItem.items(for: selectedCategory)) { item in
                itemCard(item)
            }
        }
        .padding(.horizontal, 16)
    }

    private func itemCard(_ item: CosmeticItem) -> some View {
        let isOwned    = owned.contains(item.id)
        let canAfford  = treats >= item.price
        let isEquipped = isEquippedOnTarget(item)
        let isBusy     = busyItemId == item.id

        // Build cosmetics with just this one item for the preview
        let previewCosmetics = previewCosmeticsApplying(item)

        return VStack(spacing: 10) {
            // Avatar preview
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isEquipped
                          ? Color.cozyOrange.opacity(0.12)
                          : Color(.tertiarySystemGroupedBackground))

                VStack(spacing: 4) {
                    AvatarView(
                        avatar: DogAvatar.avatar(for: displayedAvatarId),
                        mood: .happy,
                        size: 72,
                        cosmetics: previewCosmetics
                    )
                    .padding(.top, 10)

                    Text(item.emoji)
                        .font(.caption)
                }
                .padding(.bottom, 8)

                if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.cozyOrange)
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(height: 130)

            // Name
            Text(item.name)
                .font(.subheadline.bold())
                .lineLimit(1)

            // Actions
            if isBusy {
                ProgressView()
                    .frame(height: 32)
            } else if !isOwned {
                // Buy button
                Button {
                    performAction { try await shopService.purchase(item, currentTreats: treats) }
                } label: {
                    Label("\(item.price) 🦴", systemImage: "cart")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(canAfford ? Color.cozyOrange : Color(.systemGray4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!canAfford)
            } else {
                // Wear / Remove
                Button {
                    if isEquipped {
                        performAction { try await unequipOnTarget(item.category) }
                    } else {
                        performAction { try await equipOnTarget(item) }
                    }
                } label: {
                    Text(isEquipped ? "Remove" : "Wear")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(isEquipped ? Color(.systemGray4) : Color.freedomGreen)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isEquipped)
    }

    // MARK: - Helpers

    private func isEquippedOnTarget(_ item: CosmeticItem) -> Bool {
        let equipped = shopTarget == .me ? myCosmetics : partnerCosmetics
        switch item.category {
        case .necklace: return equipped.necklaceId == item.id
        case .hat:      return equipped.hatId == item.id
        case .glasses:  return equipped.glassesId == item.id
        }
    }

    // Preview cosmetics: show the item on the target's OTHER cosmetics
    private func previewCosmeticsApplying(_ item: CosmeticItem) -> AvatarCosmetics {
        var c = displayedCosmetics
        switch item.category {
        case .necklace: c.necklaceId = item.id
        case .hat:      c.hatId      = item.id
        case .glasses:  c.glassesId  = item.id
        }
        return c
    }

    private func equipOnTarget(_ item: CosmeticItem) async throws {
        if shopTarget == .me {
            try await shopService.equipOnSelf(item)
        } else if let pid = partnerProfile?.id {
            try await shopService.equipOnPartner(item, partnerId: pid)
        }
    }

    private func unequipOnTarget(_ category: CosmeticCategory) async throws {
        if shopTarget == .me {
            try await shopService.unequipOnSelf(category: category)
        } else if let pid = partnerProfile?.id {
            try await shopService.unequipOnPartner(category: category, partnerId: pid)
        }
    }

    private func performAction(_ action: @escaping () async throws -> Void) {
        Task {
            withAnimation { errorMessage = nil }
            do {
                try await action()
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
            busyItemId = nil
        }
    }
}

// MARK: - Shop Target

private enum ShopTarget: Hashable {
    case me, partner
}

// MARK: - Preview

#Preview {
    ShopTabView()
        .environmentObject(AuthService())
}
