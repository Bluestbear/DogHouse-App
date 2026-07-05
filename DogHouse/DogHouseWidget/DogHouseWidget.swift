//
//  DogHouseWidget.swift
//  DogHouseWidget
//
//  Lock screen & home screen widget showing both dogs' moods.
//  SETUP REQUIRED:
//  1. In Xcode: File > New > Target > Widget Extension, name "DogHouseWidget",
//     uncheck "Include Live Activity" and "Include Configuration App Intent".
//  2. For BOTH the DogHouse app target and DogHouseWidget target:
//     Signing & Capabilities > + Capability > App Groups
//     Add group: group.YOUR_BUNDLE_ID (e.g. group.com.harrisonkrampe.doghouse)
//     Update appGroupId constant below to match.
//  3. Replace the generated DogHouseWidget.swift content with this file.
//

import WidgetKit
import SwiftUI

// Must match the App Group ID configured in both targets' capabilities.
private let appGroupId = "group.com.harrisonkrampe.doghouse"

// MARK: - Timeline Entry

struct DogWidgetEntry: TimelineEntry {
    let date: Date
    let myAvatarId: String
    let partnerAvatarId: String
    let myInDoghouse: Bool
    let partnerInDoghouse: Bool

    static let placeholder = DogWidgetEntry(
        date: .now, myAvatarId: "dog_1", partnerAvatarId: "dog_2",
        myInDoghouse: false, partnerInDoghouse: false
    )
}

// MARK: - Timeline Provider

struct DogWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DogWidgetEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DogWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DogWidgetEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 15 min; the main app also calls WidgetCenter.reloadAllTimelines on changes.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> DogWidgetEntry {
        let d = UserDefaults(suiteName: appGroupId)
        return DogWidgetEntry(
            date: .now,
            myAvatarId: d?.string(forKey: "widget_myAvatarId") ?? "dog_1",
            partnerAvatarId: d?.string(forKey: "widget_partnerAvatarId") ?? "dog_2",
            myInDoghouse: d?.bool(forKey: "widget_myInDoghouse") ?? false,
            partnerInDoghouse: d?.bool(forKey: "widget_partnerInDoghouse") ?? false
        )
    }
}

// MARK: - Widget Definition

struct DogHouseWidget: Widget {
    let kind = "DogHouseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DogWidgetProvider()) { entry in
            DogWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("DogHouse Status")
        .description("See both dogs — smiling at home, sad in the doghouse.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

// MARK: - Widget Bundle

@main
struct DogHouseWidgetBundle: WidgetBundle {
    var body: some Widget {
        DogHouseWidget()
    }
}

// MARK: - Widget View (dispatches by family)

struct DogWidgetView: View {
    var entry: DogWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockScreenDogWidget(entry: entry)
        default:
            HomeScreenDogWidget(entry: entry)
        }
    }
}

// MARK: - Lock Screen (.accessoryRectangular)

struct LockScreenDogWidget: View {
    var entry: DogWidgetEntry

