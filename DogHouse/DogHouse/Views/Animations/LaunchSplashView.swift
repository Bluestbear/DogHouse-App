//
//  LaunchSplashView.swift
//  DogHouse
//
//  The launch sequence. LaunchScreen.storyboard shows the brand gradient, the
//  avatar's head (LaunchHead image) at HEAD_WIDTH_FRACTION of the screen width
//  in the centre, and the DogHouse wordmark near the bottom. This view lays
//  out the same picture — the head via the real AvatarView so it can blink,
//  the wordmark as the same image — blinks once, and slides up once Firebase
//  Auth has resolved. Numbers here mirror Design/make-app-icon-dog.py
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

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let screen = geo.size
                let headWidth = screen.width * headWidthFraction
                let avatarSize = headWidth / headBoxWidth * 80
                let scale = avatarSize / 80
                ZStack {
                    LinearGradient(colors: [gradientTop, gradientBottom], startPoint: .top, endPoint: .bottom)

                    AvatarView(
                        avatar: DogAvatar.avatar(for: "dog_1"),
                        mood: .happy,
                        size: avatarSize,
                        blinks: false,
                        showsTail: false,
                        headOnly: true,
                        blinkOverride: eyesClosed
                    )
                    // The image is centred on screen; the avatar's own centre is
                    // 7 units below the image centre.
                    .position(x: screen.width / 2, y: screen.height / 2 - headBoxCentreY * scale)
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
        withAnimation(.easeIn(duration: 0.07)) { eyesClosed = true }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.easeOut(duration: 0.11)) { eyesClosed = false }
        try? await Task.sleep(for: .milliseconds(160))
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

#Preview {
    LaunchSplashView(isReady: true) {}
}
