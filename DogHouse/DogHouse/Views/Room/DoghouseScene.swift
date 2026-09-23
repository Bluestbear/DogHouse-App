//
//  DoghouseScene.swift
//  DogHouse
//
//  The yard where a dog serves its sentence. Everything stacks with time
//  served (DoghouseStage): the sky closes in, drizzle becomes rain becomes a
//  storm with lightning and finally snow, the yard turns to mud, and the dog
//  shivers harder. Weather is drawn in a Canvas driven by a TimelineView, so
//  it runs without a pile of repeatForever animations.
//

import SwiftUI

struct DoghouseScene: View {
    var isCurrentUser: Bool
    var partnerName: String
    var duration: TimeInterval
    var avatarId: String = "dog_1"
    var cosmetics: AvatarCosmetics = .none
    var onBellyRub: (() -> Void)? = nil
    /// Show the received rose bouquet next to the dog (fades after 5h)
    var showRoses: Bool = false
    /// Bump this to make the dog hop — a belly rub just landed.
    var jumpTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showBellyRubBurst = false
    @State private var hop = DogHop()
    @State private var flash: Double = 0
    /// Lightning bolt, x as a fraction of the width, y in points.
    @State private var bolt: [CGPoint]? = nil
    @State private var cloudDrift: CGFloat = 0

    private var stage: DoghouseStage { DoghouseStage.stage(for: duration) }
    private var gloom: Double { stage.gloom }

    private var avatarMood: AvatarMood {
        switch stage {
        case .justArrived: .sad
        case .gettingHungry: .hungry
        case .cloudsGathering, .rainy, .gettingDirty: .sad
        case .mouseFriend, .stormyNight: .dramatic
        case .fullSurvival: .freezing
        }
    }

    // The scene is decorative: it is assembled from shapes that mean nothing
    // read aloud. The status text carries the same information for VoiceOver.
    var body: some View {
        // The scenery hangs off the sky as an overlay: several props are
        // wider than the card (the 400pt hills), and as ZStack children they
        // grew the card past the screen edges. An overlay can't size its
        // parent, so the sky alone decides the card's width and the clip
        // trims the overhang.
        sky
        .overlay {
            ZStack {
                if stage.isNight { nightSky }
                hills
                if stage.showClouds { clouds }
                ground
                fence.offset(x: -138, y: 78)
                tree.offset(x: 140, y: 44)
                house.offset(y: 40)
                weather
                Color.white.opacity(flash)
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(partnerName) is in the doghouse. Stage: \(stage.statusText)")
        .animation(.easeInOut(duration: 0.8), value: stage)
        .task(id: stage.showClouds) {
            guard stage.showClouds else { return }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: true)) { cloudDrift = 40 }
        }
        .task(id: stage.lightning) { await runLightning() }
    }

    // MARK: - Colours

    private typealias RGB = (Double, Double, Double)

    private func mix(_ a: RGB, _ b: RGB, _ t: Double) -> Color {
        Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }

    // MARK: - Sky

