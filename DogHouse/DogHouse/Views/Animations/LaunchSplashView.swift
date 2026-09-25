//
//  LaunchSplashView.swift
//  DogHouse
//
//  The launch sequence. LaunchScreen.storyboard shows the brand gradient, the
//  avatar's head (LaunchHead image) at HEAD_WIDTH_FRACTION of the screen width
//  in the centre, and the DogHouse wordmark near the bottom. This view lays
//  out the same picture — the head via the real AvatarView so it can blink,
//  the wordmark as the same image — blinks once, then a grey dog slides in
//  from the right and snuggles up to him while hearts rise behind them, and
//  the whole picture slides up once Firebase Auth has resolved. Frame 0 is
//  the storyboard picture exactly; all motion starts after the first blink. Numbers here mirror Design/make-app-icon-dog.py
//  (HEAD_BOX, HEAD_WIDTH_FRACTION) and the storyboard's constraints; keep all
//  three in step or the hand-off frame jumps.
//

import SwiftUI

struct LaunchSplashView: View {
    /// Set by the owner once the app is ready to be revealed. The splash never
    /// leaves before its own sequence has played, and never before this is true.
    let isReady: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var eyesClosed = false
    @State private var partnerEyesClosed = false
    /// 0 = the lone head of the storyboard frame, 1 = the snuggled pair.
    @State private var paired = false
    /// Extra lean into each other on top of the pair's resting tilt.
    @State private var nuzzling = false
    @State private var heartsFired = false
    @State private var sequenceDone = false
    @State private var dismissed = false
    @State private var slideOffset: CGFloat = 0
    @State private var opacity: Double = 1

    // Welcome gradient, light values (cozyOrange at 0.8 over white -> brown).
    private let gradientTop = Color(red: 255 / 255, green: 163 / 255, blue: 51 / 255)
    private let gradientBottom = Color(red: 139 / 255, green: 69 / 255, blue: 19 / 255)

    /// LaunchHead spans avatar units x -32...32, y -35...21 (HEAD_BOX), so its
    /// centre sits 7 units above the avatar's centre and it is 64 units wide.
    private let headBoxWidth: CGFloat = 64
    private let headBoxCentreY: CGFloat = -7
    /// Head image width as a fraction of the screen width (storyboard multiplier).
    private let headWidthFraction: CGFloat = 0.545
    /// Wordmark bottom edge above the safe area (storyboard constant).
    private let wordmarkBottomPadding: CGFloat = 28

