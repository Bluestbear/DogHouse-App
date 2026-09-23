//
//  TransitionAnimationView.swift
//  DogHouse
//
//  Full-screen dramatic animation overlays for Send and Release actions.
//

import SwiftUI

// MARK: - Send to DogHouse Animation

/// The partner's dog sits in the middle of the screen, an old hiking boot
/// swings in from the left, winds up, and punts it spinning out past the
/// right edge of the screen. Every element is a pure function
/// of elapsed time (see `KickTimeline`), driven by one `TimelineView` clock,
/// so the feel is tuned by editing the constants there.
struct SendToDogHouseAnimation: View {
    /// Name of the partner being sent. These overlays are shown to the
    /// SENDER, so the text speaks about the partner — not "you".
    var partnerName: String = ""
    /// The partner's dog, so the one that gets kicked is theirs.
    var avatarId: String = "dog_1"
    var cosmetics: AvatarCosmetics = .none
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = KickClock()

    private typealias T = KickTimeline

    private var headline: String {
        partnerName.isEmpty
            ? "SENT TO THE\nDOGHOUSE!"
            : "\(partnerName.uppercased()) WAS SENT\nTO THE DOGHOUSE!"
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = clock.advance(to: context.date)
            GeometryReader { geo in
                scene(t: t, size: geo.size)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onAppear {
            scheduleCues()
        }
    }

    // MARK: Scene

    private func scene(t: Double, size: CGSize) -> some View {
        // Where the dog sits; the boot's toe lands on the back of it.
        let dogCenter = CGPoint(x: size.width / 2 + T.dogOffsetX, y: size.height * 0.46)
        let contact = CGPoint(x: dogCenter.x - T.dogSize * 0.32, y: dogCenter.y + T.dogSize * 0.18)
        let fadeOut = 1 - T.easeInOut(T.progress(t, T.fadeOut))

        return ZStack {
            Color.black.opacity(0.7 * T.progress(t, T.dimIn) * fadeOut)

            if reduceMotion {
                calmDog(t: t, center: dogCenter)
            } else {
                boot(t: t, contact: contact, width: size.width)
                impactBurst(t: t, at: contact)
                flyingDog(t: t, from: dogCenter, size: size)
            }

            headlineView(t: t)
                .position(x: size.width / 2, y: size.height * 0.46)
                .opacity(fadeOut)
        }
        .offset(x: reduceMotion ? 0 : shake(t))
    }

    // MARK: Boot

    private func boot(t: Double, contact: CGPoint, width: CGFloat) -> some View {
        let w = T.bootWidth
        let h = w * T.bootAspect
        // Keep the toe on the contact point when the swing angle is zero.
        let center = CGPoint(
            x: contact.x - (T.toe.x - 0.5) * w,
            y: contact.y - (T.toe.y - 0.5) * h
        )
        // Slides in from and back out to off-screen left.
        let offscreen = -(center.x + w)
        let slide = offscreen * (1 - T.easeOut(T.progress(t, T.bootIn)))
            + offscreen * T.easeIn(T.progress(t, T.bootOut))

        return FlatBootView()
            .frame(width: w, height: h)
            // Rotate before positioning so the pivot is the hip above the
            // boot, not the screen centre (see the tour-ring drift bug).
            .rotationEffect(.degrees(bootAngle(t)), anchor: T.hip)
            .position(x: center.x + slide, y: center.y)
    }

    /// Positive is clockwise, which swings the sole back (left) around the hip.
    private func bootAngle(_ t: Double) -> Double {
        if t < T.windUp.lowerBound { return T.restAngle }
        if t < T.swing.lowerBound {
            return T.restAngle + (T.windUpAngle - T.restAngle) * T.easeInOut(T.progress(t, T.windUp))
        }
        if t < T.contact {
            // Accelerate into the dog.
            return T.windUpAngle * (1 - T.easeIn(T.progress(t, T.swing)))
        }
        if t < T.bootOut.lowerBound {
            return T.followAngle * T.easeOut(T.progress(t, T.follow))
        }
        return T.followAngle + (T.restAngle - T.followAngle) * T.progress(t, T.bootOut)
    }

    // MARK: Dog

    private func dog(mood: AvatarMood) -> some View {
        AvatarView(
            avatar: DogAvatar.avatar(for: avatarId),
            mood: mood,
            size: T.dogSize,
            cosmetics: cosmetics
        )
    }

    private func flyingDog(t: Double, from center: CGPoint, size: CGSize) -> some View {
        let appear = T.easeOutBack(T.progress(t, T.dogIn))
        let p = T.progress(t, T.flight)
        // Straight out past the right edge, lofted on a shallow arc.
        let exitX = size.width + T.dogSize
        let x = center.x + (exitX - center.x) * p
        let y = center.y - T.flightLift * sin(p * .pi * 0.75)
        // A nervous shiver once the boot starts winding up.
        let shiver = (t > T.windUp.lowerBound && t < T.contact) ? sin(t * 90) * 2.5 : 0
        let scale = appear

        return dog(mood: t < T.windUp.lowerBound ? .happy : .dramatic)
            .scaleEffect(scale)
            .rotationEffect(.degrees(T.flightSpin * T.easeOut(p)))
            .position(x: x + shiver, y: y)
    }

    /// Reduce Motion: no boot, no spin; the dog simply fades away.
    private func calmDog(t: Double, center: CGPoint) -> some View {
        dog(mood: .dramatic)
            .position(center)
            .opacity(T.progress(t, T.dogIn) * (1 - T.progress(t, T.flight)))
    }

    // MARK: Effects

    /// Comic "whack" lines radiating from where the toe lands.
    private func impactBurst(t: Double, at point: CGPoint) -> some View {
        let p = T.progress(t, T.burst)
        let visible = p > 0 && p < 1
        return ZStack {
            Circle()
                .fill(.white)
                .frame(width: 70, height: 70)
                .scaleEffect(0.4 + 1.2 * T.easeOut(p))
                .opacity(visible ? 0.55 * (1 - p) : 0)
            ForEach(0..<9, id: \.self) { i in
                Capsule()
                    .fill(i.isMultiple(of: 2) ? Color.white : Color.cozyOrange)
                    .frame(width: 5, height: 22)
                    .offset(y: -(28 + 46 * T.easeOut(p)))
                    .rotationEffect(.degrees(Double(i) * 40 + 10))
            }
            .opacity(visible ? 1 - p : 0)
        }
        .position(point)
    }

    private func shake(_ t: Double) -> CGFloat {
        let p = T.progress(t, T.shake)
        guard p > 0, p < 1 else { return 0 }
        return CGFloat(sin(p * 22) * 10 * (1 - p))
    }

    private func headlineView(t: Double) -> some View {
        let p = T.progress(t, T.textIn)
        return VStack(spacing: 8) {
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
        .scaleEffect(0.3 + 0.7 * T.easeOutBack(p))
        .opacity(min(1, p * 3))
    }

    // MARK: Haptics + completion

    /// Haptics and the hand-off run on the kick's own clock, so they stay in
    /// step with the picture even if a frame hitch pauses it.
    private func scheduleCues() {
        if !reduceMotion {
            clock.cue(at: T.windUp.lowerBound) { HapticService.shared.rigidImpact() }
        }
        clock.cue(at: T.contact) { HapticService.shared.heavyImpact() }
        clock.cue(at: T.fadeOut.upperBound) { onComplete() }
    }
}

// MARK: - Kick Clock

/// Elapsed time for the kick that pauses through a frame hitch instead of
/// skipping ahead: a stall while the send sheet dismisses (or a cold launch)
/// would otherwise eat the whole wind-up. Not observed; the TimelineView
/// redraws every frame and reads it.
@MainActor
final class KickClock {
    private(set) var t: Double = 0
    private var last: Date?
    private var cues: [(at: Double, run: () -> Void)] = []

    /// The longest step one frame may advance the clock.
    private let maxStep = 1.0 / 20

    func cue(at time: Double, _ run: @escaping () -> Void) {
        cues.append((time, run))
    }

    func advance(to now: Date) -> Double {
        if let last { t += min(max(0, now.timeIntervalSince(last)), maxStep) }
        last = now
        let due = cues.filter { $0.at <= t }
        if !due.isEmpty {
            cues.removeAll { $0.at <= t }
            // Called from inside body: run the cues after this update.
            Task { @MainActor in due.forEach { $0.run() } }
        }
        return t
    }
}

// MARK: - Kick Timeline

/// Timings (seconds from the start) and sizes for the boot kick. Tune the
/// feel here; the view only reads these.
enum KickTimeline {
    static let dimIn = 0.0...0.3
    static let dogIn = 0.05...0.45
    static let bootIn = 0.45...0.85
    /// Anticipation: the leg pulls back and holds for a beat.
    static let windUp = 0.85...1.25
    static let swing = 1.4...1.52
    static var contact: Double { swing.upperBound }
    static let follow = 1.52...1.72
    static let burst = 1.52...1.87
    static let shake = 1.52...1.77
    static let flight = 1.52...2.0
    static let bootOut = 1.8...2.25
    static let textIn = 2.3...2.75
    static let fadeOut = 3.9...4.3

    static let restAngle = 8.0
    static let windUpAngle = 35.0
    static let followAngle = -30.0
    static let flightSpin = 540.0
    /// How high the dog's arc climbs on its way out, in points.
    static let flightLift: CGFloat = 80

    static let dogSize: CGFloat = 110
    /// Dog sits right of centre to leave the boot room to swing.
    static let dogOffsetX: CGFloat = 90
    static let bootWidth: CGFloat = 200
    static let bootAspect = FlatBootView.aspect
    /// The toe cap in FlatBootView, as a fraction of its frame.
    static let toe = CGPoint(x: 0.95, y: 0.62)
    /// The pivot the leg swings around: above the boot's ankle opening.
    static let hip = UnitPoint(x: 0.35, y: -0.6)

    /// 0 before `range`, 1 after, linear inside.
    static func progress(_ t: Double, _ range: ClosedRange<Double>) -> Double {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    static func easeIn(_ p: Double) -> Double { p * p * p }
    static func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 2) }
    static func easeInOut(_ p: Double) -> Double { p * p * (3 - 2 * p) }
    /// Overshoots slightly past 1 before settling, for a springy pop.
    static func easeOutBack(_ p: Double) -> Double {
        let c = 1.7
        return 1 + (c + 1) * pow(p - 1, 3) + c * pow(p - 1, 2)
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
