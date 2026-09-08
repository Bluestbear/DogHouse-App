//
//  DogHouseWidget.swift
//  DogHouseWidget
//
//  Home screen widget in the style of a character widget: one dog fills the
//  frame, cropped at the bottom, with a counter and a one-liner above it.
//  In the doghouse the dog sits in the doorway, wet, shivering and sad under
//  weather that worsens with time served; at home it just smiles.
//
//  Which dog is shown (systemSmall): whoever is in the doghouse — you first,
//  then your partner — and your own smiling dog when everyone is home.
//  The state comes from the App Group; the weather and counters are derived
//  from timestamps so the timeline can advance without the app running.
//

import WidgetKit
import SwiftUI

// MARK: - Which dog a widget shows

enum WidgetFocus {
    case me, partner
    /// The minimal layout: both dogs side by side.
    case both
}

// MARK: - Timeline Entry

struct DogWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let focus: WidgetFocus

    /// The dog the single-character layouts feature.
    var hero: WidgetDog { focus == .partner ? snapshot.partner : snapshot.me }
    var heroIsMe: Bool { focus != .partner }

    var heroWeather: DoghouseWeather? {
        hero.isInDoghouse ? DoghouseWeather(elapsed: hero.doghouseElapsed(at: date)) : nil
    }

    /// The other dog's one-liner for the medium layout.
    var otherLine: String? {
        guard snapshot.hasPartner else { return nil }
        let other = heroIsMe ? snapshot.partner : snapshot.me
        let name = other.name.isEmpty ? (heroIsMe ? "Your partner" : "You") : other.name
        if other.isInDoghouse {
            return hero.isInDoghouse ? "\(name) is in the doghouse too" : "\(name) is in the doghouse"
        }
        return heroIsMe ? "\(name) is at home" : (other.name.isEmpty ? "You're at home" : "\(name) is at home")
    }
}

// MARK: - Timeline Provider

struct DogWidgetProvider: TimelineProvider {
    let focus: WidgetFocus

    func placeholder(in context: Context) -> DogWidgetEntry {
        DogWidgetEntry(date: .now, snapshot: .placeholder, focus: focus)
    }

    func getSnapshot(in context: Context, completion: @escaping (DogWidgetEntry) -> Void) {
        let snapshot: WidgetSnapshot = context.isPreview ? .gallerySample : .load()
        completion(DogWidgetEntry(date: .now, snapshot: snapshot, focus: focus))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DogWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load(now: now)
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates: Set<Date> = [now]

        // Re-render exactly when the weather gets worse for whoever is in the doghouse…
        for dog in [snapshot.me, snapshot.partner] {
            guard let since = dog.doghouseSince else { continue }
            for t in DoghouseWeather.thresholds {
                let d = since.addingTimeInterval(t + 1)
                if d > now && d < horizon { dates.insert(d) }
            }
        }
        // …and every hour so the counter ticks. The app also reloads the
        // timeline whenever the doghouse state changes.
        for h in 1...12 {
            dates.insert(now.addingTimeInterval(TimeInterval(h) * 3600))
        }

        let entries = dates.sorted().prefix(30).map { DogWidgetEntry(date: $0, snapshot: snapshot, focus: focus) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget Definitions
// Three widgets so the gallery lets you swipe between them: your dog, your
// partner's dog, and the minimal side-by-side view of both.

struct MyDogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DogHouseWidget", provider: DogWidgetProvider(focus: .me)) { entry in
            HeroDogWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Dog")
        .description("Smiling at home, or shivering in the doghouse.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct PartnerDogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DogHousePartnerWidget", provider: DogWidgetProvider(focus: .partner)) { entry in
            HeroDogWidgetView(entry: entry)
        }
        .configurationDisplayName("Partner's Dog")
        .description("Keep an eye on your partner — at home or in the doghouse.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct BothDogsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DogHouseBothWidget", provider: DogWidgetProvider(focus: .both)) { entry in
            MinimalDogsWidgetView(entry: entry)
        }
        .configurationDisplayName("Both Dogs")
        .description("A minimal view of both dogs at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct DogHouseWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyDogWidget()
        PartnerDogWidget()
        BothDogsWidget()
    }
}

// MARK: - Hero dispatch by family

struct HeroDogWidgetView: View {
    var entry: DogWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.focus == .partner && !entry.snapshot.hasPartner {
            NoPartnerView()
                .containerBackground(for: .widget) { SceneBackground(weather: nil) }
        } else if family == .systemMedium {
            MediumDogWidget(entry: entry)
                .containerBackground(for: .widget) { SceneBackground(weather: entry.heroWeather) }
        } else {
            SmallDogWidget(entry: entry)
                .containerBackground(for: .widget) { SceneBackground(weather: entry.heroWeather) }
        }
    }
}

/// Shown on the partner widget before pairing.
struct NoPartnerView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.slash")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 0.87, green: 0.45, blue: 0.22))
            Text("No partner yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.27, blue: 0.14))
            Text("Pair up in the app")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.27, blue: 0.14).opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small: the hero layout

struct SmallDogWidget: View {
    var entry: DogWidgetEntry

