//
//  ShopTabView.swift
//  DogHouse
//
//  The dressing room. A live preview of whichever dog is being dressed sits
//  on top, the treat wallet (and the way into the treat store) under it,
//  then the wardrobe: one category at a time, every item previewed on the
//  chosen dog. Buying always spends MY treats; dressing my partner's dog
//  gifts the item into their wardrobe.
//

import SwiftUI

struct ShopTabView: View {
    @EnvironmentObject var authService: AuthService

    @State private var selectedCategory: CosmeticCategory = .necklace
    @State private var shopTarget: ShopTarget = .me
    @State private var errorMessage: String?
    @State private var busyItemId: String?
    @State private var showingTreatPacks = false
    @Namespace private var segmentNamespace

    @StateObject private var purchases = PurchaseService.shared

    private let shopService = ShopService()
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var profile: UserProfile? { authService.userProfile }
    private var partnerProfile: UserProfile? { authService.partnerProfile }
    private var treats: Int { profile?.effectiveTreats ?? 100 }
    private var partnerName: String { partnerProfile?.displayName ?? "Partner" }

    // Inventory of whoever is being dressed (buying always spends MY treats).
    private var owned: Set<String> {
        (shopTarget == .me ? profile?.ownedItemSet : partnerProfile?.ownedItemSet) ?? []
    }

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

    private var displayedName: String {
        shopTarget == .me
            ? (profile?.displayName ?? "My Dog")
            : partnerName
    }

