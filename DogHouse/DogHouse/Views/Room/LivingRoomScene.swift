//
//  LivingRoomScene.swift
//  DogHouse

import SwiftUI

// Arch window shape: rectangle body with semicircle top
private struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(
            center: CGPoint(x: radius, y: radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct LivingRoomScene: View {
    var partnerName: String
    var isCurrentUser: Bool
    var level: RoomLevel
    var avatarId: String = "dog_1"
    var cosmetics: AvatarCosmetics = .none
    var onBellyRub: (() -> Void)? = nil
    /// Show the received rose bouquet next to the dog (fades after 5h)
    var showRoses: Bool = false

    @State private var showBellyRubBurst = false

    // The scene is decorative: it is assembled from emoji and shapes
    // that mean nothing read aloud. The accompanying status text
    // carries the same information for VoiceOver.
    var body: some View {
        ZStack {
            // Background wall — warm cream
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                // Wall area
                ZStack {
                    // Arched window (upper left) — sunset view at penthouse level
                    windowView
                        .offset(x: -68, y: -2)

                    // Shelf with decorations (level 6+)
                    if level.hasWallArt {
                        shelfView
                            .offset(x: 62, y: -8)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Paw print frame (level 6+)
                    if level.hasWallArt {
                        pawPrintFrameView
                            .offset(x: 58, y: 38)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Royal banner (level 10)
                    if level.hasBanner {
                        royalBannerView
                            .offset(x: 0, y: -34)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(height: 100)

                Spacer()

                // Main floor area
                ZStack {
                    // Red carpet (level 10) — sits under everything
                    if level.hasRedCarpet {
                        redCarpetView
                            .offset(y: 30)
                            .transition(.opacity)
                    }

                    // Round cream rug (level 4+)
                    if level.hasRug {
                        Ellipse()
                            .fill(Color(red: 0.96, green: 0.93, blue: 0.87))
                            .frame(width: 190, height: 52)
                            .offset(y: 20)
                            .transition(.opacity)
                    }

                    // Toy items on rug (level 4+)
                    if level.hasRug {
                        // Cardboard box
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.82, green: 0.68, blue: 0.45))
                            .frame(width: 18, height: 16)
                            .overlay(
                                Path { p in
                                    p.move(to: CGPoint(x: 9, y: 0))
                                    p.addLine(to: CGPoint(x: 9, y: 16))
                                }
                                .stroke(Color(red: 0.65, green: 0.52, blue: 0.32), lineWidth: 0.8)
                            )
                            .offset(x: -65, y: 22)
                            .transition(.opacity)

                        // Blue yarn ball
                        Circle()
                            .fill(Color(red: 0.42, green: 0.65, blue: 0.88))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color(red: 0.3, green: 0.52, blue: 0.78), lineWidth: 0.8)
                            )
                            .offset(x: -48, y: 28)
                            .transition(.opacity)
                    }

                    // Dog bed (level 2+) — replaces chair
                    if level.hasChair {
                        dogBedView
                            .offset(x: 62, y: 8)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Fireplace (level 5+)
                    if level.hasFireplace {
                        fireplaceView
                            .offset(x: -62, y: -8)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Tall plant (level 7+)
                    if level.hasPlants {
                        tallPlantView
                            .offset(x: -88, y: 4)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    // Aquarium (level 9+)
                    if level.hasAquarium {
                        aquariumView
                            .offset(x: 92, y: -18)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Floor lamp (level 9+)
                    if level.hasFloorLamp {
                        floorLampView
                            .offset(x: -110, y: -12)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    // Golden dog statue (level 10)
                    if level.hasGoldStatue {
                        goldStatueView
                            .offset(x: 100, y: 28)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Avatar (with belly rub gesture)
                    VStack(spacing: 4) {
                        ZStack {
                            avatarView
                                .scaleEffect(showBellyRubBurst ? 1.14 : 1.0)
                                .animation(.spring(duration: 0.25), value: showBellyRubBurst)

                            if showBellyRubBurst {
                                HeartBurstView()
                                    .allowsHitTesting(false)
                            }

                            if showRoses {
                                Text("💐")
                                    .font(.system(size: 32))
                                    .offset(x: 46, y: 14)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    guard onBellyRub != nil else { return }
                                    onBellyRub?()
                                    showBellyRubBurst = true
                                    Task {
                                        try? await Task.sleep(for: .seconds(1.6))
                                        showBellyRubBurst = false
                                    }
                                }
                        )

                        if level.hasBanner {
                            Text("👑 ROYALTY")
                                .font(.dhBadge)
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                        } else if level.hasLuxury {
                            Text("VIP")
                                .font(.dhBadge)
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                        }

                        if onBellyRub != nil {
                            Text("Hold to belly rub 🐾")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }
                }

                // Status text
                Text(isCurrentUser ? "You're home! 🏠" : "\(partnerName) is home 🏠")
                    .font(.dhHeading)
                    .foregroundStyle(Color.dogHouseBrown)
                    .padding(.top, 4)

                Spacer()

                // Wooden floor strip
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 0.52, blue: 0.32),
                                Color(red: 0.62, green: 0.44, blue: 0.26)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 40)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 0
                        )
                    )
            }

            // Luxury chandelier overlay (level 8)
            if level.hasLuxury {
                VStack {
                    Image(systemName: "chandelier")
                        .font(.system(size: 30))
                        .foregroundStyle(.yellow.opacity(0.8))
                        .shadow(color: .yellow.opacity(0.4), radius: 10)
                    Spacer()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(height: 320)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(partnerName) is home. Room level \(level.rawValue), \(level.name)")
        .animation(.spring(duration: 0.6), value: level)
    }

    // MARK: - Background Colors

    private var backgroundColors: [Color] {
        if level.hasLuxury {
            return [Color(red: 1.0, green: 0.97, blue: 0.90), Color(red: 0.98, green: 0.94, blue: 0.84)]
        } else if level.hasFireplace {
            return [Color(red: 0.99, green: 0.96, blue: 0.88), Color(red: 0.97, green: 0.92, blue: 0.82)]
        } else {
            return [Color(red: 0.98, green: 0.95, blue: 0.88), Color(red: 0.96, green: 0.91, blue: 0.82)]
        }
    }

    // MARK: - Window (arched)

    private var windowView: some View {
        ZStack {
            // Frame
            ArchShape()
                .fill(Color(red: 0.72, green: 0.55, blue: 0.38))
                .frame(width: 72, height: 76)

            // Sky interior — golden sunset at penthouse level
            ArchShape()
                .fill(
                    LinearGradient(
                        colors: level.hasSunsetWindow
                            ? [Color(red: 0.98, green: 0.68, blue: 0.38), Color(red: 0.95, green: 0.48, blue: 0.42)]
                            : [Color(red: 0.52, green: 0.80, blue: 0.97), Color(red: 0.76, green: 0.91, blue: 0.99)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 62, height: 66)

            // Sun — low and warm at sunset
            Circle()
                .fill(level.hasSunsetWindow
                      ? Color(red: 1.0, green: 0.72, blue: 0.30)
                      : Color(red: 1.0, green: 0.88, blue: 0.22))
                .shadow(color: Color(red: 1.0, green: 0.80, blue: 0.25).opacity(0.6), radius: 6)
                .frame(width: level.hasSunsetWindow ? 20 : 16, height: level.hasSunsetWindow ? 20 : 16)
                .offset(x: 12, y: level.hasSunsetWindow ? 4 : -18)

            // Cloud 1
            cloudShape
                .offset(x: -10, y: -14)

            // Cloud 2 (smaller)
            cloudShape
                .scaleEffect(0.65)
                .offset(x: 8, y: -10)

            // Green treetops
            Ellipse()
                .fill(Color(red: 0.32, green: 0.62, blue: 0.28))
                .frame(width: 30, height: 18)
                .offset(x: -16, y: 18)
            Ellipse()
                .fill(Color(red: 0.38, green: 0.68, blue: 0.32))
                .frame(width: 26, height: 16)
                .offset(x: 10, y: 20)
        }
        .frame(width: 72, height: 76)
        .clipShape(ArchShape())
    }

    private var cloudShape: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: 22, height: 9)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 12, height: 12)
                .offset(x: -4, y: -4)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 9, height: 9)
                .offset(x: 5, y: -3)
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        AvatarView(
            avatar: DogAvatar.avatar(for: avatarId),
            mood: level.hasLuxury ? .cozy : .happy,
            size: 95,
            cosmetics: cosmetics
        )
    }

    // MARK: - Dog Bed (replaces chair)

    private var dogBedView: some View {
        ZStack {
            // Bed outer rim (wicker-style)
            Ellipse()
                .fill(Color(red: 0.68, green: 0.50, blue: 0.32))
                .frame(width: 58, height: 38)

            // Bed inner cushion
            Ellipse()
                .fill(Color(red: 0.96, green: 0.91, blue: 0.86))
                .frame(width: 46, height: 28)
                .offset(y: 2)

            // Blanket (level 3+)
            if level.hasBlanket {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 34, height: 20)
                    .rotationEffect(.degrees(-6))
                    .offset(x: 5, y: 1)
                    .transition(.opacity)
            }

            // Pillow (level 4+)
            if level.hasPillow {
                Ellipse()
                    .fill(Color(red: 0.50, green: 0.72, blue: 0.90))
                    .frame(width: 22, height: 14)
                    .offset(x: -10, y: -2)
                    .transition(.scale)
            }
        }
    }

    // MARK: - Shelf

    private var shelfView: some View {
        ZStack(alignment: .bottom) {
            // Shelf board
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.65, green: 0.48, blue: 0.30))
                .frame(width: 82, height: 7)

            // Small plant on shelf
            VStack(spacing: 0) {
                ZStack {
                    Ellipse()
                        .fill(Color(red: 0.30, green: 0.58, blue: 0.28))
                        .frame(width: 16, height: 12)
                        .offset(y: -5)
                    Ellipse()
                        .fill(Color(red: 0.35, green: 0.64, blue: 0.32))
                        .frame(width: 12, height: 9)
                        .offset(x: -5, y: -10)
                    Ellipse()
                        .fill(Color(red: 0.35, green: 0.64, blue: 0.32))
                        .frame(width: 12, height: 9)
                        .offset(x: 5, y: -10)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.72, green: 0.52, blue: 0.30))
                        .frame(width: 12, height: 8)
                }
            }
            .offset(x: -28, y: -7)

            // Bone picture frame
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.94, green: 0.90, blue: 0.84))
                .frame(width: 18, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(red: 0.60, green: 0.44, blue: 0.26), lineWidth: 1.5)
                )
                .overlay(
                    Text("🦴")
                        .font(.system(size: 9))
                )
                .offset(x: 0, y: -10)

            // Books
            HStack(spacing: 1) {
                ForEach([
                    (Color(red: 0.40, green: 0.60, blue: 0.38), CGFloat(20)),
                    (Color(red: 0.72, green: 0.36, blue: 0.28), CGFloat(24)),
                    (Color(red: 0.42, green: 0.44, blue: 0.68), CGFloat(18))
                ], id: \.1) { color, height in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 7, height: height)
                }
            }
            .offset(x: 28, y: -7)
        }
    }

    // MARK: - Paw Print Frame

    private var pawPrintFrameView: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: 0.94, green: 0.90, blue: 0.84))
            .frame(width: 30, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.60, green: 0.44, blue: 0.26), lineWidth: 2)
            )
            .overlay(
                Text("🐾")
                    .font(.system(size: 14))
            )
    }

    // MARK: - Fireplace

    private var fireplaceView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.72, green: 0.68, blue: 0.64))
                .frame(width: 40, height: 45)

            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
            .fill(Color.black.opacity(0.7))
            .frame(width: 25, height: 25)
            .offset(y: 6)

            Circle()
                .fill(Color.orange.opacity(0.5))
                .frame(width: 18, height: 18)
                .offset(y: 6)
                .shadow(color: .orange.opacity(0.4), radius: 8)

            Image(systemName: "flame.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .offset(y: 4)
        }
    }

    // MARK: - Tall Plant

    private var tallPlantView: some View {
        VStack(spacing: 0) {
            ZStack {
                // Leaves
                Ellipse()
                    .fill(Color(red: 0.30, green: 0.58, blue: 0.26))
                    .frame(width: 20, height: 14)
                    .offset(x: -8, y: 0)
                    .rotationEffect(.degrees(-30))
                Ellipse()
                    .fill(Color(red: 0.36, green: 0.65, blue: 0.30))
                    .frame(width: 20, height: 14)
                    .offset(x: 8, y: 0)
                    .rotationEffect(.degrees(30))
                Ellipse()
                    .fill(Color(red: 0.32, green: 0.62, blue: 0.28))
                    .frame(width: 18, height: 13)
                    .offset(y: -8)
            }
            .frame(width: 30, height: 28)

            // Stem
            Rectangle()
                .fill(Color(red: 0.40, green: 0.30, blue: 0.18))
                .frame(width: 4, height: 18)

            // Pot
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 2,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 2
                )
                .fill(Color(red: 0.72, green: 0.50, blue: 0.30))
                .frame(width: 22, height: 18)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.62, green: 0.42, blue: 0.22))
                    .frame(width: 24, height: 5)
                    .offset(y: -7)
            }
        }
    }
}