    var body: some View {
        ZStack(alignment: .bottom) {
            HeroScene(dog: entry.hero, weather: entry.heroWeather, scale: 1.4)

            VStack(alignment: .leading, spacing: 2) {
                CounterRow(entry: entry)
                Text(headline)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry.heroWeather == nil ? Color(red: 0.42, green: 0.27, blue: 0.14) : .white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .shadow(color: .black.opacity(entry.heroWeather == nil ? 0 : 0.45), radius: 2, y: 1)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var headline: String {
        if let weather = entry.heroWeather {
            return weather.complaint(for: entry.hero.name)
        }
        return WidgetCopy.homeLine(for: entry.hero, isMe: entry.heroIsMe)
    }
}

// MARK: - Medium: text on the left, hero on the right

struct MediumDogWidget: View {
    var entry: DogWidgetEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DogHouse")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .textCase(.uppercase)
                    .tracking(0.6)

                CounterRow(entry: entry)

                Text(headline)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let other = entry.otherLine {
                    Text(other)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .shadow(color: .black.opacity(entry.heroWeather == nil ? 0 : 0.45), radius: 2, y: 1)
            .padding(.leading, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            HeroScene(dog: entry.hero, weather: entry.heroWeather, scale: 1.35)
                .frame(width: 150)
        }
    }

    private var headline: String {
        if let weather = entry.heroWeather {
            return weather.complaint(for: entry.hero.name)
        }
        return WidgetCopy.homeLine(for: entry.hero, isMe: entry.heroIsMe)
    }

    private var primaryInk: Color {
        entry.heroWeather == nil ? Color(red: 0.42, green: 0.27, blue: 0.14) : .white.opacity(0.92)
    }
    private var secondaryInk: Color {
        entry.heroWeather == nil ? Color(red: 0.42, green: 0.27, blue: 0.14).opacity(0.6) : .white.opacity(0.6)
    }
}

enum WidgetCopy {
    static func homeLine(for dog: WidgetDog, isMe: Bool) -> String {
        if dog.name.isEmpty { return isMe ? "Happy at home" : "Your partner is at home" }
        return isMe ? "\(dog.name) is happy at home" : "\(dog.name) is at home"
    }
}

// MARK: - Counter row (icon + big number)

/// In the doghouse: a rain-cloud with an alert badge and the time served.
/// At home: a house and the time since your last release.
struct CounterRow: View {
    var entry: DogWidgetEntry

    var body: some View {
        HStack(spacing: 6) {
            icon
            if let value {
                Text(value)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.heroWeather == nil ? Color(red: 0.42, green: 0.27, blue: 0.14) : .white.opacity(0.85))
                    .monospacedDigit()
            }
        }
    }

    private var value: String? {
        if entry.hero.isInDoghouse {
            return WidgetDuration.short(entry.hero.doghouseElapsed(at: entry.date))
        }
        guard let elapsed = entry.hero.homeElapsed(at: entry.date) else { return nil }
        return WidgetDuration.short(elapsed)
    }

    @ViewBuilder
    private var icon: some View {
        if entry.hero.isInDoghouse {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "cloud.rain.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.62, green: 0.78, blue: 1.0))
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white, Color(red: 0.92, green: 0.22, blue: 0.22))
                    .offset(x: 3, y: 3)
            }
        } else {
            Image(systemName: "house.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(red: 0.87, green: 0.45, blue: 0.22))
        }
    }
}

// MARK: - Backgrounds

struct SceneBackground: View {
    var weather: DoghouseWeather?

