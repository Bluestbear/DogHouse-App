//
//  TransitionAnimationView.swift
//  DogHouse
//
//  Full-screen dramatic animation overlays for Send and Release actions.
//

import SwiftUI

// MARK: - Send to DogHouse Animation

struct SendToDogHouseAnimation: View {
    /// Name of the partner being sent. These overlays are shown to the
    /// SENDER, so the text speaks about the partner — not "you".
    var partnerName: String = ""
    var onComplete: () -> Void

    private var headline: String {
        partnerName.isEmpty
            ? "SENT TO THE\nDOGHOUSE!"
            : "\(partnerName.uppercased()) WAS SENT\nTO THE DOGHOUSE!"
    }

    @State private var shakeOffset: CGFloat = 0
    @State private var showFlash = false
    @State private var trapdoorOpen = false
    @State private var avatarDropped = false
    @State private var showText = false
    @State private var textScale: CGFloat = 0.3
    @State private var backgroundOpacity: Double = 0

    var body: some View {
        ZStack {
            // Dark overlay
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // Flash overlay
            if showFlash {
                Color.red
                    .opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(spacing: 24) {
                Spacer()

                // Trapdoor visual
                ZStack {
                    // Floor panels
                    HStack(spacing: trapdoorOpen ? 80 : 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.dogHouseBrown)
                            .frame(width: 80, height: 16)
                            .rotationEffect(.degrees(trapdoorOpen ? -45 : 0), anchor: .leading)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.dogHouseBrown)
                            .frame(width: 80, height: 16)
                            .rotationEffect(.degrees(trapdoorOpen ? 45 : 0), anchor: .trailing)
                    }

                    // Avatar falling through
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.cozyOrange)
                        .offset(y: avatarDropped ? 300 : 0)
                        .opacity(avatarDropped ? 0 : 1)
                        .scaleEffect(avatarDropped ? 0.3 : 1.0)
                }

                Spacer()

                // "[NAME] WAS SENT TO THE DOGHOUSE!" text
                if showText {
                    VStack(spacing: 8) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.red)

                        Text(headline)
                            .font(.dhDisplay)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                    }
                    .scaleEffect(textScale)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()
            }
        }
        .offset(x: shakeOffset)
        .onAppear {
            runSequence()
        }
    }

    private func runSequence() {
        // Phase 1: Screen darkens
        withAnimation(.easeIn(duration: 0.3)) {
            backgroundOpacity = 0.7
        }

        // Phase 2-6: Sequential animation steps
        Task {
            // Phase 2: Earthquake shake (0.3s - 1.0s)
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                HapticService.shared.heavyImpact()
            }
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(60))
                await MainActor.run {
                    withAnimation(.linear(duration: 0.06)) {
                        shakeOffset = CGFloat.random(in: -12...12)
                    }
                    HapticService.shared.rigidImpact()
                }
            }
            await MainActor.run {
                withAnimation(.linear(duration: 0.05)) {
                    shakeOffset = 0
                }
            }

            // Phase 3: Red flash + trapdoor opens
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.15)) {
                    showFlash = true
                }
                HapticService.shared.heavyImpact()
            }
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    showFlash = false
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    trapdoorOpen = true
                }
            }

            // Phase 4: Avatar drops through
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.5)) {
                    avatarDropped = true
                }
                HapticService.shared.error()
            }

            // Phase 5: "SENT TO THE DOGHOUSE!" text
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                    showText = true
                    textScale = 1.0
                }
            }

            // Phase 6: Hold, then dismiss
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    backgroundOpacity = 0
                    showText = false
                }
            }
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                onComplete()
            }
        }
    }
}

// MARK: - Release from DogHouse Animation

struct ReleaseFromDogHouseAnimation: View {
    /// Name of the partner being released. Shown to the SENDER when they
    /// let their partner out, so the text speaks about the partner.
    var partnerName: String = ""
    var onComplete: () -> Void

    private var headline: String {
        partnerName.isEmpty ? "YOU'RE FREE!" : "\(partnerName.uppercased()) IS FREE!"
    }

    private var subline: String {
        partnerName.isEmpty ? "Welcome home!" : "You let them out — welcome home, \(partnerName)!"
    }