    // The pair. Each head shrinks to `pairScale` so both fit side by side; the
    // centres sit `pairSpacing` scaled head-widths apart so the cheeks overlap.
    private let partner = DogAvatar.avatar(for: "dog_4")
    private let pairScale: CGFloat = 0.7
    private let pairSpacing: CGFloat = 0.86
    private let restingTilt: Double = 5
    private let nuzzleTilt: Double = 10

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let screen = geo.size
                let headWidth = screen.width * headWidthFraction
                let avatarSize = headWidth / headBoxWidth * 80
                let scale = avatarSize / 80
                ZStack {
                    LinearGradient(colors: [gradientTop, gradientBottom], startPoint: .top, endPoint: .bottom)

                    let centre = CGPoint(x: screen.width / 2, y: screen.height / 2 - headBoxCentreY * scale)
                    let halfGap = headWidth * pairScale * pairSpacing / 2
                    let tilt = nuzzling ? nuzzleTilt : restingTilt

                    FloatingHearts(fired: heartsFired, spread: halfGap)
                        .position(x: centre.x, y: centre.y - 10 * scale)

                    // Partner first so the golden dog's cheek sits in front.
                    // Scale/rotate/offset go BEFORE .position so each head
                    // pivots on itself, not on the screen centre.
                    head(partner, eyesClosed: partnerEyesClosed, size: avatarSize)
                        .scaleEffect(pairScale)
                        .rotationEffect(.degrees(paired ? -tilt : -18))
                        .offset(x: paired ? halfGap - (nuzzling ? 4 : 0) : screen.width * 0.9)
                        .position(centre)

                    head(DogAvatar.avatar(for: "dog_1"), eyesClosed: eyesClosed, size: avatarSize)
                        .scaleEffect(paired ? pairScale : 1)
                        .rotationEffect(.degrees(paired ? tilt : 0))
                        .offset(x: paired ? -halfGap + (nuzzling ? 4 : 0) : 0)
                        // The image is centred on screen; the avatar's own
                        // centre is 7 units below the image centre.
                        .position(centre)
                }
                .frame(width: screen.width, height: screen.height)
                .onAppear { run() }
                .onChange(of: isReady) { _, _ in dismissIfPossible(screenHeight: screen.height) }
                .onChange(of: sequenceDone) { _, _ in dismissIfPossible(screenHeight: screen.height) }
            }
            // Measure the full window, not the safe-area inset, so the head sits
            // exactly where the launch storyboard centred it.
            .ignoresSafeArea()

            // The wordmark lives OUTSIDE the safe-area-ignoring subtree so the
            // system anchors it to the real safe area, exactly like the
            // storyboard's "safeArea.bottom - 28" constraint. (Inside it,
            // geo.safeAreaInsets reads zero and the wordmark lands 34pt low —
            // the visible jump at the storyboard hand-off.)
            VStack {
                Spacer()
                Image("LaunchWordmark")
                    .padding(.bottom, wordmarkBottomPadding)
            }
        }
        .offset(y: slideOffset)
        .opacity(opacity)
        .accessibilityHidden(true)
    }

    private func head(_ avatar: DogAvatar, eyesClosed: Bool, size: CGFloat) -> some View {
        AvatarView(
            avatar: avatar,
            mood: .happy,
            size: size,
            blinks: false,
            showsTail: false,
            headOnly: true,
            blinkOverride: eyesClosed
        )
    }

    // MARK: - Sequence

    private func run() {
        Task { @MainActor in
            if reduceMotion {
                // Same wait as below: the fade must not start mid-cross-fade.
                try? await Task.sleep(for: .milliseconds(800))
                sequenceDone = true
                return
            }
            // Hold a static frame until the system's launch zoom/cross-fade is
            // over (~0.5s after the window appears). If the blink runs during
            // the cross-fade, the snapshot blends with a mid-animation frame
            // and the dog visibly shifts.
            try? await Task.sleep(for: .milliseconds(800))
            await blink()
            try? await Task.sleep(for: .milliseconds(150))
            await snuggle()
            // `-holdSplash` launch argument: linger so the splash can be
            // inspected on the simulator (the blink keeps repeating).
            if CommandLine.arguments.contains("-holdSplash") {
                try? await Task.sleep(for: .seconds(4))
            }
            sequenceDone = true
            // Still loading? Keep him alive with an occasional blink.
            while !dismissed {
                try? await Task.sleep(for: .seconds(2.2))
                if dismissed { break }
                await blink()
            }
        }
    }

    @MainActor
    private func blink() async {
        withAnimation(.easeIn(duration: 0.07)) { eyesClosed = true; partnerEyesClosed = paired }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.easeOut(duration: 0.11)) { eyesClosed = false; partnerEyesClosed = false }
        try? await Task.sleep(for: .milliseconds(160))
    }

    /// The golden dog shuffles left and shrinks while the grey one slides in
    /// from the right; they lean in, close their eyes, and hearts rise.
    @MainActor
    private func snuggle() async {
        withAnimation(.spring(duration: 0.7, bounce: 0.22)) { paired = true }
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.spring(duration: 0.45, bounce: 0.35)) { nuzzling = true }
        withAnimation(.easeIn(duration: 0.12)) { eyesClosed = true; partnerEyesClosed = true }
        heartsFired = true
        try? await Task.sleep(for: .milliseconds(420))
        withAnimation(.easeOut(duration: 0.15)) { eyesClosed = false; partnerEyesClosed = false }
        try? await Task.sleep(for: .milliseconds(330))
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { nuzzling = false }
        try? await Task.sleep(for: .milliseconds(650))
    }

    private func dismissIfPossible(screenHeight: CGFloat) {
        guard isReady, sequenceDone, !dismissed else { return }
        dismissed = true
        Task { @MainActor in
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(320))
            } else {
                withAnimation(.easeIn(duration: 0.45)) { slideOffset = -screenHeight * 1.1 }
                try? await Task.sleep(for: .milliseconds(470))
            }
            onFinished()
        }
    }
}

/// Small hearts that drift up from behind the seam between the two heads.
private struct FloatingHearts: View {
    let fired: Bool
    /// Half the distance between the head centres; hearts fan out within it.
    let spread: CGFloat

    private struct Heart {
        let x: CGFloat       // start, as a fraction of `spread`
        let drift: CGFloat   // sideways travel, fraction of `spread`
        let rise: CGFloat    // points
        let size: CGFloat
        let delay: Double
        let white: Bool
    }

    private let hearts: [Heart] = [
        Heart(x: -0.10, drift: -0.55, rise: 190, size: 33, delay: 0.00, white: false),
        Heart(x:  0.12, drift:  0.45, rise: 170, size: 24, delay: 0.12, white: true),
        Heart(x:  0.00, drift: -0.15, rise: 230, size: 27, delay: 0.25, white: false),
        Heart(x: -0.25, drift: -0.85, rise: 150, size: 20, delay: 0.35, white: true),
        Heart(x:  0.22, drift:  0.80, rise: 210, size: 30, delay: 0.45, white: false),
        Heart(x:  0.05, drift:  0.25, rise: 160, size: 18, delay: 0.60, white: true),
    ]

    private struct Motion {
        var progress: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.4
    }

    var body: some View {
        ZStack {
            ForEach(hearts.indices, id: \.self) { i in
                let h = hearts[i]
                Image(systemName: "heart.fill")
                    .font(.system(size: h.size))
                    .foregroundStyle(h.white ? Color.white : Color(red: 1, green: 0.42, blue: 0.55))
                    .keyframeAnimator(initialValue: Motion(), trigger: fired) { view, m in
                        view
                            .scaleEffect(m.scale)
                            .opacity(m.opacity)
                            .offset(x: (h.x + h.drift * m.progress) * spread, y: -h.rise * m.progress)
                    } keyframes: { _ in
                        KeyframeTrack(\.progress) {
                            LinearKeyframe(0, duration: h.delay)
                            CubicKeyframe(1, duration: 1.5)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: h.delay)
                            LinearKeyframe(0.95, duration: 0.2)
                            LinearKeyframe(0.95, duration: 0.7)
                            LinearKeyframe(0, duration: 0.6)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(0.4, duration: h.delay)
                            SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    LaunchSplashView(isReady: true) {}
}
