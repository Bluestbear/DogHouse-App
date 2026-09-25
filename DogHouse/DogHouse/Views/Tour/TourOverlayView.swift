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
    /// The target once it has stopped moving. The spotlight and card are
    /// revealed against this, not the live frame: a control that is still
    /// scrolling into place (Profile's list settles in two hops when the tab
    /// is created for the tour) would otherwise show the ring at a halfway
    /// position and then slide it.
    @State private var settledTarget: CGRect?

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

                // An anchored step whose control is not laid out yet (a tab
                // created lazily, a row still scrolling in) shows only the
                // dim until the control exists. Centring the card meanwhile
                // and then sliding it to the control read as a "flip".
                let ready = step.anchor == nil || (target != nil && settledTarget == target)
                let shown = ready ? target : nil

                ZStack {
                    backdrop(cutout: shown)
                    if let shown {
                        spotlightRing(shown)
                            .transition(.opacity)
                    }
                    if ready {
                        callout(step: step, target: shown, bounds: bounds)
                            // A new card per step: steps cross-fade instead
                            // of one card sliding across the screen.
                            .id(step)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: step)
                .animation(.easeInOut(duration: 0.35), value: shown)
                .transition(.opacity)
                // Restarts whenever the step or the live frame changes; the
                // target counts as settled once it has held still this long.
                .task(id: SettleKey(step: step, target: target)) {
                    settledTarget = nil
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    settledTarget = target
                }
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
        var shape = frame
        if anchor.isCircular {
            let side = min(shape.width, shape.height)
            shape = CGRect(x: shape.midX - side / 2, y: shape.midY - side / 2, width: side, height: side)
        }
        let cutout = shape
            .offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            .insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
        // Whatever the anchor reports, the ring must stay on screen: a
        // cut-off ring reads as a layout bug, not a highlight.
        let clamped = cutout.intersection(bounds.insetBy(dx: 4, dy: 4).offsetBy(dx: -bounds.minX, dy: -bounds.minY))
        return clamped.isNull ? cutout : clamped
    }

    /// Every tour target registers its own frame with `.tourAnchor`.
    private func windowFrame(for anchor: TourAnchorID) -> CGRect? {
        anchors.frames[anchor]
    }

    // MARK: - Layers

    /// The dim, with the spotlight punched out of it. The hole is a separate
    /// view knocked out with `destinationOut`, so it fades in and out on its
    /// own and moves with the same animation as the ring — an even-odd path
    /// animating from a zero rect grew the hole out of the screen's corner
    /// whenever a step's control was not there yet.
    private func backdrop(cutout: CGRect?) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.62))
            if let cutout {
                RoundedRectangle(cornerRadius: spotlightRadius)
                    .fill(.black)
                    .frame(width: cutout.width, height: cutout.height)
                    .position(x: cutout.midX, y: cutout.midY)
                    .blendMode(.destinationOut)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
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
            // Scale BEFORE positioning. `.position` makes the view fill the
            // overlay, so a scale applied after it pivoted on the screen's
            // centre and pushed the ring ~10 pt off its control at the top
            // (toolbar) and bottom (send button) of the screen.
            .scaleEffect(pulse ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .position(x: target.midX, y: target.midY)
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

private struct SettleKey: Equatable {
    let step: TourStep
    let target: CGRect?
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

#Preview {
    ZStack {
        Color.cozyOrange.opacity(0.2).ignoresSafeArea()
        TourOverlayView(userName: "Harrison", partnerName: "Sam")
            .onAppear { TourCoordinator.shared.start() }
    }
}
