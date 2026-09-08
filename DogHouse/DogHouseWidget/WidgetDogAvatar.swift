//
//  WidgetDogAvatar.swift
//  DogHouseWidget
//
//  A static copy of the main app's AvatarView (same 80-unit geometry, same
//  flat look) for the widget extension, which can't share the app's view
//  because that pulls in cosmetics, timers and Firebase-backed models.
//  Keep the shapes in sync with Views/Avatar/AvatarView.swift by hand.
//

import SwiftUI

enum WidgetMood {
    case happy, sad, freezing
}

struct WidgetDogAvatar: View {
    var avatarId: String
    var mood: WidgetMood = .happy
    var size: CGFloat = 80
    var showsTail: Bool = true

    private var scale: CGFloat { size / 80 }
    private var fur: Color { Self.primaryColor(for: avatarId) }
    private var muzzle: Color { Self.muzzleColor(for: avatarId) }
    private let ink = Color(red: 0.12, green: 0.08, blue: 0.08)

    var body: some View {
        ZStack {
            if showsTail { tail }
            ear(isLeft: true)
            ear(isLeft: false)
            Ellipse().fill(fur)
                .frame(width: 52 * scale, height: 40 * scale)
                .offset(y: 16 * scale)
            Circle().fill(fur)
                .frame(width: 50 * scale, height: 50 * scale)
                .offset(y: -8 * scale)
            face
            paws
            collar
            if mood == .freezing {
                Circle()
                    .fill(Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.18))
                    .frame(width: 50 * scale, height: 50 * scale)
                    .offset(y: -8 * scale)
            }
        }
        .frame(width: size, height: size)
    }

    private var tail: some View {
        Path { path in
            path.move(to: CGPoint(x: 2 * scale, y: 20 * scale))
            path.addQuadCurve(
                to: CGPoint(x: 26 * scale, y: 2 * scale),
                control: CGPoint(x: 30 * scale, y: 24 * scale)
            )
        }
        .stroke(fur, lineWidth: 10 * scale)
        .frame(width: 34 * scale, height: 28 * scale)
        .rotationEffect(.degrees(mood == .happy ? 4 : -12), anchor: UnitPoint(x: 0.08, y: 0.72))
        .offset(x: 18 * scale, y: 10 * scale)
    }

    private func ear(isLeft: Bool) -> some View {
        Ellipse()
            .fill(fur)
            .frame(width: 20 * scale, height: 26 * scale)
            .rotationEffect(.degrees(isLeft ? -6 : 6))
            .offset(x: (isLeft ? -21 : 21) * scale, y: -21 * scale)
    }

    private var face: some View {
        ZStack {
            Ellipse().fill(muzzle)
                .frame(width: 26 * scale, height: 20 * scale)
                .offset(y: 10 * scale)

            HStack(spacing: 18 * scale) {
                eye
                eye
            }
            .offset(y: -7 * scale)

            Ellipse().fill(ink)
                .frame(width: 9 * scale, height: 6 * scale)
                .offset(y: 2 * scale)

            mouth.offset(y: 12 * scale)
        }
        .offset(y: -8 * scale)
    }

    private var eye: some View {
        ZStack {
            Circle().fill(Color.white)
                .frame(width: 14 * scale, height: 14 * scale)
            Circle().fill(ink)
                .frame(width: pupilSize, height: pupilSize)
                .offset(y: mood == .sad ? 1 * scale : 0)
            Circle().fill(Color.white.opacity(0.75))
                .frame(width: 4 * scale, height: 4 * scale)
                .offset(x: 3 * scale, y: -3 * scale)
        }
        .frame(width: 14 * scale, height: 14 * scale)
        .clipShape(Circle())
    }

    private var pupilSize: CGFloat {
        switch mood {
        case .happy:    7 * scale
        case .sad:      8 * scale
        case .freezing: 5 * scale
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .happy:
            Path { path in
                path.addArc(center: CGPoint(x: 8 * scale, y: 0), radius: 8 * scale,
                            startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            }
            .stroke(ink, lineWidth: 1.5 * scale)
            .frame(width: 16 * scale, height: 8 * scale)
        case .sad:
            Path { path in
                path.addArc(center: CGPoint(x: 8 * scale, y: 8 * scale), radius: 8 * scale,
                            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            }
            .stroke(ink, lineWidth: 1.5 * scale)
            .frame(width: 16 * scale, height: 8 * scale)
        case .freezing:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5 * scale))
                path.addCurve(to: CGPoint(x: 18 * scale, y: 5 * scale),
                              control1: CGPoint(x: 4 * scale, y: 0),
                              control2: CGPoint(x: 14 * scale, y: 10 * scale))
            }
            .stroke(ink, lineWidth: 1.5 * scale)
            .frame(width: 18 * scale, height: 10 * scale)
        }
    }

    private var paws: some View {
        HStack(spacing: 13 * scale) {
            paw
            paw
        }
        .offset(y: 34 * scale)
    }

    private var paw: some View {
        RoundedRectangle(cornerRadius: 5 * scale)
            .fill(fur)
            .frame(width: 14 * scale, height: 9 * scale)
    }

    private var collar: some View {
        let bandW = 34 * scale
        let bow = 16 * scale
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: bandW, y: 0), control: CGPoint(x: bandW / 2, y: bow))
            }
            .stroke(Color(red: 0.42, green: 0.24, blue: 0.07),
                    style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round))
            .frame(width: bandW, height: bow + 2 * scale)

            Circle()
                .fill(Color(red: 0.96, green: 0.82, blue: 0.18))
                .overlay(Circle().stroke(Color(red: 0.22, green: 0.13, blue: 0.02), lineWidth: 1.5 * scale))
                .overlay(
                    Circle().fill(Color.white.opacity(0.35))
                        .frame(width: 3 * scale)
                        .offset(x: -1 * scale, y: -1 * scale)
                )
                .frame(width: 9 * scale)
                .offset(y: -1 * scale)
        }
        .offset(y: 16 * scale)
    }

    // Colours mirror DogAvatar.allAvatars in the main app.
    static func primaryColor(for id: String) -> Color {
        switch id {
        case "dog_1": Color(red: 0.82, green: 0.63, blue: 0.25)
        case "dog_2": Color(red: 0.72, green: 0.75, blue: 0.80)
        case "dog_3": Color(red: 0.90, green: 0.64, blue: 0.26)
        case "dog_4": Color(red: 0.80, green: 0.78, blue: 0.76)
        case "dog_5": Color(red: 0.97, green: 0.97, blue: 0.97)
        case "dog_6": Color(red: 0.76, green: 0.61, blue: 0.46)
        case "dog_7": Color(red: 0.88, green: 0.55, blue: 0.20)
        case "dog_8": Color(red: 0.72, green: 0.50, blue: 0.26)
        default:      Color(red: 0.82, green: 0.63, blue: 0.25)
        }
    }

    static func muzzleColor(for id: String) -> Color {
        switch id {
        case "dog_1": Color(red: 0.95, green: 0.84, blue: 0.60)
        case "dog_2": Color(red: 0.94, green: 0.94, blue: 0.96)
        case "dog_3": Color(red: 0.98, green: 0.93, blue: 0.84)
        case "dog_4": Color(red: 0.96, green: 0.95, blue: 0.94)
        case "dog_5": Color(red: 0.99, green: 0.97, blue: 0.94)
        case "dog_6": Color(red: 0.94, green: 0.84, blue: 0.70)
        case "dog_7": Color(red: 0.98, green: 0.93, blue: 0.82)
        case "dog_8": Color(red: 0.96, green: 0.87, blue: 0.70)
        default:      Color(red: 0.95, green: 0.84, blue: 0.60)
        }
    }
}