// MARK: - Penthouse & Palace Assets

extension LivingRoomScene {

    // Aquarium on a stand (level 9+)
    var aquariumView: some View {
        VStack(spacing: 0) {
            ZStack {
                // Tank
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.45, green: 0.72, blue: 0.92).opacity(0.85),
                                     Color(red: 0.30, green: 0.55, blue: 0.82).opacity(0.9)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 46, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(red: 0.35, green: 0.30, blue: 0.25), lineWidth: 2)
                    )

                // Fish
                Text("🐠")
                    .font(.system(size: 11))
                    .offset(x: -8, y: -2)
                Text("🐟")
                    .font(.system(size: 9))
                    .offset(x: 9, y: 5)

                // Bubbles
                Circle().fill(Color.white.opacity(0.6)).frame(width: 3, height: 3).offset(x: 14, y: -8)
                Circle().fill(Color.white.opacity(0.5)).frame(width: 2, height: 2).offset(x: 16, y: -3)

                // Seaweed
                Path { p in
                    p.move(to: CGPoint(x: 8, y: 30))
                    p.addQuadCurve(to: CGPoint(x: 6, y: 18), control: CGPoint(x: 12, y: 24))
                }
                .stroke(Color(red: 0.25, green: 0.60, blue: 0.35), lineWidth: 2)
            }

            // Stand
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.50, green: 0.36, blue: 0.22))
                .frame(width: 50, height: 8)
        }
    }

    // Floor lamp with warm glow (level 9+)
    var floorLampView: some View {
        VStack(spacing: 0) {
            // Shade
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 4
            )
            .fill(Color(red: 0.96, green: 0.87, blue: 0.68))
            .frame(width: 26, height: 18)
            .shadow(color: Color.yellow.opacity(0.45), radius: 9, y: 4)

            // Pole
            Rectangle()
                .fill(Color(red: 0.40, green: 0.34, blue: 0.28))
                .frame(width: 3, height: 34)

            // Base
            Capsule()
                .fill(Color(red: 0.40, green: 0.34, blue: 0.28))
                .frame(width: 20, height: 5)
        }
    }

    // Golden dog statue on a pedestal (level 10)
    var goldStatueView: some View {
        VStack(spacing: 0) {
            // Golden dog (sitting silhouette built from shapes)
            ZStack {
                // Body
                Ellipse()
                    .fill(goldGradient)
                    .frame(width: 16, height: 20)
                    .offset(y: 5)
                // Head
                Circle()
                    .fill(goldGradient)
                    .frame(width: 12, height: 12)
                    .offset(y: -7)
                // Ear
                Ellipse()
                    .fill(goldGradient)
                    .frame(width: 5, height: 8)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -5, y: -12)
                Ellipse()
                    .fill(goldGradient)
                    .frame(width: 5, height: 8)
                    .rotationEffect(.degrees(24))
                    .offset(x: 5, y: -12)
            }
            .frame(width: 22, height: 32)
            .shadow(color: Color.yellow.opacity(0.5), radius: 5)

            // Pedestal
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.85, green: 0.72, blue: 0.38))
                    .frame(width: 26, height: 4)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.75, green: 0.62, blue: 0.30))
                    .frame(width: 20, height: 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.85, green: 0.72, blue: 0.38))
                    .frame(width: 30, height: 5)
            }
        }
    }

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.85, green: 0.65, blue: 0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // Red carpet runner (level 10)
    var redCarpetView: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 3,
            bottomLeadingRadius: 3,
            bottomTrailingRadius: 3,
            topTrailingRadius: 3
        )
        .fill(
            LinearGradient(
                colors: [Color(red: 0.72, green: 0.12, blue: 0.16), Color(red: 0.58, green: 0.08, blue: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .frame(width: 230, height: 34)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(red: 0.92, green: 0.78, blue: 0.35), lineWidth: 1.5)
                .frame(width: 222, height: 26)
        )
    }

    // Hanging royal banner (level 10)
    var royalBannerView: some View {
        VStack(spacing: 0) {
            // Rod
            Capsule()
                .fill(Color(red: 0.85, green: 0.70, blue: 0.32))
                .frame(width: 56, height: 3)

            // Banner cloth with notched bottom
            ZStack {
                BannerShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.65, green: 0.12, blue: 0.18), Color(red: 0.50, green: 0.08, blue: 0.14)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 34)

                Text("🐕")
                    .font(.system(size: 13))
                    .offset(y: -4)
            }
        }
    }
}

