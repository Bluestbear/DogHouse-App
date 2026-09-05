//
//  TourOverlayView.swift
//  DogHouse
//
//  The visual half of the live tour: a dimmed backdrop with a spotlight cut
//  around the current step's control, and a callout card that sits above or
//  below it. Sits as an overlay on MainTabView so it covers every tab.
//
//  Everything is drawn in window coordinates — the anchors report their
//  frames in `.global`, and this view ignores the safe area so its origin is
//  the window's origin.
//

import SwiftUI

struct TourOverlayView: View {
    @ObservedObject private var tour = TourCoordinator.shared
    @ObservedObject private var anchors = TourAnchorStore.shared

    let userName: String
    let partnerName: String

    @State private var pulse = false

    /// Breathing room between the control's edge and the spotlight edge.
    private let spotlightPadding: CGFloat = 8
    private let spotlightRadius: CGFloat = 18
    /// A callout needs at least this much room on the side it is placed;
    /// below that it is centred instead of squashed off-screen.
    private let minimumCalloutSpace: CGFloat = 230

    var body: some View {
        GeometryReader { geo in
            if let step = tour.currentStep {
                let bounds = geo.frame(in: .global)
                let target = spotlight(for: step, in: bounds)

                ZStack {
                    backdrop(cutout: target)
                    if let target {
                        spotlightRing(target)
                    }
                    callout(step: step, target: target, bounds: bounds)
                }
                .animation(.spring(duration: 0.45), value: step)
                .animation(.spring(duration: 0.45), value: target)
                .transition(.opacity)
                .accessibilityAddTraits(.isModal)
                .onAppear { pulse = true }
                // Reset so a replayed tour gets its breathing ring back.
                .onDisappear { pulse = false }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: tour.isActive)
    }

    // MARK: - Geometry

    /// The rectangle to cut out for this step, in the overlay's own
    /// coordinates, or nil when the step has no anchor or the anchored view
    /// is not currently laid out (different tab, scrolled away, hidden).
    private func spotlight(for step: TourStep, in bounds: CGRect) -> CGRect? {
        guard let anchor = step.anchor,
              let frame = windowFrame(for: anchor),
              frame.width > 0, frame.height > 0,
              frame.intersects(bounds) else { return nil }
        return frame
            .offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            .insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
    }

    /// Registered frame first; toolbar buttons fall back to a UIKit lookup
    /// because `.tourAnchor` cannot attach to a toolbar item (see
    /// ToolbarButtonLocator). Trailing items read left to right: tasks,
    /// games, achievements.
    private func windowFrame(for anchor: TourAnchorID) -> CGRect? {
        if let registered = anchors.frames[anchor] { return registered }
        // Home's trailing toolbar has exactly three items: tasks, games,
        // achievements. The tour only points at the first two.
        let frames = ToolbarButtonLocator.trailingButtonFrames(count: 3)
        switch anchor {
        case .tasksButton: return frames.first
        case .gamesMenu: return frames.count > 1 ? frames[1] : frames.first
        default: return nil
        }
    }

    // MARK: - Layers

    private func backdrop(cutout: CGRect?) -> some View {
        SpotlightShape(cutout: cutout ?? .zero, cornerRadius: spotlightRadius)
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            // Tapping the dimmed area advances — quicker than reaching for
            // Next every time, and there is nothing else it could mean.
            .onTapGesture { tour.next() }
            .accessibilityHidden(true)
    }

    private func spotlightRing(_ target: CGRect) -> some View {
        RoundedRectangle(cornerRadius: spotlightRadius)
            .stroke(Color.cozyOrange, lineWidth: 3)
            .frame(width: target.width, height: target.height)
            .position(x: target.midX, y: target.midY)
            .scaleEffect(pulse ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Callout

    private enum Placement { case below, above, centered }

    private func placement(for target: CGRect?, in bounds: CGRect) -> Placement {
        guard let target else { return .centered }
        let below = bounds.height - target.maxY
        let above = target.minY
        if below >= minimumCalloutSpace, below >= above { return .below }
        if above >= minimumCalloutSpace { return .above }
        if below >= minimumCalloutSpace { return .below }
        return .centered
    }

    @ViewBuilder
    private func callout(step: TourStep, target: CGRect?, bounds: CGRect) -> some View {
        let content = step.content(userName: userName, partnerName: partnerName)
        let cardWidth = min(bounds.width - 40, 380)
        let place = placement(for: target, in: bounds)
        // Pointer x, relative to the card's centre, kept inside the card.
        let pointerOffset: CGFloat = {
            guard let target else { return 0 }
            let raw = target.midX - bounds.width / 2
            let limit = cardWidth / 2 - 36
            return min(max(raw, -limit), limit)
        }()

        VStack(spacing: 0) {
            switch place {
            case .below:
                Spacer().frame(height: (target?.maxY ?? 0) + 8)
                Pointer(pointsUp: true).offset(x: pointerOffset)
                card(content, step: step, width: cardWidth)
                Spacer(minLength: 0)
            case .above:
                Spacer(minLength: 0)
                card(content, step: step, width: cardWidth)
                Pointer(pointsUp: false).offset(x: pointerOffset)
                Spacer().frame(height: bounds.height - (target?.minY ?? bounds.height) + 8)
            case .centered:
                Spacer(minLength: 0)
                card(content, step: step, width: cardWidth)
                Spacer(minLength: 0)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private func card(_ content: TourStepContent, step: TourStep, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(content.emoji)
                    .font(.system(size: 34))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.dhHeading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(step.ordinal) of \(TourStep.count)")
                        .font(.dhBadge)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if !step.isLast {
                    Button("Skip") { tour.skip() }
                        .font(.dhCaptionBold)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Skip the tour")
                }
            }

            Text(content.body)
                .font(.dhBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: Double(step.ordinal), total: Double(TourStep.count))
                .tint(Color.cozyOrange)

            HStack {
                if !step.isFirst {
                    Button {
                        tour.back()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.dhCaptionBold)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.dogHouseBrown)
                }

                Spacer()

                Button {
                    HapticService.shared.lightTap()
                    tour.next()
                } label: {
                    Text(step.isLast ? "Let's go!" : "Next")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .frame(width: width, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Pointer

/// The little wedge between the card and the spotlight.
private struct Pointer: View {
    let pointsUp: Bool

    var body: some View {
        Triangle()
            .fill(Color(.systemBackground))
            .frame(width: 22, height: 11)
            .rotationEffect(pointsUp ? .zero : .degrees(180))
            .accessibilityHidden(true)
    }
}

// MARK: - Spotlight Shape

/// Full-rect fill with a rounded hole. Drawn with even-odd fill so the hole
/// really is transparent (and tappable through, if we ever want that).
struct SpotlightShape: Shape {
    var cutout: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cutout.minX, cutout.minY),
                AnimatablePair(cutout.width, cutout.height)
            )
        }
        set {
            cutout = CGRect(
                x: newValue.first.first, y: newValue.first.second,
                width: newValue.second.first, height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if cutout.width > 0, cutout.height > 0 {
            path.addRoundedRect(
                in: cutout,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
        }
        return path
    }
}

#Preview {
    ZStack {
        Color.cozyOrange.opacity(0.2).ignoresSafeArea()
        TourOverlayView(userName: "Harrison", partnerName: "Sam")
            .onAppear { TourCoordinator.shared.start() }
    }
}
