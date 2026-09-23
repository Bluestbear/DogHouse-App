//
//  ReleaseAnimations.swift
//  DogHouse
//
//  The release overlay, the answer to the boot kick in SendToDogHouseAnimation.
//  Each release picks one of two little scenes at random:
//
//  - Homecoming: the dog that was kicked out the right edge peeks back in,
//    checks the coast is clear, hops home and shakes itself off.
//  - Peace offering: the same old boot comes back, gently this time, and
//    nudges a treat over to the dog.
//
//  Like the kick, every element is a pure function of a hitch-tolerant clock
//  (KickClock) and the feel is tuned in the timeline enums at the bottom.
//

import SwiftUI

enum ReleaseVariant: String, CaseIterable {
    case homecoming
    case peaceOffering

    /// A random scene per release. Debug builds can pin one with
    /// `-demoRelease homecoming` / `-demoRelease peaceOffering`.
    static func pick() -> ReleaseVariant {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "demoRelease"),
           let pinned = ReleaseVariant(rawValue: name) {
            return pinned
        }
        #endif
        return allCases.randomElement() ?? .homecoming
    }
}

struct ReleaseFromDogHouseAnimation: View {
    /// Name of the partner being released. Shown to the SENDER when they
    /// let their partner out, so the text speaks about the partner.
    var partnerName: String = ""
    /// The partner's dog, the same one the boot kicked out.
    var avatarId: String = "dog_1"
    var cosmetics: AvatarCosmetics = .none
    /// Pin a scene (previews); nil picks one at random per release.
    var fixedVariant: ReleaseVariant? = nil
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var randomVariant = ReleaseVariant.pick()
    private var variant: ReleaseVariant { fixedVariant ?? randomVariant }
    @State private var clock = KickClock()

    private var headline: String {
        partnerName.isEmpty ? "YOU'RE FREE!" : "\(partnerName.uppercased()) IS FREE!"
    }

    private var subline: String {
        partnerName.isEmpty ? "Welcome home!" : "You let them out — welcome home, \(partnerName)!"
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
        .onAppear(perform: scheduleCues)
    }

    // MARK: Scene

    @ViewBuilder
    private func scene(t: Double, size: CGSize) -> some View {
        let fadeOut = 1 - KickTimeline.easeInOut(KickTimeline.progress(t, beats.fadeOut))
        ZStack {
            Color.black.opacity(0.7 * KickTimeline.progress(t, 0...0.3) * fadeOut)

            Group {
                if reduceMotion {
                    calmScene(t: t, size: size, beats: beats)
                } else {
                    switch variant {
                    case .homecoming: HomecomingScene(t: t, size: size, dog: dog)
                    case .peaceOffering: PeaceOfferingScene(t: t, size: size, dog: dog)
                    }
                }
            }
            .opacity(fadeOut)

            ReleaseText(headline: headline, subline: subline, p: KickTimeline.progress(t, beats.textIn))
                .position(x: size.width / 2, y: size.height * ReleaseLayout.textY)
                .opacity(fadeOut)
        }
    }

    /// The shared beats the overlay itself needs: when the text lands, when
    /// the heart pops (haptic), and when it all fades.
    private var beats: ReleaseBeats {
        switch variant {
        case .homecoming: HomecomingTimeline.beats
        case .peaceOffering: OfferingTimeline.beats
        }
    }

    private func dog(_ mood: AvatarMood) -> AvatarView {
        AvatarView(avatar: DogAvatar.avatar(for: avatarId), mood: mood,
                   size: ReleaseLayout.dogSize, cosmetics: cosmetics)
    }

    /// Reduce Motion: no hops, no boot. The happy dog fades in with its heart.
    private func calmScene(t: Double, size: CGSize, beats: ReleaseBeats) -> some View {
        let home = ReleaseLayout.home(in: size)
        return ZStack {
            dog(.happy)
                .position(home)
                .opacity(KickTimeline.progress(t, 0.2...0.7))
            ReleaseHeart(p: KickTimeline.progress(t, beats.heart), drift: false)
                .position(x: home.x, y: home.y - ReleaseLayout.dogSize * 0.75)
        }
    }

    // MARK: Haptics + completion