// Banner with a triangular notch cut from the bottom
private struct BannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width / 2, y: rect.height * 0.72))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Heart Burst Particle View (shared by Living Room and Doghouse scenes)

struct HeartBurstView: View {
    @State private var launched = false

    private let particles: [(symbol: String, x: CGFloat, yEnd: CGFloat, delay: Double, size: CGFloat)] = [
        ("❤️",  -24, -58, 0.00, 14),
        ("💕",    2, -68, 0.07, 12),
        ("💗",   24, -52, 0.04, 15),
        ("❤️",  -14, -72, 0.11, 11),
        ("💕",   16, -46, 0.15, 13),
        ("💗",    0, -62, 0.19, 10),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(particles.enumerated()), id: \.offset) { _, p in
                Text(p.symbol)
                    .font(.system(size: p.size))
                    .offset(x: p.x, y: launched ? p.yEnd : 0)
                    .opacity(launched ? 0 : 1)
                    .animation(.easeOut(duration: 1.0).delay(p.delay), value: launched)
            }
        }
        .onAppear { launched = true }
    }
}

#Preview("Level 1 - Bare") {
    LivingRoomScene(partnerName: "Alex", isCurrentUser: false, level: .bareBones)
}

#Preview("Level 4 - Rug & Bed") {
    LivingRoomScene(partnerName: "Alex", isCurrentUser: false, level: .pillowAndRug)
}

#Preview("Level 7 - Plants & Shelf") {
    LivingRoomScene(partnerName: "Alex", isCurrentUser: false, level: .plantsAndBooks)
}

#Preview("Level 8 - Luxury") {
    LivingRoomScene(partnerName: "Alex", isCurrentUser: false, level: .luxury)
}

#Preview("Level 9 - Penthouse") {
    LivingRoomScene(partnerName: "Alex", isCurrentUser: false, level: .penthouse)
}

#Preview("Level 10 - Palace") {
    LivingRoomScene(partnerName: "Alex", isCurrentUser: false, level: .palace)
}