    var body: some View {
        HStack(spacing: 0) {
            dogColumn(avatarId: entry.myAvatarId, inDoghouse: entry.myInDoghouse, label: "You")

            Rectangle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 0.5)
                .padding(.vertical, 8)

            dogColumn(avatarId: entry.partnerAvatarId, inDoghouse: entry.partnerInDoghouse, label: "Partner")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dogColumn(avatarId: String, inDoghouse: Bool, label: String) -> some View {
        VStack(spacing: 3) {
            WidgetDogFace(avatarId: avatarId, isHappy: !inDoghouse, size: 42)

            Text(inDoghouse ? "In Doghouse" : "At Home")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Home Screen (.systemSmall)

struct HomeScreenDogWidget: View {
    var entry: DogWidgetEntry

    var body: some View {
        VStack(spacing: 6) {
            Text("DogHouse 🐕")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                dogBlock(avatarId: entry.myAvatarId, inDoghouse: entry.myInDoghouse, label: "You")
                dogBlock(avatarId: entry.partnerAvatarId, inDoghouse: entry.partnerInDoghouse, label: "Partner")
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
    }

    private func dogBlock(avatarId: String, inDoghouse: Bool, label: String) -> some View {
        VStack(spacing: 4) {
            WidgetDogFace(avatarId: avatarId, isHappy: !inDoghouse, size: 54)

            Text(label)
                .font(.system(size: 10, weight: .semibold))

            Text(inDoghouse ? "Doghouse" : "Home")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(inDoghouse ? .red : .green)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Dog Face Canvas

struct WidgetDogFace: View {
    var avatarId: String
    var isHappy: Bool
    var size: CGFloat = 44

    private var primary: Color { Self.primaryColor(for: avatarId) }
    private var muzzle: Color { Self.muzzleColor(for: avatarId) }

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 80
            let cx = sz.width / 2
            let cy = sz.height / 2 + 2 * s

            // Ears (behind head)
            for side: CGFloat in [-1, 1] {
                var ear = Path()
                ear.move(to: CGPoint(x: cx + side*18*s, y: cy - 20*s))
                ear.addCurve(
                    to: CGPoint(x: cx + side*34*s, y: cy - 36*s),
                    control1: CGPoint(x: cx + side*32*s, y: cy - 20*s),
                    control2: CGPoint(x: cx + side*38*s, y: cy - 28*s)
                )
                ear.addCurve(
                    to: CGPoint(x: cx + side*20*s, y: cy - 20*s),
                    control1: CGPoint(x: cx + side*28*s, y: cy - 42*s),
                    control2: CGPoint(x: cx + side*14*s, y: cy - 32*s)
                )
                ear.closeSubpath()
                ctx.fill(ear, with: .color(primary.opacity(0.8)))
            }

            // Head
            let head = Path(ellipseIn: CGRect(x: cx-28*s, y: cy-28*s, width: 56*s, height: 52*s))
            ctx.fill(head, with: .color(primary))

            // Muzzle
            let muz = Path(ellipseIn: CGRect(x: cx-14*s, y: cy+4*s, width: 28*s, height: 18*s))
            ctx.fill(muz, with: .color(muzzle))

            // Nose
            let nose = Path(ellipseIn: CGRect(x: cx-7*s, y: cy+4*s, width: 14*s, height: 8*s))
            ctx.fill(nose, with: .color(.black.opacity(0.8)))

            // Eyes
            for side: CGFloat in [-1, 1] {
                let eyeX = cx + side*15*s
                let eyeY = cy - 10*s
                if isHappy {
                    let eye = Path(ellipseIn: CGRect(x: eyeX-4*s, y: eyeY-4*s, width: 8*s, height: 8*s))
                    ctx.fill(eye, with: .color(.black))
                    let shine = Path(ellipseIn: CGRect(x: eyeX+0.5*s, y: eyeY-3*s, width: 2.5*s, height: 2.5*s))
                    ctx.fill(shine, with: .color(.white.opacity(0.75)))
                } else {
                    var sadEye = Path()
                    sadEye.move(to: CGPoint(x: eyeX-4*s, y: eyeY+1*s))
                    sadEye.addQuadCurve(
                        to: CGPoint(x: eyeX+4*s, y: eyeY+1*s),
                        control: CGPoint(x: eyeX, y: eyeY-5*s)
                    )
                    ctx.stroke(sadEye, with: .color(.black.opacity(0.85)), lineWidth: 1.5*s)
                }
            }

            // Mouth
            var mouth = Path()
            if isHappy {
                mouth.move(to: CGPoint(x: cx-8*s, y: cy+15*s))
                mouth.addQuadCurve(to: CGPoint(x: cx+8*s, y: cy+15*s), control: CGPoint(x: cx, y: cy+22*s))
            } else {
                mouth.move(to: CGPoint(x: cx-8*s, y: cy+20*s))
                mouth.addQuadCurve(to: CGPoint(x: cx+8*s, y: cy+20*s), control: CGPoint(x: cx, y: cy+13*s))
            }
            ctx.stroke(mouth, with: .color(.black.opacity(0.6)), lineWidth: 1.5*s)

            // Tears when sad
            if !isHappy {
                for (dx, dy): (CGFloat, CGFloat) in [(-18, -6), (14, -6)] {
                    let tear = Path(ellipseIn: CGRect(x: cx+dx*s, y: cy+dy*s, width: 4*s, height: 7*s))
                    ctx.fill(tear, with: .color(.blue.opacity(0.55)))
                }
            }
        }
        .frame(width: size, height: size)
    }

    // Avatar colors mirror DogAvatar.allAvatars in the main app.
    private static func primaryColor(for id: String) -> Color {
        switch id {
        case "dog_1": return Color(red: 0.82, green: 0.63, blue: 0.25)
        case "dog_2": return Color(red: 0.72, green: 0.75, blue: 0.80)
        case "dog_3": return Color(red: 0.90, green: 0.64, blue: 0.26)
        case "dog_4": return Color(red: 0.80, green: 0.78, blue: 0.76)
        case "dog_5": return Color(red: 0.97, green: 0.97, blue: 0.97)
        case "dog_6": return Color(red: 0.76, green: 0.61, blue: 0.46)
        case "dog_7": return Color(red: 0.88, green: 0.55, blue: 0.20)
        case "dog_8": return Color(red: 0.72, green: 0.50, blue: 0.26)
        default:      return Color(red: 0.82, green: 0.63, blue: 0.25)
        }
    }

    private static func muzzleColor(for id: String) -> Color {
        switch id {
        case "dog_1": return Color(red: 0.95, green: 0.84, blue: 0.60)
        case "dog_2": return Color(red: 0.94, green: 0.94, blue: 0.96)
        case "dog_3": return Color(red: 0.98, green: 0.93, blue: 0.84)
        case "dog_4": return Color(red: 0.96, green: 0.95, blue: 0.94)
        case "dog_5": return Color(red: 0.99, green: 0.97, blue: 0.94)
        case "dog_6": return Color(red: 0.94, green: 0.84, blue: 0.70)
        case "dog_7": return Color(red: 0.98, green: 0.93, blue: 0.82)
        case "dog_8": return Color(red: 0.96, green: 0.87, blue: 0.70)
        default:      return Color(red: 0.95, green: 0.84, blue: 0.60)
        }
    }
}