    private func scheduleCues() {
        if !reduceMotion {
            switch variant {
            case .homecoming:
                for landing in HomecomingTimeline.landings {
                    clock.cue(at: landing) { HapticService.shared.lightTap() }
                }
            case .peaceOffering:
                clock.cue(at: OfferingTimeline.nudge.lowerBound) { HapticService.shared.lightTap() }
            }
        }
        clock.cue(at: beats.heart.lowerBound) { HapticService.shared.success() }
        clock.cue(at: beats.fadeOut.upperBound) { onComplete() }
    }
}

// MARK: - Homecoming

/// The dog peeks back in from the right edge, looks both ways, brightens,
/// hops home in three bounds, and shakes itself dry.
private struct HomecomingScene: View {
    let t: Double
    let size: CGSize
    let dog: (AvatarMood) -> AvatarView

    private typealias T = HomecomingTimeline
    private typealias K = KickTimeline

    var body: some View {
        let home = ReleaseLayout.home(in: size)
        let s = ReleaseLayout.dogSize
        let pos = position(home: home)
        let squash = squash
        let happy = t >= T.brighten

        ZStack {
            if t >= T.confetti.lowerBound {
                ReleaseConfetti(p: K.progress(t, T.confetti))
                    .position(x: home.x, y: home.y - s * 0.2)
            }
            WaterDrops(p: K.progress(t, T.drops))
                .position(home)

            dog(happy ? .happy : .sad)
                .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .position(pos)

            ReleaseHeart(p: K.progress(t, T.beats.heart), drift: true)
                .position(x: home.x, y: home.y - s * 0.75)
        }
    }

    private func position(home: CGPoint) -> CGPoint {
        let s = ReleaseLayout.dogSize
        let offscreen = size.width + s
        // About half the dog shows while it peeks round the edge.
        let peekX = size.width - s * 0.05
        if t < T.hops.lowerBound {
            let x = offscreen + (peekX - offscreen) * K.easeOut(K.progress(t, T.peek))
            return CGPoint(x: x, y: home.y)
        }
        // Three hops from the edge to home, each a little lower than the last.
        let p = K.progress(t, T.hops) * Double(T.hopHeights.count)
        let i = min(Int(p), T.hopHeights.count - 1)
        let local = p - Double(i)
        let span = (home.x - peekX) / CGFloat(T.hopHeights.count)
        let x = peekX + span * (CGFloat(i) + CGFloat(local))
        let y = home.y - T.hopHeights[i] * CGFloat(sin(local * .pi))
        return CGPoint(x: x, y: y)
    }

    /// Looks left and right while peeking, then the wet-dog shake at home.
    private var tilt: Double {
        let look = K.progress(t, T.look)
        if look > 0 && look < 1 { return 14 * sin(look * 2 * .pi) }
        let shake = K.progress(t, T.shake)
        if shake > 0 && shake < 1 { return 16 * sin(shake * .pi * 9) * (1 - shake) }
        return 0
    }

    /// Crouch before the first hop and on every landing.
    private var squash: CGFloat {
        let moments = [T.brighten + 0.02] + T.landings
        for m in moments where t >= m && t < m + 0.14 {
            return CGFloat(sin((t - m) / 0.14 * .pi) * 0.1)
        }
        return 0
    }
}

// MARK: - Peace Offering

/// The old boot comes back, slowly, and nudges a treat across to the dog,
/// who eats it and cheers up.
private struct PeaceOfferingScene: View {
    let t: Double
    let size: CGSize
    let dog: (AvatarMood) -> AvatarView

    private typealias T = OfferingTimeline
    private typealias K = KickTimeline

