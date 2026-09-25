//
//  AvatarView.swift
//  DogHouse

import SwiftUI

struct AvatarView: View {
    var avatar: DogAvatar
    var mood: AvatarMood = .happy
    var size: CGFloat = 80
    var cosmetics: AvatarCosmetics = .none

    /// Set false for dense grids (avatar picker, friends list) so dozens
    /// of timers don't run at once.
    var blinks: Bool = true

    /// Set false where the tail would stick out of a crop — the Welcome
    /// mascot shows only the head above the sign-in card.
    var showsTail: Bool = true

    /// Where the pupils look, in the avatar's own 80-unit space. Positive
    /// looks down. The Welcome mascot uses it to watch the field being typed.
    var gaze: CGFloat = 0

    /// Draw only the head (ears, face, collar): no tail, body or paws. The
    /// launch splash shows the head alone on the brand gradient.
    var headOnly: Bool = false

    /// When set, the eyelids follow this instead of the random blink timer,
    /// so an owner can blink the dog on cue (the launch splash blinks once).
    var blinkOverride: Bool? = nil

    @State private var isBlinking = false
    @State private var wag = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A happy dog wags; a dog in the doghouse does not. Shares the `blinks`
    /// switch so dense grids stay still.
    private var isWagging: Bool {
        blinks && !reduceMotion && (mood == .happy || mood == .cozy)
    }

    private var scale: CGFloat { size / 80.0 }

