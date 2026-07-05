//
//  DoghouseScene.swift
//  DogHouse
//

import SwiftUI

struct DoghouseScene: View {
    var isCurrentUser: Bool
    var partnerName: String
    var duration: TimeInterval
    var avatarId: String = "dog_1"
    var cosmetics: AvatarCosmetics = .none
    var onBellyRub: (() -> Void)? = nil

    @State private var showBellyRubBurst = false

    private var stage: DoghouseStage {
        DoghouseStage.stage(for: duration)
    }

    private var avatarMood: AvatarMood {
        switch stage {
        case .justArrived: .sad
        case .gettingHungry: .hungry
        case .rainy: .sad
        case .gettingDirty: .sad
        case .mouseFriend: .dramatic
        case .fullSurvival: .freezing
        }
    }

    @State private var rainOffsets: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: -150...150) }
    @State private var rainPhases: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: 0...1) }
    @State private var thunderFlash = false
    @State private var shiverOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Background — gets colder/darker with degradation
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Thunder flash overlay
            if thunderFlash {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.6))
            }

            VStack(spacing: 0) {
                // Rain layer
                if stage.showRain {
                    rainLayer
                }

                Spacer()

                // Doghouse structure
                ZStack {
                    // Cobwebs (stage 4+)
                    if stage.showDirty {
                        cobwebView
                            .offset(x: -55, y: -25)
                            .transition(.opacity)
                    }

                    // Roof
                    Triangle()
                        .fill(Color.dogHouseBrown)
                        .frame(width: 180, height: 68)
                        .offset(y: -15)

                    // House body
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.dogHouseBrown.opacity(0.8))
                        .frame(width: 160, height: 102)
                        .offset(y: 25)

                    // Door opening
                    UnevenRoundedRectangle(
                        topLeadingRadius: 26,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 26
                    )
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 64, height: 68)
                    .offset(y: 37)

                    // Avatar inside doghouse (with belly rub gesture)
                    ZStack {
                        AvatarView(
                            avatar: DogAvatar.avatar(for: avatarId),
                            mood: avatarMood,
                            size: 50,
                            cosmetics: cosmetics
                        )
                        .scaleEffect(showBellyRubBurst ? 1.14 : 1.0)
                        .animation(.spring(duration: 0.25), value: showBellyRubBurst)

                        if showBellyRubBurst {
                            HeartBurstView()
                                .scaleEffect(0.6)
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(x: shiverOffset, y: 30)
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

                    // "DOGHOUSE" label
                    Text("DOGHOUSE")
                        .font(.dhBadge)
                        .foregroundStyle(.white.opacity(0.6))
                        .offset(y: -2)

                    // Hunger thought bubble (stage 2+)
                    if stage.showHunger {
                        thoughtBubble
                            .offset(x: 50, y: 0)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Mouse friend (stage 5+)
                    if stage.showMouse {
                        mouseView
                            .offset(x: 80, y: 45)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                // Status text
                VStack(spacing: 4) {
                    Text(isCurrentUser ? "You're in the DogHouse 🐕" : "\(partnerName) is in the DogHouse 🐕")
                        .font(.dhBodyBold)
                        .foregroundStyle(.white)

                    Text(stage.statusText)
                        .font(.dhCaption)
                        .foregroundStyle(.white.opacity(0.7))
                        .italic()
                }
                .padding(.top, 16)

                Spacer()

                // Ground
                Rectangle()
                    .fill(Color.dogHouseBrown.opacity(0.4))
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
        }
        .frame(height: 320)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(partnerName) is in the doghouse. Stage: \(stage.statusText)")
        .animation(.easeInOut(duration: 0.8), value: stage)
        .onAppear {
            if stage.showShiver {
                startShivering()
            }
            if stage.showThunder {
                startThunder()
            }
        }
        .onChange(of: stage) { _, newStage in
            if newStage.showShiver {
                startShivering()
            }
            if newStage.showThunder {
                startThunder()
            }
        }
    }

    // MARK: - Background Colors

    private var backgroundColors: [Color] {
        switch stage {
        case .justArrived:
            [Color(red: 0.7, green: 0.75, blue: 0.85), Color(red: 0.55, green: 0.6, blue: 0.7)]
        case .gettingHungry:
            [Color(red: 0.65, green: 0.7, blue: 0.8), Color(red: 0.5, green: 0.55, blue: 0.65)]
        case .rainy:
            [Color(red: 0.55, green: 0.58, blue: 0.68), Color(red: 0.4, green: 0.45, blue: 0.55)]
        case .gettingDirty:
            [Color(red: 0.5, green: 0.52, blue: 0.6), Color(red: 0.35, green: 0.38, blue: 0.48)]
        case .mouseFriend:
            [Color(red: 0.45, green: 0.47, blue: 0.55), Color(red: 0.3, green: 0.33, blue: 0.43)]
        case .fullSurvival:
            [Color(red: 0.35, green: 0.37, blue: 0.47), Color(red: 0.2, green: 0.22, blue: 0.32)]
        }
    }

    // MARK: - Rain Layer

    private var rainLayer: some View {
        ZStack {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 2, height: 12)
                    .offset(x: rainOffsets[i])
                    .modifier(RainDrop(phase: rainPhases[i]))
            }
        }
        .frame(height: 80)
        .clipped()
    }

    // MARK: - Thought Bubble

    private var thoughtBubble: some View {
        ZStack {
            // Bubble
            Ellipse()
                .fill(Color.white.opacity(0.9))
                .frame(width: 40, height: 30)

            // Food emoji
            Text("🍕")
                .font(.system(size: 16))

            // Small bubbles
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 8, height: 8)
                .offset(x: -18, y: 15)

            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 5, height: 5)
                .offset(x: -14, y: 20)
        }
    }

    // MARK: - Mouse

    private var mouseView: some View {
        ZStack {
            // Body
            Ellipse()
                .fill(Color.gray)
                .frame(width: 20, height: 14)

            // Ears
            Circle()
                .fill(Color.gray.opacity(0.8))
                .frame(width: 8, height: 8)
                .offset(x: -6, y: -8)
            Circle()
                .fill(Color.gray.opacity(0.8))
                .frame(width: 8, height: 8)
                .offset(x: 6, y: -8)

            // Eyes
            Circle()
                .fill(Color.black)
                .frame(width: 3, height: 3)
                .offset(x: -3, y: -2)
            Circle()
                .fill(Color.black)
                .frame(width: 3, height: 3)
                .offset(x: 3, y: -2)

            // Nose
            Circle()
                .fill(Color.pink)
                .frame(width: 3, height: 3)
                .offset(y: 1)

            // Tail
            Path { path in
                path.move(to: CGPoint(x: 10, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: 22, y: -5),
                    control: CGPoint(x: 16, y: 5)
                )
            }
            .stroke(Color.gray, lineWidth: 1.5)
        }
    }

    // MARK: - Cobwebs

    private var cobwebView: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 15))
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 15, y: 20))
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 22))
            }
            .stroke(Color.gray.opacity(0.4), lineWidth: 0.8)
        }
        .frame(width: 25, height: 25)
    }

    // MARK: - Animations

    private func startShivering() {
        withAnimation(.linear(duration: 0.1).repeatForever(autoreverses: true)) {
            shiverOffset = 2
        }
    }

    private func startThunder() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 5...15)))
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.1)) {
                        thunderFlash = true
                    }
                }
                try? await Task.sleep(for: .milliseconds(150))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        thunderFlash = false
                    }
                }
            }
        }
    }
}

// MARK: - Rain Drop Animation Modifier

struct RainDrop: ViewModifier, Animatable {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: phase * 100)
            .opacity(1.0 - Double(phase) * 0.5)
            .onAppear {
                withAnimation(.linear(duration: Double.random(in: 0.6...1.2)).repeatForever(autoreverses: false)) {
                    // Animation drives the rain down
                }
            }
    }
}

#Preview("Stage 1 - Just Arrived") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 0)
}

#Preview("Stage 3 - Rainy") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 25000)
}

#Preview("Stage 6 - Full Survival") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 700000)
}
