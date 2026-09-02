//
//  AvatarDialView.swift
//  DogHouse
//
//  A wheel for picking a dog. The dogs sit on a large circle whose centre is
//  below the screen: the chosen dog is at the top of the wheel, in the middle
//  of the screen, and its neighbours fall away down the arc — the next dog
//  waits in the lower right, the previous one has rolled off to the lower
//  left. Dragging turns the wheel; it settles on the nearest dog. Tap a
//  neighbour to bring it up.
//
//  Nothing is drawn behind the dogs, so whatever the screen puts underneath
//  shows through.
//

import SwiftUI

// MARK: - Geometry

/// Where each dog sits on the wheel for a given (continuous) position.
/// Pure maths, separate from the view so it can be unit-tested.
struct WheelGeometry: Equatable {
    /// Radius of the wheel. Bigger = flatter arc.
    var radius: CGFloat = 270
    /// Angle between neighbouring dogs. Chosen so the two neighbours sit
    /// just inside the screen edges on an iPhone while the dogs beyond them
    /// are already round the corner.
    var slotAngle: Angle = .degrees(33)
    /// How small a dog gets at `fadeSlots` slots from the top.
    var minScale: CGFloat = 0.42
    var minOpacity: CGFloat = 0.25
    /// Slots away from the top at which scale/opacity bottom out.
    var fadeSlots: CGFloat = 2
    /// How much a dog leans with the wheel (1 = fully tangent, 0 = upright).
    var tilt: CGFloat = 0.55

    struct Placement: Equatable {
        /// Offset from the wheel's top point.
        var offset: CGSize
        var scale: CGFloat
        var opacity: CGFloat
        var rotation: Angle
        /// Larger = drawn on top. The top dog wins.
        var zIndex: Double
    }

    /// `distance` is the dog's index minus the wheel position, in slots:
    /// 0 is the top, +1 the next dog (lower right), -1 the previous (lower left).
    func placement(forSlotDistance distance: CGFloat) -> Placement {
        let theta = slotAngle.radians * distance          // 0 = top of wheel
        let x = radius * sin(theta)
        let y = radius * (1 - cos(theta))                 // drops as it leaves the top
        let t = min(abs(distance) / fadeSlots, 1)
        return Placement(
            offset: CGSize(width: x, height: y),
            scale: 1 - (1 - minScale) * t,
            opacity: 1 - (1 - minOpacity) * t,
            rotation: .radians(theta * tilt),
            zIndex: 10 - Double(abs(distance))
        )
    }

    /// Horizontal drag distance that turns the wheel by one slot: the arc
    /// length between neighbours, so the dog under the finger keeps up with it.
    var pixelsPerSlot: CGFloat { radius * slotAngle.radians }
}

// MARK: - View

struct AvatarDialView: View {
    /// The dog at the top of the wheel. Never nil.
    @Binding var selectedId: String

    var avatars: [DogAvatar] = DogAvatar.allAvatars
    var centerSize: CGFloat = 150
    var geometry = WheelGeometry()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Continuous wheel position in slots; `round(position)` is the selection.
    @State private var position: CGFloat = 0
    @State private var dragStartPosition: CGFloat?

    /// How far the wheel is allowed to overshoot past the first/last dog
    /// while dragging, before rubber-banding back.
    private let overscroll: CGFloat = 0.35

    private var effectiveGeometry: WheelGeometry {
        guard reduceMotion else { return geometry }
        var g = geometry
        g.tilt = 0
        g.minScale = 0.8
        g.minOpacity = 0.6
        return g
    }

    private var selectedIndex: Int {
        avatars.firstIndex { $0.id == selectedId } ?? 0
    }

    var body: some View {
        VStack(spacing: 14) {
            wheel
                .frame(height: wheelHeight)

            Text(DogAvatar.avatar(for: selectedId).name)
                .font(.dhBodyBold)
                .foregroundStyle(Color.dogHouseBrown)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: selectedId)

            HStack(spacing: 6) {
                ForEach(avatars) { avatar in
                    Circle()
                        .fill(avatar.id == selectedId ? Color.cozyOrange : Color(.systemGray4))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.snappy(duration: 0.2), value: selectedId)
        }
        .onAppear { position = CGFloat(selectedIndex) }
        .onChange(of: selectedId) { _, _ in
            // Keep the wheel in sync if the caller sets the selection.
            let target = CGFloat(selectedIndex)
            if abs(position - target) > 0.001 {
                withAnimation(.spring(duration: 0.45)) { position = target }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dog picker")
        .accessibilityValue(DogAvatar.avatar(for: selectedId).name)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(index: selectedIndex + 1)
            case .decrement: select(index: selectedIndex - 1)
            @unknown default: break
            }
        }
    }