    private var skyGradient: LinearGradient {
        LinearGradient(
            colors: [mix((0.74, 0.79, 0.88), (0.11, 0.12, 0.20), gloom),
                     mix((0.60, 0.65, 0.74), (0.19, 0.21, 0.31), gloom)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var sky: some View { skyGradient }

    private var nightSky: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(Double((i * 37) % 5) / 10 + 0.3))
                    .frame(width: CGFloat((i * 13) % 3) + 1.5)
                    .offset(x: CGFloat((i * 7919) % 340) - 170, y: CGFloat((i * 104729) % 120) - 150)
            }
            Circle()
                .fill(Color(red: 0.96, green: 0.95, blue: 0.86))
                .frame(width: 30)
                .shadow(color: .white.opacity(0.5), radius: 12)
                .overlay(Circle().fill(skyGradient).frame(width: 24).offset(x: 9, y: -6))
                // Clear of the status pill, which spans the top centre.
                .offset(x: 150, y: -82)
        }
        .transition(.opacity)
    }

    // MARK: - Hills & Ground

    private var hills: some View {
        ZStack {
            Ellipse()
                .fill(mix((0.36, 0.52, 0.34), (0.15, 0.19, 0.25), gloom))
                .frame(width: 400, height: 150)
                .offset(x: -110, y: 118)
            Ellipse()
                .fill(mix((0.30, 0.46, 0.30), (0.12, 0.15, 0.21), gloom))
                .frame(width: 360, height: 130)
                .offset(x: 120, y: 128)
        }
    }

    private var ground: some View {
        VStack {
            Spacer()
            ZStack {
                LinearGradient(
                    colors: [mix((0.44, 0.60, 0.34), (0.32, 0.30, 0.25), min(1, gloom * 1.3)),
                             mix((0.34, 0.48, 0.26), (0.24, 0.22, 0.18), min(1, gloom * 1.3))],
                    startPoint: .top, endPoint: .bottom
                )

                // Worn dirt patch where the house stands, centred 120pt below
                // the scene centre: 4pt under the house's base (116pt), so the
                // house sits on it with the patch's front edge showing.
                Ellipse()
                    .fill(mix((0.55, 0.42, 0.26), (0.30, 0.24, 0.17), gloom).opacity(0.85))
                    .frame(width: 230, height: 30)
                    .offset(y: -11)

                if stage.showDirty {
                    ForEach(0..<4, id: \.self) { i in
                        Ellipse()
                            .fill(Color(red: 0.30, green: 0.22, blue: 0.13).opacity(0.7))
                            .frame(width: CGFloat(14 + i * 6), height: CGFloat(5 + i))
                            .offset(x: CGFloat([-120, -30, 70, 130][i]), y: CGFloat([8, 16, 4, 14][i]))
                    }
                    .transition(.opacity)
                }

                if stage.showPuddles {
                    puddle.frame(width: 54, height: 12).offset(x: 78, y: 12)
                    puddle.frame(width: 34, height: 8).offset(x: -60, y: 18)
                }

                if stage.showSnow {
                    Rectangle()
                        .fill(Color(red: 0.90, green: 0.93, blue: 0.97).opacity(0.85))
                        .mask(alignment: .top) { Rectangle().frame(height: 16) }
                        .transition(.opacity)
                }

                // Grass tufts along the edge, thinning as the yard turns to mud.
                if !stage.showSnow {
                    HStack(spacing: 26) {
                        ForEach(0..<9, id: \.self) { i in
                            Triangle()
                                .fill(mix((0.32, 0.50, 0.24), (0.28, 0.26, 0.20), gloom))
                                .frame(width: 8, height: CGFloat(i % 2 == 0 ? 10 : 7))
                                .opacity(stage.showDirty ? 0.5 : 1)
                        }
                    }
                    .offset(y: -25)
                }
            }
            .frame(height: 58)
        }
    }

    private var puddle: some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.75),
                                          Color(red: 0.40, green: 0.47, blue: 0.62).opacity(0.55)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Ellipse().stroke(Color.white.opacity(0.3), lineWidth: 1).scaleEffect(x: 0.45, y: 0.4).offset(x: -8, y: -1))
            .transition(.opacity)
    }

    // MARK: - Fence & Tree

    private var fence: some View {
        let wood = mix((0.58, 0.42, 0.26), (0.28, 0.24, 0.20), gloom)
        return ZStack {
            ForEach(0..<2, id: \.self) { r in
                RoundedRectangle(cornerRadius: 1.5).fill(wood.opacity(0.9))
                    .frame(width: 66, height: 4).offset(y: CGFloat(r == 0 ? -8 : 8))
            }
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(wood)
                        .frame(width: 7, height: 36)
                        // One picket gives up once things get grim.
                        .rotationEffect(.degrees(stage.showDirty && i == 3 ? 14 : 0), anchor: .bottom)
                        .offset(y: stage.showDirty && i == 3 ? 4 : 0)
                }
            }
        }
    }

    private var tree: some View {
        let bark = mix((0.36, 0.26, 0.18), (0.14, 0.12, 0.12), gloom)
        // Drawn with the trunk's foot at the bottom of the frame, so the
        // frame's bottom edge is what sits on the ground.
        return Path { p in
            p.move(to: CGPoint(x: 35, y: 120))
            p.addQuadCurve(to: CGPoint(x: 39, y: 24), control: CGPoint(x: 29, y: 70))
            p.move(to: CGPoint(x: 37, y: 62))
            p.addQuadCurve(to: CGPoint(x: 5, y: 36), control: CGPoint(x: 23, y: 54))
            p.move(to: CGPoint(x: 38, y: 48))
            p.addQuadCurve(to: CGPoint(x: 65, y: 20), control: CGPoint(x: 49, y: 42))
            p.move(to: CGPoint(x: 39, y: 30))
            p.addQuadCurve(to: CGPoint(x: 23, y: 2), control: CGPoint(x: 33, y: 20))
        }
        .stroke(bark, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        .frame(width: 70, height: 120)
        .modifier(WindSway(strength: stage.windStrength, enabled: !reduceMotion))
    }

    // MARK: - Clouds

    private var clouds: some View {
        VStack {
            HStack(spacing: 34) {
                stormCloud.offset(x: cloudDrift * 0.6)
                stormCloud.scaleEffect(0.75).offset(x: -cloudDrift, y: 6)
                stormCloud.scaleEffect(0.9).offset(x: cloudDrift * 0.4, y: -3)
            }
            .padding(.top, 34)
            Spacer()
        }
        .transition(.opacity)
    }

    private var stormCloud: some View {
        let c = mix((0.46, 0.49, 0.58), (0.20, 0.21, 0.28), gloom)
        return ZStack {
            Capsule().fill(c).frame(width: 60, height: 20)
            Circle().fill(c).frame(width: 30).offset(x: -12, y: -9)
            Circle().fill(c.opacity(0.95)).frame(width: 22).offset(x: 13, y: -7)
        }
    }

    // MARK: - House

    private var house: some View {
        ZStack {
            // Shadow on the dirt patch: the wall's base is 76pt below the group
            // centre, and this sits just under it, inside the patch.
            Ellipse().fill(Color.black.opacity(0.28)).frame(width: 196, height: 14).offset(y: 78)

            houseBody.offset(y: 20)
            // Shadow the roof slab throws on the wall
            Rectangle().fill(Color.black.opacity(0.22)).frame(width: 160, height: 6).offset(y: -30)

            roof.offset(y: -38)

            if stage.showRoofPatch { roofPatch.offset(x: 42, y: -39).transition(.opacity) }
            if stage.showIcicles { icicleRow.offset(y: -22).transition(.opacity) }
            if stage.showDirty { cobweb.offset(x: -70, y: -20).transition(.opacity) }

            door.offset(y: 37)

            // The dog, with everything that happens to it. The offset seats
            // its paws level with the bottom of the doorway (73pt below the
            // group centre): the avatar's paws sit ~24pt below its own centre,
            // so 48 + 24 ≈ 72 puts the feet just inside the door.
            dog.offset(y: 48)

            nameplate.offset(y: -14)

            if stage.showHunger {
                // On the wall just right of the doorway, level with the dog's
                // head; its trail steps into the doorway towards the dog.
                thoughtBubble.offset(x: 58, y: 16).transition(.scale.combined(with: .opacity))
                // On the dirt patch in front of the wall: the bowl's base
                // (7pt below its centre) lands 10pt in front of the wall's.
                emptyBowl.offset(x: -94, y: 79).transition(.opacity)
            }
            if stage.showFlies { flies.offset(x: -72, y: 28).transition(.opacity) }
            if stage.showMouse { mouse.offset(x: 82, y: 46).transition(.move(edge: .trailing).combined(with: .opacity)) }
            if stage.showLeaves { blownLeaves.transition(.opacity) }
        }
    }

    private var wallTop: Color { mix((0.58, 0.39, 0.22), (0.30, 0.20, 0.12), gloom * 0.7) }
    private var wallBottom: Color { mix((0.45, 0.29, 0.15), (0.22, 0.14, 0.08), gloom * 0.7) }
    private var roofTop: Color { mix((0.42, 0.25, 0.13), (0.20, 0.12, 0.07), gloom * 0.7) }
    private var roofBottom: Color { mix((0.32, 0.18, 0.09), (0.14, 0.08, 0.05), gloom * 0.7) }

    private var houseBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [wallTop, wallBottom], startPoint: .top, endPoint: .bottom))
            // Planks
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle().fill(Color.clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.22)).frame(height: 1.5) }
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // Nail heads at the plank ends
            ForEach(0..<4, id: \.self) { i in
                ForEach([-70, 70], id: \.self) { x in
                    Circle().fill(Color.black.opacity(0.35)).frame(width: 2.5)
                        .offset(x: CGFloat(x), y: CGFloat(i * 22 - 34))
                }
            }
            if stage.showDirty {
                Path { p in
                    p.move(to: CGPoint(x: 120, y: 0))
                    p.addLine(to: CGPoint(x: 126, y: 16))
                    p.addLine(to: CGPoint(x: 118, y: 30))
                    p.addLine(to: CGPoint(x: 127, y: 48))
                }
                .stroke(Color.black.opacity(0.4), lineWidth: 1.2)
                .transition(.opacity)
            }
            RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.35), lineWidth: 1)
        }
        .frame(width: 160, height: 112)
    }

    /// A flat roof: a slab of planks overhanging the walls by a hand's width.
    private var roof: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [roofTop, roofBottom], startPoint: .top, endPoint: .bottom))
            // Two plank seams along the slab
            VStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1.2)
                }
            }
            .padding(.horizontal, 6)
            // Lit top edge
            RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.14), lineWidth: 1.5)
                .mask(alignment: .top) { Rectangle().frame(height: 3) }
            RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4), lineWidth: 1)
            if stage.showSnow {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 180, height: 9)
                    .offset(y: -9)
                    .transition(.opacity)
            }
        }
        .frame(width: 178, height: 16)
    }

    private var door: some View {
        let arch = UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 28)
        return ZStack {
            arch.fill(mix((0.62, 0.44, 0.26), (0.34, 0.24, 0.15), gloom)).frame(width: 70, height: 72)
            arch.fill(LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 62, height: 66).offset(y: 3)
        }
    }

    private var nameplate: some View {
        Text("DOGHOUSE")
            .font(.dhBadge)
            .foregroundStyle(Color(red: 0.98, green: 0.92, blue: 0.78).opacity(0.9))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(mix((0.50, 0.34, 0.18), (0.26, 0.18, 0.11), gloom)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.35), lineWidth: 1))
    }

    private var dog: some View {
        ZStack {
            AvatarView(avatar: DogAvatar.avatar(for: avatarId), mood: avatarMood, size: 50, cosmetics: cosmetics)
                .scaleEffect(showBellyRubBurst ? 1.14 : 1.0)
                .animation(.spring(duration: 0.25), value: showBellyRubBurst)
                .dogHop(hop)
                .modifier(Shiver(level: stage.shiverLevel, enabled: !reduceMotion))

            if showBellyRubBurst {
                HeartBurstView().scaleEffect(0.6).allowsHitTesting(false)
            }
            if showRoses {
                Text("💐").font(.system(size: 24)).offset(x: 34, y: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard onBellyRub != nil else { return }
                onBellyRub?()
                showBellyRubBurst = true
                DogHop.perform($hop)
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    showBellyRubBurst = false
                }
            }
        )
        .onChange(of: jumpTrigger) { _, _ in DogHop.perform($hop) }
    }

    // MARK: - Weather (Canvas)

    private var weather: some View {
        let intensity = stage.rainIntensity
        let wind = stage.windStrength
        let snowing = stage.showSnow
        let boltPoints = bolt
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                Self.drawPrecipitation(&g, size: size, t: t, intensity: intensity, wind: wind, snowing: snowing)
                if let boltPoints { Self.drawBolt(&g, size: size, points: boltPoints) }
            }
        }
        .allowsHitTesting(false)
    }

    private static func drawPrecipitation(_ g: inout GraphicsContext, size: CGSize, t: Double,
                                          intensity: Double, wind: Double, snowing: Bool) {
        guard intensity > 0 else { return }
        let count = Int(intensity * 70)
        for i in 0..<count {
            let fx = Double((i * 7919) % 1000) / 1000
            let fy = Double((i * 104729) % 1000) / 1000
            let fs = Double((i * 31) % 10) / 10
            if snowing {
                let speed = 26 + 24 * fs
                let y = (fy * size.height + t * speed).truncatingRemainder(dividingBy: size.height + 12) - 6
                let x = fx * size.width + sin(t * 1.3 + Double(i)) * 9
                let r = 1.6 + 1.6 * fs
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.white.opacity(0.85)))
            } else {
                let speed = 320 + 180 * fs
                let len = 8 + 6 * fs + 8 * intensity
                let y = (fy * size.height + t * speed).truncatingRemainder(dividingBy: size.height + len) - len
                var x = (fx * size.width - t * 40 * wind).truncatingRemainder(dividingBy: size.width)
                if x < 0 { x += size.width }
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - wind * 5, y: y + len))
                g.stroke(path, with: .color(.white.opacity(0.26 + 0.24 * intensity)), lineWidth: 1.1 + 0.9 * fs)
            }
        }
    }

    private static func drawBolt(_ g: inout GraphicsContext, size: CGSize, points: [CGPoint]) {
        var path = Path()
        for (i, pt) in points.enumerated() {
            let p = CGPoint(x: pt.x * size.width, y: pt.y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        g.stroke(path, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(Color(red: 0.95, green: 0.96, blue: 1.0)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    private static func makeBolt() -> [CGPoint] {
        var x = CGFloat.random(in: 0.28...0.72)
        var y: CGFloat = 8
        var pts = [CGPoint(x: x, y: y)]
        for _ in 0..<Int.random(in: 6...8) {
            x += .random(in: -0.07...0.07)
            y += .random(in: 18...28)
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }

    /// Distant stage: a flash on the horizon now and then. Storm stage: bolts
    /// overhead with a double flicker. Cancelled and restarted by `.task(id:)`
    /// whenever the stage's lightning mode changes.
    private func runLightning() async {
        guard stage.lightning != .none else { return }
        let storm = stage.lightning == .storm
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(storm ? Double.random(in: 4...11) : Double.random(in: 9...20)))
            if Task.isCancelled { return }
            if storm { bolt = Self.makeBolt() }
            if reduceMotion {
                try? await Task.sleep(for: .milliseconds(220))
            } else {
                withAnimation(.easeIn(duration: 0.04)) { flash = storm ? 0.55 : 0.26 }
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeOut(duration: 0.12)) { flash = 0.08 }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeIn(duration: 0.04)) { flash = storm ? 0.38 : 0.18 }
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            }
            bolt = nil
        }
    }

    // MARK: - Status

    // MARK: - Props

    private var roofPatch: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(red: 0.45, green: 0.32, blue: 0.18))
            .frame(width: 34, height: 9)
            .overlay(HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.black.opacity(0.55)).frame(width: 2) }
            })
            .rotationEffect(.degrees(-5))
    }

    private var icicleRow: some View {
        HStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { i in
                Triangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.9), Color(red: 0.75, green: 0.88, blue: 0.98).opacity(0.7)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: i % 2 == 0 ? 14 : 9)
                    .rotationEffect(.degrees(180))
            }
        }
    }

    private var cobweb: some View {
        Path { p in
            for end in [CGPoint(x: 22, y: 14), CGPoint(x: 16, y: 22), CGPoint(x: 6, y: 24)] {
                p.move(to: .zero); p.addLine(to: end)
            }
            p.move(to: CGPoint(x: 8, y: 5)); p.addQuadCurve(to: CGPoint(x: 5, y: 9), control: CGPoint(x: 7, y: 8))
            p.move(to: CGPoint(x: 15, y: 10)); p.addQuadCurve(to: CGPoint(x: 10, y: 17), control: CGPoint(x: 14, y: 15))
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
        .frame(width: 25, height: 25)
    }

    private var emptyBowl: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.25)).frame(width: 36, height: 6).offset(y: 7)
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 9, bottomTrailingRadius: 9, topTrailingRadius: 2)
                .fill(Color(red: 0.75, green: 0.28, blue: 0.24)).frame(width: 30, height: 14)
            Ellipse().fill(Color.black.opacity(0.35)).frame(width: 24, height: 5).offset(y: -5)
            Text("🦴").font(.system(size: 7)).opacity(0.85).offset(y: 2)
        }
    }

    private var thoughtBubble: some View {
        ZStack {
            Ellipse().fill(Color.white.opacity(0.95)).frame(width: 42, height: 32)
            Text("🍕").font(.system(size: 17))
            // Trail down-left towards the dog's head.
            Circle().fill(Color.white.opacity(0.85)).frame(width: 7).offset(x: -23, y: 13)
            Circle().fill(Color.white.opacity(0.75)).frame(width: 4).offset(x: -30, y: 18)
        }
    }

    private var flies: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.black.opacity(0.7)).frame(width: 3)
                    .phaseAnimator([0, 1, 2], content: { v, phase in
                        v.offset(x: CGFloat(i * 8 - 8) + CGFloat([3, -3, 1][phase]),
                                 y: CGFloat((i % 2) * 6 - 3) + CGFloat([-4, 4, -1][phase]))
                    }, animation: { _ in .easeInOut(duration: 0.45) })
            }
        }
    }

    private var mouse: some View {
        ZStack {
            Ellipse().fill(Color.gray).frame(width: 20, height: 14)
            Circle().fill(Color.gray.opacity(0.8)).frame(width: 8).offset(x: -6, y: -8)
            Circle().fill(Color.gray.opacity(0.8)).frame(width: 8).offset(x: 6, y: -8)
            Circle().fill(Color.black).frame(width: 3).offset(x: -3, y: -2)
            Circle().fill(Color.black).frame(width: 3).offset(x: 3, y: -2)
            Circle().fill(Color.pink).frame(width: 3).offset(y: 1)
            // A Path has no size of its own; without this frame it takes the
            // whole scene and draws the tail up in the sky.
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addQuadCurve(to: CGPoint(x: 12, y: -1), control: CGPoint(x: 6, y: 9)) }
                .stroke(Color.gray, lineWidth: 1.5)
                .frame(width: 12, height: 10)
                .offset(x: 16, y: 0)
        }
        .frame(width: 24, height: 16)
    }

    private var blownLeaves: some View {
        ForEach(0..<3, id: \.self) { i in
            Ellipse()
                .fill(Color(red: 0.62, green: 0.42, blue: 0.18))
                .frame(width: 10, height: 6)
                .phaseAnimator([0, 1], content: { v, phase in
                    v.rotationEffect(.degrees(phase == 0 ? 0 : 300))
                        .offset(x: phase == 0 ? -110 : 110, y: CGFloat([38, 55, 20][i]) + (phase == 0 ? 0 : 18))
                        .opacity(phase == 0 ? 0 : 1)
                }, animation: { _ in .easeInOut(duration: 3.2 + Double(i) * 0.7) })
        }
    }
}