    /// What the displayed dog currently has on, in wardrobe order.
    private var outfit: [CosmeticItem] {
        [displayedCosmetics.hat, displayedCosmetics.glasses, displayedCosmetics.necklace]
            .compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    dressingRoom
                    walletRow
                    if let err = errorMessage {
                        errorBanner(err)
                    }
                    categoryPicker
                    itemGrid
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .toolbar(.hidden, for: .navigationBar)
            .dhPageBackground()
            // With the navigation bar hidden nothing covers the status bar,
            // so scrolled cards ran under the clock. A strip of page colour
            // over the top safe area keeps them behind it.
            .overlay(alignment: .top) {
                Color.canvasTop
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 0)
            }
            .sheet(isPresented: $showingTreatPacks) {
                TreatPackSheet()
                    .environmentObject(authService)
            }
            .animation(.easeInOut(duration: 0.2), value: errorMessage)
        }
    }

    // MARK: - Header

    /// Page title with the treat store button on the same line. Drawn by
    /// hand instead of the navigation bar so the button can sit level with
    /// the title rather than above it.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Shop")
                .font(.largeTitle.bold())

            Spacer()

            // The treat store — only once in-app purchases are configured,
            // so a half-set-up build never shows a button that cannot work.
            if purchases.isAvailable {
                Button {
                    showingTreatPacks = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                        Text("Get treats")
                            .font(.dhCaptionBold)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.cozyOrange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.cozyOrange.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Get more treats")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Dressing room

    private var dressingRoom: some View {
        VStack(spacing: 14) {
            if partnerProfile != nil {
                targetSwitch
            }

            ZStack {
                // A warm spotlight behind the dog so the card reads as a
                // stage rather than a blank tile.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cozyOrange.opacity(0.28), Color.cozyOrange.opacity(0.0)],
                            center: .center, startRadius: 10, endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)
                    .offset(y: 6)

                Ellipse()
                    .fill(Color.dogHouseBrown.opacity(0.12))
                    .frame(width: 120, height: 22)
                    .offset(y: 70)

                AvatarView(
                    avatar: DogAvatar.avatar(for: displayedAvatarId),
                    mood: .happy,
                    size: 124,
                    cosmetics: displayedCosmetics
                )
                .id(shopTarget) // re-animate blink timers per dog
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .frame(height: 160)
            // Tall hats reach above the avatar's frame; keep them clear of
            // the stage's top edge.
            .padding(.top, 32)
            .frame(maxWidth: .infinity)
            // A warm stage, like the item tiles, so white pieces (Chef's
            // Hat) don't vanish into the white card.
            .background(Color.canvasTop, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 8) {
                Text(displayedName)
                    .font(.dhSubtitle)

                if outfit.isEmpty {
                    Text("Nothing on yet — pick something below")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(outfit, id: \.id) { item in
                            outfitChip(item)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.28), value: shopTarget)
    }

    private func outfitChip(_ item: CosmeticItem) -> some View {
        HStack(spacing: 4) {
            Text(item.emoji).font(.caption2)
            Text(item.name).font(.dhCaptionBold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tileTint(for: item).opacity(0.14))
        .clipShape(Capsule())
    }

    /// Me / Partner switch, drawn as a sliding pill so the swap feels like
    /// turning the mannequin rather than reloading the page.
    private var targetSwitch: some View {
        HStack(spacing: 2) {
            ForEach([ShopTarget.me, .partner], id: \.self) { target in
                let selected = target == shopTarget
                Button {
                    withAnimation(.snappy(duration: 0.28)) { shopTarget = target }
                    HapticService.shared.lightTap()
                } label: {
                    Text(target == .me ? "My Dog" : "\(partnerName)'s Dog")
                        .font(.dhCaptionBold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(selected ? .white : .primary)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.cozyOrange)
                                    .matchedGeometryEffect(id: "segment", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.cozyOrange.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Wallet

    private var walletRow: some View {
        // Balance pill. The tour points at this, so it keeps its anchor.
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
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .tourAnchor(.treatBalance)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text)
                .font(.dhCaption)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CosmeticCategory.allCases, id: \.self) { cat in
                    categoryChip(cat)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func categoryChip(_ cat: CosmeticCategory) -> some View {
        let isSelected = cat == selectedCategory
        let items = CosmeticItem.items(for: cat)
        let ownedCount = items.filter { owned.contains($0.id) }.count
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedCategory = cat }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.systemImage)
                Text(cat.displayName)
                    .fontWeight(.semibold)
                Text("\(ownedCount)/\(items.count)")
                    .font(.dhBadge)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.cozyOrange.opacity(0.12))
                    .clipShape(Capsule())
            }
            .font(.subheadline)
            .padding(.leading, 14).padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.cozyOrange : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
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
        let previewCosmetics = previewCosmeticsApplying(item)

        return VStack(spacing: 10) {
            // Preview, tinted with the item's own colour so the grid reads
            // as a rack of different things rather than identical tiles.
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [tileTint(for: item).opacity(0.22), item.accentColor.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                AvatarView(
                    avatar: DogAvatar.avatar(for: displayedAvatarId),
                    mood: .happy,
                    size: 78,
                    cosmetics: previewCosmetics,
                    blinks: false
                )
                // Sits low in the tile so hat tips clear the top edge.
                .padding(.top, 24)

                if isEquipped || isOwned {
                    statusBadge(isEquipped ? "Wearing" : "Owned",
                                color: isEquipped ? .cozyOrange : .freedomGreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(height: 140)

            // Name + price line
            VStack(spacing: 2) {
                Text(item.name)
                    .font(.dhBodyBold)
                    .lineLimit(1)
                if !isOwned {
                    Text("🦴 \(item.price)")
                        .font(.dhCaption)
                        .foregroundStyle(canAfford ? Color.secondary : Color.red.opacity(0.8))
                }
            }

            // Action
            if isBusy {
                ProgressView()
                    .frame(height: 34)
            } else if !isOwned {
                Button {
                    if canAfford {
                        busyItemId = item.id
                        performAction { try await purchase(item) }
                    } else if purchases.isAvailable {
                        showingTreatPacks = true
                    } else {
                        errorMessage = "You need \(item.price - treats) more treats for \(item.name). Time at home earns them."
                    }
                } label: {
                    Label(shopTarget == .partner ? "Gift" : "Buy",
                          systemImage: shopTarget == .partner ? "gift.fill" : "cart.fill")
                        .font(.dhCaptionBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(canAfford ? Color.cozyOrange : Color(.systemGray4))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if shopTarget == .partner {
                // Theirs already; whether their dog wears it is their call.
                Label("In their closet", systemImage: "hanger")
                    .font(.dhCaptionBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.secondary)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
            } else {
                Button {
                    HapticService.shared.lightTap()
                    if isEquipped {
                        performAction { try await unequip(item.category) }
                    } else {
                        performAction { try await equip(item) }
                    }
                } label: {
                    Label(isEquipped ? "Remove" : "Wear",
                          systemImage: isEquipped ? "xmark" : "checkmark")
                        .font(.dhCaptionBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isEquipped ? Color(.systemGray4) : Color.freedomGreen)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.cozyOrange, lineWidth: isEquipped ? 2 : 0)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .animation(.easeInOut(duration: 0.18), value: isEquipped)
        .animation(.easeInOut(duration: 0.18), value: isOwned)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.dhBadge)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    /// The colour an item's tile and outfit chip are tinted with. Near-white
    /// items (Chef's Hat, Bone Charm) would tint them white and vanish, so
    /// they get the page's warm brown instead.
    private func tileTint(for item: CosmeticItem) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(item.primaryColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.9 ? Color.dogHouseBrown : item.primaryColor
    }

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

    private func purchase(_ item: CosmeticItem) async throws {
        let forPartner = shopTarget == .partner
        #if DEBUG
        if AuthService.isDemo {
            try? await Task.sleep(for: .seconds(0.5))
            try authService.demoPurchase(item, forPartner: forPartner)
            HapticService.shared.success()
            return
        }
        #endif
        try await shopService.purchase(item, forPartner: forPartner)
        HapticService.shared.success()
    }

    // Only ever called on the Me tab: gifts are the partner's to wear.
    private func equip(_ item: CosmeticItem) async throws {
        #if DEBUG
        if AuthService.isDemo {
            authService.demoEquip(item.id, category: item.category)
            return
        }
        #endif
        try await shopService.equipOnSelf(item)
    }

    private func unequip(_ category: CosmeticCategory) async throws {
        #if DEBUG
        if AuthService.isDemo {
            authService.demoEquip(nil, category: category)
            return
        }
        #endif
        try await shopService.unequipOnSelf(category: category)
    }

    private func performAction(_ action: @escaping () async throws -> Void) {
        Task {
            errorMessage = nil
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
                HapticService.shared.error()
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