    var body: some View {
        ZStack {
            if showsTail && !headOnly { tailView }

            // Ears sit behind head
            earView(isLeft: true)
            earView(isLeft: false)

            if !headOnly { bodyView }

            // Head drawn on top of ears
            headShape

            faceView

            if !headOnly { pawsView }

            collarView

            moodAccessories

            // Cosmetics drawn last (on top)
            if let hat = cosmetics.hat      { hatView(hat) }
            if let gl  = cosmetics.glasses  { glassesView(gl) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(avatar.name) dog, feeling \(mood.rawValue)")
        .task(id: isWagging) {
            // Starting a repeating animation on a state flag confines it to that
            // flag; stopping is a plain (non-repeating) write of the same flag.
            if isWagging {
                withAnimation(.easeInOut(duration: 0.26).repeatForever(autoreverses: true)) { wag = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { wag = false }
            }
        }
        .task(id: blinks && !reduceMotion) {
            guard blinks && !reduceMotion else { return }
            // Desync avatars that appear on screen together
            try? await Task.sleep(for: .seconds(Double.random(in: 0...2.0)))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.6...6.0)))
                await blinkOnce()
                if Double.random(in: 0...1) < 0.35 {
                    try? await Task.sleep(for: .seconds(0.11))
                    await blinkOnce()
                }
            }
        }
    }

    private func blinkOnce() async {
        withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
        try? await Task.sleep(for: .seconds(0.09))
        withAnimation(.easeOut(duration: 0.11)) { isBlinking = false }
        try? await Task.sleep(for: .seconds(0.11))
    }

    // MARK: - Tail

    private var tailView: some View {
        Path { path in
            path.move(to: CGPoint(x: 2 * scale, y: 20 * scale))
            path.addQuadCurve(
                to: CGPoint(x: 26 * scale, y: 2 * scale),
                control: CGPoint(x: 30 * scale, y: 24 * scale)
            )
        }
        .stroke(avatar.primaryColor, lineWidth: 10 * scale)
        .frame(width: 34 * scale, height: 28 * scale)
        // Wag about the root of the tail (its bottom-left end), not the frame centre.
        .rotationEffect(.degrees(wag ? 16 : -12), anchor: UnitPoint(x: 0.08, y: 0.72))
        .offset(x: 18 * scale, y: 10 * scale)
    }

    // MARK: - Ears

    private func earView(isLeft: Bool) -> some View {
        Ellipse()
            .fill(avatar.primaryColor)
            .frame(width: 20 * scale, height: 26 * scale)
            .rotationEffect(.degrees(isLeft ? -6 : 6))
            .offset(x: (isLeft ? -21 : 21) * scale, y: -21 * scale)
    }

    // MARK: - Body

    private var bodyView: some View {
        Ellipse()
            .fill(avatar.primaryColor)
            .frame(width: 52 * scale, height: 40 * scale)
            .offset(y: 16 * scale)
    }

    // MARK: - Head

    private var headShape: some View {
        Circle()
            .fill(avatar.primaryColor)
            .frame(width: 50 * scale, height: 50 * scale)
            .offset(y: -8 * scale)
    }

    // MARK: - Face (all coords relative to head center y=-8)

    private var faceView: some View {
        ZStack {
            // Muzzle area — lower face
            Ellipse()
                .fill(avatar.muzzleColor)
                .frame(width: 26 * scale, height: 20 * scale)
                .offset(y: 10 * scale)

            // Eyes
            HStack(spacing: 18 * scale) {
                eyeView
                eyeView
            }
            .offset(y: -7 * scale)

            // Nose — at top of muzzle
            Ellipse()
                .fill(Color(red: 0.12, green: 0.08, blue: 0.08))
                .frame(width: 9 * scale, height: 6 * scale)
                .offset(y: 2 * scale)

            // Mouth
            mouthView
                .offset(y: 12 * scale)
        }
        .offset(y: -8 * scale)
    }

    private var eyeView: some View {
        ZStack {
            // White sclera
            Circle()
                .fill(Color.white)
                .frame(width: 14 * scale, height: 14 * scale)

            // Pupil
            Circle()
                .fill(Color(red: 0.12, green: 0.08, blue: 0.08))
                .frame(width: eyePupilSize, height: eyePupilSize)
                .offset(y: eyeOffset + gaze * scale)
                .animation(.easeInOut(duration: 0.25), value: gaze)

            // Shine highlight
            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 4 * scale, height: 4 * scale)
                .offset(x: 3 * scale, y: -3 * scale)

            // Eyelid — fur coloured, so it reads as the lid closing
            Rectangle()
                .fill(avatar.primaryColor)
                .frame(width: 15 * scale, height: 15 * scale)
                .offset(y: (blinkOverride ?? isBlinking) ? 0 : -15 * scale)
        }
        .frame(width: 14 * scale, height: 14 * scale)
        .clipShape(Circle())
    }

    private var eyePupilSize: CGFloat {
        switch mood {
        case .happy, .cozy:  7 * scale
        case .sad, .hungry:  8 * scale
        case .freezing:      5 * scale
        case .dramatic:     10 * scale
        }
    }

    private var eyeOffset: CGFloat {
        switch mood {
        case .sad, .hungry: 1 * scale
        default: 0
        }
    }

    @ViewBuilder
    private var mouthView: some View {
        switch mood {
        case .happy, .cozy:
            Path { path in
                path.addArc(
                    center: CGPoint(x: 8 * scale, y: 0),
                    radius: 8 * scale,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false
                )
            }
            .stroke(Color(red: 0.12, green: 0.08, blue: 0.08), lineWidth: 1.5 * scale)
            .frame(width: 16 * scale, height: 8 * scale)

        case .sad, .dramatic:
            Path { path in
                path.addArc(
                    center: CGPoint(x: 8 * scale, y: 8 * scale),
                    radius: 8 * scale,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false
                )
            }
            .stroke(Color(red: 0.12, green: 0.08, blue: 0.08), lineWidth: 1.5 * scale)
            .frame(width: 16 * scale, height: 8 * scale)

        case .hungry:
            Ellipse()
                .fill(Color(red: 0.12, green: 0.08, blue: 0.08).opacity(0.7))
                .frame(width: 13 * scale, height: 9 * scale)

        case .freezing:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5 * scale))
                path.addCurve(
                    to: CGPoint(x: 18 * scale, y: 5 * scale),
                    control1: CGPoint(x: 4 * scale, y: 0),
                    control2: CGPoint(x: 14 * scale, y: 10 * scale)
                )
            }
            .stroke(Color(red: 0.12, green: 0.08, blue: 0.08), lineWidth: 1.5 * scale)
            .frame(width: 18 * scale, height: 10 * scale)
        }
    }

    // MARK: - Paws

    private var pawsView: some View {
        HStack(spacing: 13 * scale) {
            pawShape
            pawShape
        }
        .offset(y: 34 * scale)
    }

    private var pawShape: some View {
        RoundedRectangle(cornerRadius: 5 * scale)
            .fill(avatar.primaryColor)
            .frame(width: 14 * scale, height: 9 * scale)
    }

    // MARK: - Collar (necklace cosmetic applied here)

    private var collarView: some View {
        let bandW = 34 * scale
        let bow   = 16 * scale
        let necklace = cosmetics.necklace
        let bandColor = necklace?.primaryColor ?? Color(red: 0.42, green: 0.24, blue: 0.07)
        let gemColor  = necklace?.primaryColor ?? Color(red: 0.96, green: 0.82, blue: 0.18)

        return ZStack {
            if necklace?.id == "necklace_rainbow" {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(
                        to: CGPoint(x: bandW, y: 0),
                        control: CGPoint(x: bandW / 2, y: bow)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round)
                )
                .frame(width: bandW, height: bow + 2 * scale)
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(
                        to: CGPoint(x: bandW, y: 0),
                        control: CGPoint(x: bandW / 2, y: bow)
                    )
                }
                .stroke(
                    bandColor,
                    style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round)
                )
                .frame(width: bandW, height: bow + 2 * scale)
            }

            // Gem / tag at the lowest point of the collar arc
            Circle()
                .fill(gemColor)
                .overlay(Circle().stroke(Color(red: 0.22, green: 0.13, blue: 0.02), lineWidth: 1.5 * scale))
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 3 * scale)
                        .offset(x: -1 * scale, y: -1 * scale)
                )
                .frame(width: 9 * scale)
                .offset(y: -1 * scale)
        }
        .offset(y: 16 * scale)
    }

    // MARK: - Mood Accessories

    @ViewBuilder
    private var moodAccessories: some View {
        switch mood {
        case .hungry:
            Capsule()
                .fill(Color(red: 0.5, green: 0.72, blue: 0.95).opacity(0.7))
                .frame(width: 4 * scale, height: 7 * scale)
                .offset(x: 5 * scale, y: 8 * scale)

        case .freezing:
            Circle()
                .fill(Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.18))
                .frame(width: 50 * scale, height: 50 * scale)
                .offset(y: -8 * scale)

        case .dramatic:
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color(red: 0.5, green: 0.72, blue: 0.95).opacity(0.7))
                    .frame(width: 3 * scale, height: 6 * scale)
                    .offset(
                        x: CGFloat([-28, 28, -22][i]) * scale,
                        y: CGFloat([-18, -12, -6][i]) * scale
                    )
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Hat Cosmetics
    // Head top is at y = -33*scale from ZStack center, but the head is a
    // circle (centre y = -8, radius 25), so a flat base resting on that
    // single point hovers above the curve. Each hat's bottom edge instead
    // sits where its base's corners meet the head: y = -8 - sqrt(25² - (w/2)²)
    // for base width w. Wide brims (cowboy, wizard) are seated by their
    // crown and overhang, as brims do.

    @ViewBuilder
    private func hatView(_ item: CosmeticItem) -> some View {
        switch item.id {
        case "hat_party":  partyHat(item)
        case "hat_crown":  crownHat(item)
        case "hat_cowboy": cowboyHat(item)
        case "hat_chef":   chefHat(item)
        case "hat_beanie": beanieHat(item)
        case "hat_wizard": wizardHat(item)
        case "hat_halo":   haloHat(item)
        case "hat_top":    topHat(item)
        default: EmptyView()
        }
    }

    private func beanieHat(_ item: CosmeticItem) -> some View {
        ZStack(alignment: .bottom) {
            // Knit dome
            Ellipse()
                .fill(item.primaryColor)
                .frame(width: 34 * scale, height: 22 * scale)
                .offset(y: -6 * scale)
            // Folded brim
            Capsule()
                .fill(item.accentColor)
                .frame(width: 36 * scale, height: 8 * scale)
            // Pom pom
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 9 * scale)
                .offset(y: -20 * scale)
        }
        .frame(width: 36 * scale, height: 26 * scale)
        .offset(y: -(26 + 13) * scale)   // beanie, 36 wide, hugs the head
    }

    private func wizardHat(_ item: CosmeticItem) -> some View {
        ZStack {
            // Tall cone
            Path { path in
                path.move(to: CGPoint(x: 15 * scale, y: 0))
                path.addLine(to: CGPoint(x: 30 * scale, y: 34 * scale))
                path.addLine(to: CGPoint(x: 0, y: 34 * scale))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [item.primaryColor, item.accentColor], startPoint: .top, endPoint: .bottom))
            // Pin the cone's frame: the wider brim widens the ZStack, and a
            // Path draws from its top-left, which pushed the cone off-centre.
            .frame(width: 30 * scale, height: 34 * scale)
            // Brim
            Capsule()
                .fill(item.primaryColor)
                .frame(width: 40 * scale, height: 6 * scale)
                .offset(y: 15 * scale)
            // Stars
            Image(systemName: "star.fill")
                .font(.system(size: 6 * scale))
                .foregroundStyle(item.accentColor)
                .offset(y: 4 * scale)
            Image(systemName: "sparkle")
                .font(.system(size: 5 * scale))
                .foregroundStyle(item.accentColor)
                .offset(x: -5 * scale, y: 9 * scale)
        }
        .frame(width: 30 * scale, height: 34 * scale)
        .offset(y: -(28 + 17) * scale)   // seated by its 30-wide cone
    }

    private func haloHat(_ item: CosmeticItem) -> some View {
        Ellipse()
            .stroke(
                LinearGradient(colors: [item.primaryColor, item.accentColor], startPoint: .leading, endPoint: .trailing),
                lineWidth: 4 * scale
            )
            .frame(width: 30 * scale, height: 10 * scale)
            .shadow(color: item.primaryColor.opacity(0.7), radius: 5 * scale)
            .offset(y: -(33 + 12) * scale)
    }

    private func partyHat(_ item: CosmeticItem) -> some View {
        ZStack {
            // Cone
            Path { path in
                path.move(to: CGPoint(x: 12 * scale, y: 0))
                path.addLine(to: CGPoint(x: 24 * scale, y: 27 * scale))
                path.addLine(to: CGPoint(x: 0, y: 27 * scale))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [item.primaryColor, item.accentColor], startPoint: .top, endPoint: .bottom))
            .frame(width: 24 * scale, height: 27 * scale) // see wizardHat
            // Accent band at base
            Capsule()
                .fill(item.accentColor)
                .frame(width: 26 * scale, height: 5 * scale)
                .offset(y: 12 * scale)
            // Pom pom tip
            Circle()
                .fill(Color.yellow)
                .frame(width: 8 * scale)
                .offset(y: -12 * scale)
        }
        .frame(width: 24 * scale, height: 27 * scale)
        .offset(y: -(29 + 13.5) * scale) // 26-wide band
    }

    private func crownHat(_ item: CosmeticItem) -> some View {
        ZStack(alignment: .bottom) {
            // Three triangular points
            HStack(spacing: 1 * scale) {
                ForEach(0..<3, id: \.self) { _ in
                    Path { path in
                        path.move(to: CGPoint(x: 6 * scale, y: 0))
                        path.addLine(to: CGPoint(x: 12 * scale, y: 12 * scale))
                        path.addLine(to: CGPoint(x: 0, y: 12 * scale))
                        path.closeSubpath()
                    }
                    .fill(item.primaryColor)
                    .frame(width: 12 * scale, height: 12 * scale)
                }
            }
            .offset(y: -8 * scale)
            // Band
            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(item.primaryColor)
                .frame(width: 38 * scale, height: 8 * scale)
            // Gems
            HStack(spacing: 8 * scale) {
                Circle().fill(item.accentColor).frame(width: 5 * scale)
                Circle().fill(Color.blue.opacity(0.8)).frame(width: 5 * scale)
                Circle().fill(item.accentColor).frame(width: 5 * scale)
            }
            .offset(y: -2 * scale)
        }
        .frame(width: 38 * scale, height: 20 * scale)
        .offset(y: -(25 + 10) * scale)   // 38-wide band
    }

    private func cowboyHat(_ item: CosmeticItem) -> some View {
        ZStack(alignment: .bottom) {
            // Dome
            Ellipse()
                .fill(item.primaryColor)
                .frame(width: 30 * scale, height: 18 * scale)
                .offset(y: -8 * scale)
            // Hat band
            Rectangle()
                .fill(item.accentColor)
                .frame(width: 30 * scale, height: 3.5 * scale)
                .offset(y: -8 * scale)
            // Brim
            Capsule()
                .fill(item.primaryColor)
                .frame(width: 50 * scale, height: 7 * scale)
        }
        .frame(width: 50 * scale, height: 25 * scale)
        .offset(y: -(28 + 12.5) * scale) // seated by its 30-wide dome
    }

    private func topHat(_ item: CosmeticItem) -> some View {
        ZStack(alignment: .bottom) {
            // Crown
            Rectangle()
                .fill(item.primaryColor)
                .frame(width: 26 * scale, height: 22 * scale)
                .offset(y: -3 * scale)
            // Hat band
            Rectangle()
                .fill(item.accentColor)
                .frame(width: 26 * scale, height: 5 * scale)
                .offset(y: -3 * scale)
            // Brim
            Capsule()
                .fill(item.primaryColor)
                .frame(width: 40 * scale, height: 6 * scale)
        }
        .frame(width: 40 * scale, height: 25 * scale)
        .offset(y: -(29 + 12.5) * scale) // seated by its 26-wide crown
    }

    private func chefHat(_ item: CosmeticItem) -> some View {
        ZStack(alignment: .bottom) {
            // Puffy dome
            Ellipse()
                .fill(item.primaryColor)
                .frame(width: 28 * scale, height: 22 * scale)
                .offset(y: -12 * scale)
            // Cylinder body
            Rectangle()
                .fill(item.primaryColor)
                .frame(width: 28 * scale, height: 14 * scale)
            // Band
            Rectangle()
                .fill(item.accentColor)
                .frame(width: 28 * scale, height: 5 * scale)
        }
        .frame(width: 28 * scale, height: 28 * scale)
        .offset(y: -(29 + 14) * scale)   // 28-wide body
    }

    // MARK: - Glasses Cosmetics
    // Eye centers: x = ±16*scale, y = -15*scale from ZStack center; each eye
    // is 14 wide. Lenses with a picture on them (heart, star, pixel) are
    // solid so the eye doesn't show through behind the picture.

    @ViewBuilder
    private func glassesView(_ item: CosmeticItem) -> some View {
        if item.id == "glasses_pixel" {
            pixelShades(item)
        } else {
            framedGlasses(item)
        }
    }

    private func framedGlasses(_ item: CosmeticItem) -> some View {
        ZStack {
            // Left lens
            lensShape(item: item)
                .offset(x: -16 * scale, y: -15 * scale)
            // Right lens
            lensShape(item: item)
                .offset(x: 16 * scale, y: -15 * scale)
            // Bridge
            Rectangle()
                .fill(item.primaryColor)
                .frame(width: 10 * scale, height: 2 * scale)
                .offset(y: -15 * scale)
        }
    }

    @ViewBuilder
    private func lensShape(item: CosmeticItem) -> some View {
        switch item.id {
        case "glasses_cool":
            RoundedRectangle(cornerRadius: 3 * scale)
                .fill(item.primaryColor.opacity(0.72))
                .frame(width: 17 * scale, height: 11 * scale)
        case "glasses_heart":
            ZStack {
                Circle()
                    .fill(item.primaryColor)
                    .frame(width: 16 * scale, height: 16 * scale)
                Image(systemName: "heart.fill")
                    .font(.system(size: 8 * scale))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        case "glasses_star":
            ZStack {
                // Night-sky lens so the gold star reads against it
                Circle()
                    .fill(Color(red: 0.16, green: 0.15, blue: 0.32))
                    .frame(width: 16 * scale, height: 16 * scale)
                Circle()
                    .stroke(item.primaryColor, lineWidth: 2 * scale)
                    .frame(width: 16 * scale, height: 16 * scale)
                Image(systemName: "star.fill")
                    .font(.system(size: 8 * scale))
                    .foregroundStyle(item.primaryColor)
            }
        case "glasses_round":
            Circle()
                .fill(item.accentColor.opacity(0.25))
                .overlay(Circle().stroke(item.primaryColor, lineWidth: 2 * scale))
                .frame(width: 15 * scale, height: 15 * scale)
        case "glasses_ski":
            RoundedRectangle(cornerRadius: 6 * scale)
                .fill(
                    LinearGradient(colors: [item.primaryColor.opacity(0.75), item.accentColor.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 6 * scale).stroke(Color.white.opacity(0.6), lineWidth: 1.5 * scale))
                .frame(width: 19 * scale, height: 14 * scale)
        default:
            Circle()
                .stroke(item.primaryColor, lineWidth: 2 * scale)
                .frame(width: 16 * scale, height: 16 * scale)
        }
    }

    /// 8-bit "deal with it" shades: one bar across the top, and each lens
    /// steps in along its bottom row. Drawn on a 4-unit pixel grid in the
    /// avatar's 80-unit space (origin at centre), covering both eyes.
    private func pixelShades(_ item: CosmeticItem) -> some View {
        func px(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: (x0 + 40) * scale, y: (y0 + 40) * scale,
                   width: (x1 - x0) * scale, height: (y1 - y0) * scale)
        }
        let frame = Path { p in
            p.addRect(px(-26, -23, 26, -19))            // top bar + bridge
            for cx: CGFloat in [-16, 16] {
                p.addRect(px(cx - 10, -19, cx + 10, -11))   // lens body
                p.addRect(px(cx - 6, -11, cx + 6, -7))      // stepped bottom row
            }
        }
        let shine = Path { p in
            for cx: CGFloat in [-16, 16] {
                p.addRect(px(cx - 8, -19, cx - 6, -17))
                p.addRect(px(cx - 6, -17, cx - 4, -15))
            }
        }
        return ZStack {
            frame.fill(item.primaryColor)
            shine.fill(item.accentColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Previews

#Preview("All Moods") {
    VStack(spacing: 20) {
        HStack(spacing: 24) {
            AvatarView(avatar: .allAvatars[0], mood: .happy, size: 90)
            AvatarView(avatar: .allAvatars[2], mood: .sad, size: 90)
            AvatarView(avatar: .allAvatars[4], mood: .hungry, size: 90)
        }
        HStack(spacing: 24) {
            AvatarView(avatar: .allAvatars[6], mood: .freezing, size: 90)
            AvatarView(avatar: .allAvatars[1], mood: .dramatic, size: 90)
            AvatarView(avatar: .allAvatars[3], mood: .cozy, size: 90)
        }
    }
    .padding(24)
    .background(Color(red: 0.98, green: 0.96, blue: 0.92))
}

#Preview("Cosmetics") {
    HStack(spacing: 20) {
        AvatarView(avatar: .allAvatars[0], mood: .happy, size: 90,
                   cosmetics: .init(necklaceId: "necklace_rainbow", hatId: "hat_crown", glassesId: "glasses_star"))
        AvatarView(avatar: .allAvatars[2], mood: .happy, size: 90,
                   cosmetics: .init(necklaceId: "necklace_pink", hatId: "hat_party", glassesId: "glasses_heart"))
        AvatarView(avatar: .allAvatars[4], mood: .happy, size: 90,
                   cosmetics: .init(necklaceId: "necklace_blue", hatId: "hat_cowboy", glassesId: "glasses_cool"))
        AvatarView(avatar: .allAvatars[6], mood: .happy, size: 90,
                   cosmetics: .init(necklaceId: "necklace_gold", hatId: "hat_top", glassesId: "glasses_pixel"))
    }
    .padding(24)
    .background(Color(red: 0.98, green: 0.96, blue: 0.92))
}