    var body: some View {
        if let weather {
            let g = weather.gloom
            let top = Color(red: 0.13 - 0.06 * g, green: 0.17 - 0.07 * g, blue: 0.31 - 0.08 * g)
            let bottom = Color(red: 0.18 - 0.05 * g, green: 0.24 - 0.06 * g, blue: 0.40 - 0.08 * g)
            ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
                Bubbles(seed: 3, count: 14, tint: .white.opacity(0.10))
                if weather.showClouds {
                    Cloud(color: .black.opacity(0.18 + 0.12 * g))
                        .frame(width: 70, height: 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: 4, y: 6)
                }
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1.00, green: 0.94, blue: 0.82), Color(red: 0.99, green: 0.83, blue: 0.64)],
                    startPoint: .top, endPoint: .bottom
                )
                Bubbles(seed: 7, count: 8, tint: .white.opacity(0.45))
                // A sun in the corner
                Circle()
                    .fill(Color(red: 1.0, green: 0.86, blue: 0.40).opacity(0.9))
                    .frame(width: 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 10, y: -10)
            }
        }
    }
}

/// Soft dots scattered across the background, like the reference widget.
struct Bubbles: View {
    var seed: UInt64
    var count: Int
    var tint: Color

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: seed)
            for _ in 0..<count {
                let r = CGFloat(rng.next(in: 2...6))
                let x = CGFloat(rng.next(in: 0...1)) * size.width
                let y = CGFloat(rng.next(in: 0...1)) * size.height
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(tint))
            }
        }
    }
}

struct Cloud: View {
    var color: Color
    var body: some View {
        ZStack {
            Capsule().fill(color).frame(width: 60, height: 20)
            Circle().fill(color).frame(width: 30).offset(x: -12, y: -9)
            Circle().fill(color).frame(width: 22).offset(x: 13, y: -7)
        }
    }
}

// MARK: - The scene

/// The dog, bottom-anchored and cropped by the widget edge. In the doghouse it
/// sits in the doorway under the roof with rain (or snow) falling in front.
struct HeroScene: View {
    var dog: WidgetDog
    var weather: DoghouseWeather?
    var scale: CGFloat

    private var mood: WidgetMood {
        guard let weather else { return .happy }
        return weather.stage >= 3 ? .freezing : .sad
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let weather {
                Doghouse(gloom: weather.gloom, snow: weather.showSnow, scale: scale)
                    .offset(y: 22 * scale / 1.4)
            } else {
                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 80 * scale, height: 14 * scale)
                    .offset(y: 4)
            }

            ZStack {
                WidgetDogAvatar(avatarId: dog.avatarId, mood: mood, size: 80 * scale)
                if let weather {
                    WetOverlay(weather: weather, scale: scale)
                }
            }
            .offset(y: weather == nil ? 14 * scale / 1.4 : 30 * scale / 1.4)

            if let weather {
                Precipitation(weather: weather)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }
}

/// A flat-roofed plank hut with an arched doorway — the app's doghouse,
/// simplified to what fits in a widget.
struct Doghouse: View {
    var gloom: Double
    var snow: Bool
    var scale: CGFloat