    var body: some View {
        // The dog sits right of centre so the boot has room on screen.
        let home = ReleaseLayout.home(in: size).applying(.init(translationX: T.dogOffsetX, y: 0))
        let s = ReleaseLayout.dogSize
        let groundY = home.y + s * 0.44
        let bootW = K.bootWidth
        let bootH = bootW * K.bootAspect
        // The toe stops a treat's length short of the dog.
        let toeX = home.x - s * 0.5 - T.gap
        let bootCenter = CGPoint(x: toeX - (K.toe.x - 0.5) * bootW,
                                 y: groundY - (T.soleBottom - 0.5) * bootH)
        let offscreen = -(bootCenter.x + bootW)
        let slide = offscreen * (1 - K.easeOut(K.progress(t, T.bootIn)))
            + offscreen * K.easeIn(K.progress(t, T.bootOut))

        // The treat rides in just ahead of the toe, then the nudge sends it on.
        let treatStart = toeX + 28
        let treatEnd = home.x - s * 0.08
        let treatX = t < T.treatSlide.lowerBound
            ? treatStart + slide
            : treatStart + (treatEnd - treatStart) * K.easeOut(K.progress(t, T.treatSlide))
        let eaten = K.progress(t, T.eat)

        ZStack {
            if t >= T.confetti.lowerBound {
                ReleaseConfetti(p: K.progress(t, T.confetti))
                    .position(x: home.x, y: home.y - s * 0.2)
            }

            dog(mood)
                .scaleEffect(x: 1 + dogSquash, y: 1 - dogSquash, anchor: .bottom)
                .offset(y: -hop)
                .position(home)
                .opacity(K.progress(t, T.dogIn))

            TreatBone()
                .frame(width: 44, height: 20)
                .scaleEffect(1 - eaten)
                .position(x: treatX, y: groundY - 8)
                .opacity(eaten < 1 ? 1 : 0)

            FlatBootView()
                .frame(width: bootW, height: bootH)
                .rotationEffect(.degrees(bootAngle), anchor: K.hip)
                .position(x: bootCenter.x + slide, y: bootCenter.y)

            ReleaseHeart(p: K.progress(t, T.beats.heart), drift: true)
                .position(x: home.x, y: home.y - s * 0.75)
        }
    }

    private var mood: AvatarMood {
        if t >= T.brighten { return .happy }
        if t >= T.bootIn.lowerBound + 0.2 { return .dramatic }
        return .sad
    }

    /// A small, polite tap: toe lifts, then pushes forward.
    private var bootAngle: Double {
        let p = K.progress(t, T.nudge)
        guard p > 0 && p < 1 else { return 0 }
        return p < 0.4 ? 10 * K.easeOut(p / 0.4) : 10 - 18 * sin((p - 0.4) / 0.6 * .pi)
    }

    /// One happy bounce after the treat.
    private var hop: CGFloat {
        let p = K.progress(t, T.hop)
        return p > 0 && p < 1 ? CGFloat(sin(p * .pi)) * 36 : 0
    }

    /// Flinch when the boot shows up; a chomp pulse while eating.
    private var dogSquash: CGFloat {
        let flinch = K.progress(t, T.flinch)
        if flinch > 0 && flinch < 1 { return -CGFloat(sin(flinch * .pi)) * 0.08 }
        let eat = K.progress(t, T.eat)
        if eat > 0 && eat < 1 { return CGFloat(abs(sin(eat * .pi * 3))) * 0.06 }
        return 0
    }
}

// MARK: - Shared pieces

private enum ReleaseLayout {
    static let dogSize: CGFloat = 110
    static let textY: CGFloat = 0.64

    /// Where the dog ends up: a little above centre, so the text sits below.
    static func home(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.40)
    }
}

private struct ReleaseText: View {
    let headline: String
    let subline: String
    let p: Double

    var body: some View {
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
        .scaleEffect(0.3 + 0.7 * KickTimeline.easeOutBack(p))
        .opacity(min(1, p * 3))
    }
}

private struct ReleaseHeart: View {
    let p: Double
    /// Float up and fade after popping, instead of staying put.
    let drift: Bool

    var body: some View {
        let pop = KickTimeline.easeOutBack(min(1, p * 2.5))
        let rise = drift ? max(0, p - 0.4) / 0.6 : 0
        Image(systemName: "heart.fill")
            .font(.system(size: 34))
            .foregroundStyle(Color(red: 0.93, green: 0.36, blue: 0.40))
            .scaleEffect(pop)
            .offset(y: -30 * rise)
            .opacity(p > 0 ? 1 - rise : 0)
    }
}

