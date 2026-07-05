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
        case .cloudsGathering: .sad
        case .rainy: .sad
        case .gettingDirty: .sad
        case .mouseFriend: .dramatic
        case .stormyNight: .dramatic
        case .fullSurvival: .freezing
        }
    }

    @State private var rainOffsets: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: -150...150) }
    @State private var rainPhases: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: 0...1) }
    @State private var thunderFlash = false
    @State private var shiverOffset: CGFloat = 0
    @State private var cloudDrift: CGFloat = 0
    @State private var flyPhase = false
    @State private var leafDrift = false

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

            // Dark clouds drifting across the sky (stage 3+)
            if stage.showClouds {
                darkCloudsLayer
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                // Rain / snow layer
                if stage.showRain {
                    rainLayer
                }

                Spacer()

                // Doghouse structure
                ZStack {
                    // Cobwebs
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

                    // Patched roof plank (stage 6+) — the house itself decays
                    if stage.showRoofPatch {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 0.45, green: 0.32, blue: 0.18))
                            .frame(width: 34, height: 9)
                            .rotationEffect(.degrees(-22))
                            .overlay(
                                HStack(spacing: 5) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Circle()
                                            .fill(Color.black.opacity(0.55))
                                            .frame(width: 2, height: 2)
                                    }
                                }
                                .rotationEffect(.degrees(-22))
                            )
                            .offset(x: 38, y: -32)
                            .transition(.opacity)
                    }

                    // Icicles hanging from the roof edge (stage 8)
                    if stage.showIcicles {
                        icicleRow
                            .offset(y: 14)
                            .transition(.opacity)
                    }

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

                    // Empty food bowl (stage 2+)
                    if stage.showHunger {
                        emptyBowlView
                            .offset(x: -78, y: 62)
                            .transition(.opacity)
                    }

                    // Rain puddles on the ground (stage 4+)
                    if stage.showPuddles {
                        puddleView
                            .offset(x: 62, y: 72)
                            .transition(.opacity)
                        puddleView
                            .scaleEffect(0.6)
                            .offset(x: -48, y: 78)
                            .transition(.opacity)
                    }

                    // Buzzing flies (stage 5+)
                    if stage.showFlies {
                        fliesView
                            .offset(x: -70, y: 30)
                            .transition(.opacity)
                    }

                    // Mouse friend (stage 6+)
                    if stage.showMouse {
                        mouseView
                            .offset(x: 80, y: 45)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Wind-blown leaves (stage 7+)
                    if stage.showLeaves {
                        leafView
                            .offset(x: leafDrift ? 95 : -95, y: leafDrift ? 58 : 38)
                            .transition(.opacity)
                        leafView
                            .scaleEffect(0.7)
                            .rotationEffect(.degrees(120))
                            .offset(x: leafDrift ? 80 : -110, y: leafDrift ? 30 : 55)
                            .transition(.opacity)
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
        .onAppear { startStageAnimations(stage) }
        .onChange(of: stage) { _, newStage in
            startStageAnimations(newStage)
        }
    }

    private func startStageAnimations(_ stage: DoghouseStage) {
        if stage.showShiver { startShivering() }
        if stage.showThunder { startThunder() }
        if stage.showClouds {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: true)) {
                cloudDrift = 40
            }
        }
        if stage.showFlies {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                flyPhase = true
            }
        }
        if stage.showLeaves {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: false)) {
                leafDrift = true
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
        case .cloudsGathering:
            [Color(red: 0.6, green: 0.63, blue: 0.73), Color(red: 0.45, green: 0.5, blue: 0.6)]
        case .rainy:
            [Color(red: 0.55, green: 0.58, blue: 0.68), Color(red: 0.4, green: 0.45, blue: 0.55)]
        case .gettingDirty:
            [Color(red: 0.5, green: 0.52, blue: 0.6), Color(red: 0.35, green: 0.38, blue: 0.48)]
        case .mouseFriend:
            [Color(red: 0.45, green: 0.47, blue: 0.55), Color(red: 0.3, green: 0.33, blue: 0.43)]
        case .stormyNight:
            [Color(red: 0.28, green: 0.29, blue: 0.4), Color(red: 0.16, green: 0.17, blue: 0.28)]
        case .fullSurvival:
            [Color(red: 0.35, green: 0.37, blue: 0.47), Color(red: 0.2, green: 0.22, blue: 0.32)]
        }
    }

    // MARK: - Rain / Snow Layer

    private var rainLayer: some View {
        ZStack {
            ForEach(0..<20, id: \.self) { i in
                Group {
                    if stage.showSnow {
                        // Snowflakes at the freezing stage
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 5, height: 5)
                    } else {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 2, height: 12)
                    }
                }
                .offset(x: rainOffsets[i])
                .modifier(RainDrop(phase: rainPhases[i]))
            }
        }
        .frame(height: 80)
        .clipped()
    }

    // MARK: - Dark Clouds

    private var darkCloudsLayer: some View {
        VStack {
            HStack(spacing: 30) {
                stormCloud.offset(x: cloudDrift * 0.6)
                stormCloud.scaleEffect(0.75).offset(x: -cloudDrift, y: 6)
                stormCloud.scaleEffect(0.9).offset(x: cloudDrift * 0.4, y: -3)
            }
            .padding(.top, 14)
            Spacer()
        }
    }

    private var stormCloud: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.32, green: 0.34, blue: 0.42).opacity(0.85))
                .frame(width: 52, height: 18)
            Circle()
                .fill(Color(red: 0.30, green: 0.32, blue: 0.40).opacity(0.85))
                .frame(width: 26, height: 26)
                .offset(x: -10, y: -8)
            Circle()
                .fill(Color(red: 0.36, green: 0.38, blue: 0.46).opacity(0.85))
                .frame(width: 20, height: 20)
                .offset(x: 12, y: -6)
        }
    }

    // MARK: - Empty Food Bowl

    private var emptyBowlView: some View {
        ZStack {
            // Bowl
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 9,
                topTrailingRadius: 2
            )
            .fill(Color(red: 0.75, green: 0.28, blue: 0.24))
            .frame(width: 30, height: 14)

            // Empty inside
            Ellipse()
                .fill(Color.black.opacity(0.35))
                .frame(width: 24, height: 5)
                .offset(y: -5)

            // Bone print on the bowl
            Text("🦴")
                .font(.system(size: 7))
                .opacity(0.85)
                .offset(y: 2)
        }
    }

    // MARK: - Puddle

    private var puddleView: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.7),
                             Color(red: 0.45, green: 0.52, blue: 0.68).opacity(0.5)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 42, height: 10)
            .overlay(
                Ellipse()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 20, height: 4)
                    .offset(x: -6, y: -1)
            )
    }

    // MARK: - Flies

    private var fliesView: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 3, height: 3)
                    .offset(
                        x: CGFloat(i * 8 - 8) + (flyPhase ? 3 : -3),
                        y: CGFloat((i % 2) * 6 - 3) + (flyPhase ? -4 : 4)
                    )
            }
        }
    }

    // MARK: - Leaf

    private var leafView: some View {
        Ellipse()
            .fill(Color(red: 0.62, green: 0.42, blue: 0.18))
            .frame(width: 10, height: 6)
            .rotationEffect(.degrees(leafDrift ? 300 : 0))
    }

    // MARK: - Icicles

    private var icicleRow: some View {
        HStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { i in
                Triangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color(red: 0.75, green: 0.88, blue: 0.98).opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 6, height: i % 2 == 0 ? 14 : 9)
                    .rotationEffect(.degrees(180))
            }
        }
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

#Preview("Stage 3 - Clouds Gathering") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 12000)
}

#Preview("Stage 7 - Stormy Night") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 450000)
}

#Preview("Stage 8 - Full Survival") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 700000)
}