    /// Room for the top dog plus the arc its neighbours fall along.
    private var wheelHeight: CGFloat {
        let drop = effectiveGeometry.placement(forSlotDistance: effectiveGeometry.fadeSlots).offset.height
        return centerSize + drop * 0.55
    }

    private var wheel: some View {
        GeometryReader { geo in
            let g = effectiveGeometry
            // The top of the wheel sits centred horizontally, with the top
            // dog's centre a little below the top edge of this frame.
            let apex = CGPoint(x: geo.size.width / 2, y: centerSize / 2 + 8)

            ZStack {
                ForEach(Array(avatars.enumerated()), id: \.element.id) { index, avatar in
                    let distance = CGFloat(index) - position
                    let p = g.placement(forSlotDistance: distance)
                    // Dogs more than a few slots away are off-screen anyway.
                    if abs(distance) < g.fadeSlots + 1.5 {
                        AvatarView(
                            avatar: avatar,
                            mood: .happy,
                            size: centerSize,
                            blinks: avatar.id == selectedId
                        )
                        .scaleEffect(p.scale)
                        .rotationEffect(p.rotation)
                        .opacity(p.opacity)
                        .position(x: apex.x + p.offset.width, y: apex.y + p.offset.height)
                        .zIndex(p.zIndex)
                        .contentShape(Circle().scale(0.9))
                        .onTapGesture { select(index: index) }
                        .accessibilityLabel(avatar.name)
                        .accessibilityAddTraits(
                            avatar.id == selectedId ? [.isButton, .isSelected] : .isButton
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(g))
        }
    }

    private func dragGesture(_ g: WheelGeometry) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStartPosition == nil { dragStartPosition = position }
                guard let start = dragStartPosition else { return }
                // Dragging left brings the next dog up from the right.
                let raw = start - value.translation.width / g.pixelsPerSlot
                position = rubberBanded(raw)
                // Tick as the wheel passes each dog.
                let live = clampedIndex(Int(raw.rounded()))
                if avatars[live].id != selectedId {
                    selectedId = avatars[live].id
                    HapticService.shared.lightTap()
                }
            }
            .onEnded { value in
                guard let start = dragStartPosition else { return }
                dragStartPosition = nil
                // A flick may carry the wheel one dog past where the finger
                // let go, never further — it should feel weighted, not loose.
                let projected = start - value.predictedEndTranslation.width / g.pixelsPerSlot
                let landed = position.rounded()
                let target = min(max(projected.rounded(), landed - 1), landed + 1)
                select(index: Int(target), animated: true)
            }
    }

    /// Slows the wheel down past either end instead of stopping dead.
    private func rubberBanded(_ raw: CGFloat) -> CGFloat {
        let last = CGFloat(avatars.count - 1)
        if raw < 0 { return -overscroll * (1 - 1 / (1 - raw / overscroll)) }
        if raw > last { return last + overscroll * (1 - 1 / (1 + (raw - last) / overscroll)) }
        return raw
    }

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), avatars.count - 1)
    }

    private func select(index: Int, animated: Bool = true) {
        let index = clampedIndex(index)
        let changed = avatars[index].id != selectedId
        withAnimation(animated ? .spring(duration: 0.45, bounce: 0.25) : nil) {
            position = CGFloat(index)
        }
        if changed {
            selectedId = avatars[index].id
            HapticService.shared.lightTap()
        }
    }
}

#Preview {
    @Previewable @State var selected = DogAvatar.allAvatars[1].id
    return ZStack {
        LinearGradient(colors: [Color.cozyOrange.opacity(0.25), Color.dogHouseBrown.opacity(0.15)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AvatarDialView(selectedId: $selected)
    }
}