    private func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }

    var body: some View {
        let wallTop = mix((0.58, 0.39, 0.22), (0.30, 0.20, 0.12), gloom * 0.7)
        let wallBottom = mix((0.45, 0.29, 0.15), (0.22, 0.14, 0.08), gloom * 0.7)
        let roofTop = mix((0.42, 0.25, 0.13), (0.20, 0.12, 0.07), gloom * 0.7)
        let roofBottom = mix((0.32, 0.18, 0.09), (0.14, 0.08, 0.05), gloom * 0.7)
        let doorFrame = mix((0.62, 0.44, 0.26), (0.34, 0.24, 0.15), gloom)
        let arch = UnevenRoundedRectangle(topLeadingRadius: 26 * scale, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 26 * scale)

        ZStack(alignment: .bottom) {
            // Wall with plank seams
            ZStack {
                RoundedRectangle(cornerRadius: 5 * scale)
                    .fill(LinearGradient(colors: [wallTop, wallBottom], startPoint: .top, endPoint: .bottom))
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle().fill(Color.clear)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.22)).frame(height: 1.2) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5 * scale))
                RoundedRectangle(cornerRadius: 5 * scale).stroke(Color.black.opacity(0.35), lineWidth: 1)
            }
            .frame(width: 96 * scale, height: 78 * scale)

            // Doorway
            ZStack {
                arch.fill(doorFrame).frame(width: 66 * scale, height: 66 * scale)
                arch.fill(LinearGradient(colors: [Color.black.opacity(0.78), Color.black.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 58 * scale, height: 60 * scale)
                    .offset(y: 3 * scale)
            }

            // Shadow the roof throws on the wall
            Rectangle().fill(Color.black.opacity(0.22))
                .frame(width: 96 * scale, height: 4 * scale)
                .padding(.bottom, 74 * scale)

            // Roof slab overhanging both sides
            ZStack {
                RoundedRectangle(cornerRadius: 3 * scale)
                    .fill(LinearGradient(colors: [roofTop, roofBottom], startPoint: .top, endPoint: .bottom))
                VStack(spacing: 3 * scale) {
                    ForEach(0..<2, id: \.self) { _ in
                        Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
                    }
                }
                .padding(.horizontal, 5 * scale)
                RoundedRectangle(cornerRadius: 3 * scale).stroke(Color.black.opacity(0.4), lineWidth: 1)
                if snow {
                    RoundedRectangle(cornerRadius: 4 * scale)
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 114 * scale, height: 6 * scale)
                        .offset(y: -6 * scale)
                }
            }
            .frame(width: 112 * scale, height: 10 * scale)
            .padding(.bottom, 76 * scale)
        }
    }
}

/// Drips, tears and shiver marks drawn over the avatar in its 80-unit space.
struct WetOverlay: View {
    var weather: DoghouseWeather
    var scale: CGFloat

    private let drop = Color(red: 0.55, green: 0.75, blue: 1.0)

    var body: some View {
        ZStack {
            // Tears from both eyes
            ForEach([-9, 9], id: \.self) { x in
                Capsule().fill(drop.opacity(0.75))
                    .frame(width: 3.5 * scale, height: 8 * scale)
                    .offset(x: CGFloat(x) * scale, y: -8 * scale)
            }
            // Water running off the head and ears once it rains
            if weather.stage >= 3 {
                Capsule().fill(drop.opacity(0.7))
                    .frame(width: 3 * scale, height: 7 * scale)
                    .offset(x: -24 * scale, y: -12 * scale)
                Capsule().fill(drop.opacity(0.7))
                    .frame(width: 3 * scale, height: 6 * scale)
                    .offset(x: 22 * scale, y: -6 * scale)
                Capsule().fill(drop.opacity(0.6))
                    .frame(width: 2.5 * scale, height: 5 * scale)
                    .offset(x: 4 * scale, y: -30 * scale)
            }
            // Shiver marks either side of the head
            if weather.shiverLevel >= 1 {
                ForEach(0..<min(weather.shiverLevel, 3), id: \.self) { i in
                    let y = CGFloat(-20 + i * 8) * scale
                    ShiverMark(scale: scale).offset(x: -33 * scale, y: y)
                    ShiverMark(scale: scale).scaleEffect(x: -1).offset(x: 33 * scale, y: y)
                }
            }
        }
    }
}

struct ShiverMark: View {
    var scale: CGFloat
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 3 * scale, y: 2 * scale))
            p.addLine(to: CGPoint(x: 0, y: 4 * scale))
            p.addLine(to: CGPoint(x: 3 * scale, y: 6 * scale))
        }
        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round, lineJoin: .round))
        .frame(width: 4 * scale, height: 6 * scale)
    }
}