// MARK: - Motion Modifiers

/// Cold-dog jitter. Level 0 is still; 3 is teeth chattering.
private struct Shiver: ViewModifier {
    let level: Int
    let enabled: Bool

    private var amplitude: CGFloat { [0, 1.2, 2.2, 3.4][min(max(level, 0), 3)] }
    private var period: Double { [1, 0.1, 0.075, 0.05][min(max(level, 0), 3)] }

    @ViewBuilder
    func body(content: Content) -> some View {
        if level == 0 || !enabled {
            content
        } else {
            content.phaseAnimator([CGFloat(-1), 1, -0.6, 0.8], content: { view, phase in
                view.offset(x: phase * amplitude, y: abs(phase) * amplitude * 0.35)
            }, animation: { _ in .linear(duration: period) })
        }
    }
}

/// Trees lean with the wind. Strength 0 stands still.
private struct WindSway: ViewModifier {
    let strength: Double
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if strength == 0 || !enabled {
            content
        } else {
            content.phaseAnimator([CGFloat(-1), 1], content: { view, phase in
                view.rotationEffect(.degrees(Double(phase) * 3.5 * strength), anchor: .bottom)
            }, animation: { _ in .easeInOut(duration: 1.1) })
        }
    }
}

#Preview("Stage 1 - Just Arrived") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 0)
}

#Preview("Stage 4 - Rainy") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 25_000)
}

#Preview("Stage 7 - The Storm") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 450_000)
}

#Preview("Stage 8 - Full Survival") {
    DoghouseScene(isCurrentUser: true, partnerName: "Alex", duration: 700_000)
}