/// A flat dog bone, drawn like the rest of the scene.
private struct TreatBone: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let r = h * 0.3
            var bone = Path(roundedRect: CGRect(x: r, y: h * 0.3, width: w - 2 * r, height: h * 0.4),
                            cornerRadius: h * 0.1)
            for x in [r, w - r] {
                for y in [h * 0.3, h * 0.7] {
                    bone.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
            }
            ctx.fill(bone, with: .color(Color(red: 0.98, green: 0.92, blue: 0.78)))
            ctx.stroke(bone, with: .color(.black.opacity(0.35)), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}

/// Drops flung off by the wet-dog shake.
private struct WaterDrops: View {
    let p: Double

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = -.pi / 2 + (Double(i) / 9 - 0.5) * .pi * 1.5
                let r = 40 + 80 * KickTimeline.easeOut(p)
                Capsule()
                    .fill(Color(red: 0.5, green: 0.72, blue: 0.95))
                    .frame(width: 5, height: 9)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: cos(angle) * r, y: sin(angle) * r + 60 * p * p)
            }
        }
        .opacity(p > 0 && p < 1 ? 1 - p : 0)
    }
}

/// A burst of confetti in the app's own warm palette, falling under gravity.
private struct ReleaseConfetti: View {
    let p: Double

    private static let colors: [Color] = [
        .cozyOrange, .freedomGreen, .white,
        Color(red: 0.98, green: 0.92, blue: 0.78),
        Color(red: 0.93, green: 0.36, blue: 0.40),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<30, id: \.self) { i in
                let angle = -.pi / 2 + (Self.noise(i, 1) - 0.5) * .pi * 1.4
                let speed = 140 + 150 * Self.noise(i, 2)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.colors[i % Self.colors.count])
                    .frame(width: 6, height: 10)
                    .rotationEffect(.degrees(720 * p * (Self.noise(i, 3) - 0.5)))
                    .offset(x: cos(angle) * speed * p,
                            y: sin(angle) * speed * p + 320 * p * p)
            }
        }
        .opacity(p > 0 ? 1 - pow(p, 3) : 0)
    }

    /// Stable pseudo-random 0...1 per particle, so every frame agrees.
    private static func noise(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i * 127 + k * 311)) * 43_758.5453
        return x - floor(x)
    }
}

// MARK: - Timelines

struct ReleaseBeats {
    let heart: ClosedRange<Double>
    let textIn: ClosedRange<Double>
    let fadeOut: ClosedRange<Double>
}

/// Seconds from the start. Tune the homecoming here.
enum HomecomingTimeline {
    static let peek = 0.35...0.8
    /// Looks left, then right, before daring to come in.
    static let look = 0.95...1.75
    /// Sees the coast is clear: mood flips to happy and the tail wags.
    static let brighten = 1.8
    static let hops = 2.0...2.9
    static let hopHeights: [CGFloat] = [70, 55, 40]
    static var landings: [Double] {
        let each = (hops.upperBound - hops.lowerBound) / Double(hopHeights.count)
        return (1...hopHeights.count).map { hops.lowerBound + each * Double($0) }
    }
    static let shake = 3.0...3.5
    static let drops = 3.05...3.6
    static let confetti = 3.3...4.8
    static let beats = ReleaseBeats(heart: 3.45...4.4, textIn: 3.55...4.0, fadeOut: 5.1...5.5)
}

/// Seconds from the start. Tune the peace offering here.
enum OfferingTimeline {
    static let dogIn = 0.1...0.45
    static let bootIn = 0.6...1.4
    static let flinch = 0.8...1.05
    static let nudge = 1.6...2.0
    static var treatSlide: ClosedRange<Double> { (nudge.lowerBound + 0.2)...(nudge.lowerBound + 0.75) }
    static let bootOut = 2.3...2.9
    static let brighten = 2.45
    static let eat = 2.5...2.85
    static let hop = 2.95...3.3
    static let confetti = 3.0...4.5
    static let beats = ReleaseBeats(heart: 3.0...3.9, textIn: 3.15...3.6, fadeOut: 4.7...5.1)
    /// How far short of the dog the boot stops, in points.
    static let gap: CGFloat = 38
    static let dogOffsetX: CGFloat = 70
    /// The bottom of the tread in FlatBootView, as a fraction of its height.
    static let soleBottom: CGFloat = 0.87
}

#Preview("Homecoming") {
    ReleaseFromDogHouseAnimation(partnerName: "Sam", fixedVariant: .homecoming) {}
}

#Preview("Peace offering") {
    ReleaseFromDogHouseAnimation(partnerName: "Sam", fixedVariant: .peaceOffering) {}
}