    @State private var doorBurst = false
    @State private var showSunburst = false
    @State private var showAvatar = false
    @State private var avatarScale: CGFloat = 0.3
    @State private var showText = false
    @State private var textScale: CGFloat = 0.3
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var backgroundOpacity: Double = 0
    @State private var sunburstRotation: Double = 0

    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // Sunburst
            if showSunburst {
                sunburstView
                    .transition(.scale.combined(with: .opacity))
            }

            // Confetti layer
            ForEach(confettiParticles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }

            VStack(spacing: 20) {
                Spacer()

                // Door burst visual
                ZStack {
                    if !doorBurst {
                        // Closed door
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.dogHouseBrown)
                            .frame(width: 100, height: 140)
                            .overlay(
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 12, height: 12)
                                    .offset(x: 30, y: 0)
                            )
                    } else {
                        // Burst open door halves
                        HStack(spacing: 100) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.dogHouseBrown)
                                .frame(width: 50, height: 140)
                                .rotationEffect(.degrees(-30), anchor: .leading)
                                .opacity(0.6)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.dogHouseBrown)
                                .frame(width: 50, height: 140)
                                .rotationEffect(.degrees(30), anchor: .trailing)
                                .opacity(0.6)
                        }
                    }

                    // Avatar emerging
                    if showAvatar {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Color.freedomGreen)
                            .scaleEffect(avatarScale)
                            .transition(.scale)
                    }
                }

                // "[NAME] IS FREE!" text
                if showText {
                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.dhDisplay)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(Color.freedomGreen)
                            .padding(.horizontal, 16)

                        Text(subline)
                            .font(.dhSubtitle)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 24)
                    }
                    .scaleEffect(textScale)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()
            }
        }
        .onAppear {
            runSequence()
        }
    }

    private var sunburstView: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(Color.freedomGreen.opacity(0.15))
                    .frame(width: 4, height: 300)
                    .rotationEffect(.degrees(Double(i) * 30 + sunburstRotation))
            }
        }
        .rotationEffect(.degrees(sunburstRotation))
    }

    private func runSequence() {
        // Phase 1: Screen darkens
        withAnimation(.easeIn(duration: 0.3)) {
            backgroundOpacity = 0.8
        }

        Task {
            // Phase 2: Door rattles, then bursts open
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                HapticService.shared.heavyImpact()
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                    doorBurst = true
                }
            }

            // Phase 3: Sunburst + avatar emerges
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSunburst = true
                }
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    sunburstRotation = 360
                }
                withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
                    showAvatar = true
                    avatarScale = 1.2
                }
                HapticService.shared.success()
            }

            // Phase 4: Confetti explosion
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                spawnConfetti()
            }

            // Phase 5: "YOU'RE FREE!" text
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                    showText = true
                    textScale = 1.0
                }
                HapticService.shared.success()
            }

            // Phase 6: Hold, then dismiss
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.5)) {
                    backgroundOpacity = 0
                    showText = false
                    showSunburst = false
                    showAvatar = false
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                onComplete()
            }
        }
    }

    private func spawnConfetti() {
        let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink, .mint]
        confettiParticles = (0..<40).map { i in
            ConfettiParticle(
                id: i,
                x: 0,
                y: 0,
                color: colors[i % colors.count],
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
        }

        // Animate each particle outward
        for i in 0..<confettiParticles.count {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 100...250)
            let targetX = cos(angle) * distance
            let targetY = sin(angle) * distance - 50

            withAnimation(.easeOut(duration: Double.random(in: 0.8...1.5))) {
                confettiParticles[i].x = targetX
                confettiParticles[i].y = targetY
            }

            withAnimation(.easeIn(duration: 1.5).delay(0.5)) {
                confettiParticles[i].opacity = 0
            }
        }
    }
}

// MARK: - Confetti Particle

struct ConfettiParticle: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var color: Color
    var size: CGFloat
    var opacity: Double
}

// MARK: - Previews

#Preview("Send Animation") {
    SendToDogHouseAnimation {
    }
}

#Preview("Release Animation") {
    ReleaseFromDogHouseAnimation {
    }
}