/// Rain streaks (tilted by the wind) or, at the last stage, falling snow.
struct Precipitation: View {
    var weather: DoghouseWeather

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 11)
            if weather.showSnow {
                for _ in 0..<26 {
                    let r = CGFloat(rng.next(in: 1.5...3.5))
                    let x = CGFloat(rng.next(in: 0...1)) * size.width
                    let y = CGFloat(rng.next(in: 0...1)) * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.85)))
                }
            } else if weather.rainIntensity > 0 {
                let n = Int(14 + 30 * weather.rainIntensity)
                let tilt = CGFloat(3 + 6 * weather.windStrength)
                for _ in 0..<n {
                    let x = CGFloat(rng.next(in: 0...1)) * size.width
                    let y = CGFloat(rng.next(in: 0...1)) * size.height
                    let len = CGFloat(rng.next(in: 7...14))
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - tilt * len / 10, y: y + len))
                    ctx.stroke(p, with: .color(Color(red: 0.70, green: 0.82, blue: 1.0).opacity(0.35 + 0.25 * weather.rainIntensity)),
                               style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Tiny deterministic generator so every render of an entry looks the same.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Minimal: both dogs side by side

struct MinimalDogsWidgetView: View {
    var entry: DogWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockScreenDogWidget(entry: entry)
                .containerBackground(.clear, for: .widget)
        default:
            MinimalHomeDogWidget(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

/// The original two-dog layout: a header, then each dog in its own tile
/// with a green "Home" or red "Doghouse" label.
struct MinimalHomeDogWidget: View {
    var entry: DogWidgetEntry
    @Environment(\.widgetFamily) var family

    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        VStack(spacing: 6) {
            Text("DogHouse 🐕")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: isMedium ? 10 : 6) {
                dogBlock(entry.snapshot.me, label: "You")
                if entry.snapshot.hasPartner {
                    dogBlock(entry.snapshot.partner,
                             label: entry.snapshot.partner.name.isEmpty ? "Partner" : entry.snapshot.partner.name)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(isMedium ? 4 : 0)
    }

    private func dogBlock(_ dog: WidgetDog, label: String) -> some View {
        let elapsed = dog.isInDoghouse ? dog.doghouseElapsed(at: entry.date) : dog.homeElapsed(at: entry.date)
        return VStack(spacing: 4) {
            WidgetDogAvatar(avatarId: dog.avatarId, mood: dog.isInDoghouse ? .sad : .happy,
                            size: isMedium ? 64 : 54, showsTail: false)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // One concatenated Text so the whole status shrinks to fit the tile.
            (Text(dog.isInDoghouse ? "Doghouse" : "Home")
                .foregroundColor(dog.isInDoghouse ? .red : .green)
             + Text(elapsed.map { " · \(WidgetDuration.short($0))" } ?? "")
                .foregroundColor(.secondary))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Lock Screen (.accessoryRectangular)

struct LockScreenDogWidget: View {
    var entry: DogWidgetEntry

    var body: some View {
        HStack(spacing: 0) {
            dogColumn(entry.snapshot.me, label: "You")
            if entry.snapshot.hasPartner {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 0.5)
                    .padding(.vertical, 8)
                dogColumn(entry.snapshot.partner,
                          label: entry.snapshot.partner.name.isEmpty ? "Partner" : entry.snapshot.partner.name)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dogColumn(_ dog: WidgetDog, label: String) -> some View {
        VStack(spacing: 2) {
            WidgetDogAvatar(avatarId: dog.avatarId, mood: dog.isInDoghouse ? .sad : .happy, size: 36, showsTail: false)
            Text(dog.isInDoghouse ? "Doghouse · \(WidgetDuration.short(dog.doghouseElapsed(at: entry.date)))" : "At home")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

#Preview("You · doghouse", as: .systemSmall) {
    MyDogWidget()
} timeline: {
    DogWidgetEntry(date: .now, snapshot: .gallerySample, focus: .me)
    DogWidgetEntry(date: .now, snapshot: WidgetSnapshot(
        me: WidgetDog(avatarId: "dog_7", name: "Max", doghouseSince: Date().addingTimeInterval(-8 * 86400), homeSince: nil),
        partner: WidgetSnapshot.placeholder.partner, hasPartner: true), focus: .me)
}

#Preview("You · home", as: .systemSmall) {
    MyDogWidget()
} timeline: {
    DogWidgetEntry(date: .now, snapshot: .placeholder, focus: .me)
}

#Preview("Partner · medium", as: .systemMedium) {
    PartnerDogWidget()
} timeline: {
    DogWidgetEntry(date: .now, snapshot: .gallerySample, focus: .partner)
}

#Preview("Both · small", as: .systemSmall) {
    BothDogsWidget()
} timeline: {
    DogWidgetEntry(date: .now, snapshot: .gallerySample, focus: .both)
}
