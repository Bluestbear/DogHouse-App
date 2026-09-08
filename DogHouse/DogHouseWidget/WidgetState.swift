//
//  WidgetState.swift
//  DogHouseWidget
//
//  What the main app shares with the widget through the App Group, plus the
//  time-derived bits (doghouse weather, counters) the widget computes itself
//  so a timeline entry can be rendered for any future date without the app.
//

import Foundation

enum WidgetStore {
    /// Must match the App Group configured on both targets.
    static let appGroupId = "group.com.harrisonkrampe.doghouse"

    // Keys written by HomeView.writeWidgetState() in the main app.
    enum Key {
        static let myAvatarId          = "widget_myAvatarId"
        static let partnerAvatarId     = "widget_partnerAvatarId"
        static let myInDoghouse        = "widget_myInDoghouse"
        static let partnerInDoghouse   = "widget_partnerInDoghouse"
        static let myName              = "widget_myName"
        static let partnerName         = "widget_partnerName"
        static let myDoghouseSince     = "widget_myDoghouseSince"      // epoch seconds, 0 = none
        static let partnerDoghouseSince = "widget_partnerDoghouseSince"
        static let myHomeSince         = "widget_myHomeSince"          // epoch seconds of my last release
        static let partnerHomeSince    = "widget_partnerHomeSince"
        static let hasPartner          = "widget_hasPartner"
    }
}

struct WidgetDog {
    var avatarId: String
    var name: String
    /// When this dog was sent to the doghouse. nil = at home.
    var doghouseSince: Date?
    /// When this dog was last released (room progression clock). nil = unknown.
    var homeSince: Date?

    var isInDoghouse: Bool { doghouseSince != nil }

    func doghouseElapsed(at date: Date) -> TimeInterval {
        guard let since = doghouseSince else { return 0 }
        return max(0, date.timeIntervalSince(since))
    }

    func homeElapsed(at date: Date) -> TimeInterval? {
        guard let since = homeSince else { return nil }
        return max(0, date.timeIntervalSince(since))
    }
}

struct WidgetSnapshot {
    var me: WidgetDog
    var partner: WidgetDog
    var hasPartner: Bool

    static let placeholder = WidgetSnapshot(
        me: WidgetDog(avatarId: "dog_1", name: "", doghouseSince: nil,
                      homeSince: Date().addingTimeInterval(-3 * 86400)),
        partner: WidgetDog(avatarId: "dog_2", name: "", doghouseSince: nil,
                           homeSince: Date().addingTimeInterval(-3 * 86400)),
        hasPartner: true
    )

    /// The gallery preview: the dog shivering in the doghouse is the whole
    /// point of the widget, so show that rather than a smiling one.
    static let gallerySample = WidgetSnapshot(
        me: WidgetDog(avatarId: "dog_1", name: "Max",
                      doghouseSince: Date().addingTimeInterval(-5 * 3600), homeSince: nil),
        partner: WidgetDog(avatarId: "dog_2", name: "Mia", doghouseSince: nil,
                           homeSince: Date().addingTimeInterval(-3 * 86400)),
        hasPartner: true
    )

    static func load(now: Date = Date()) -> WidgetSnapshot {
        guard let d = UserDefaults(suiteName: WidgetStore.appGroupId) else { return .placeholder }

        func date(_ key: String) -> Date? {
            let t = d.double(forKey: key)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        // Older app builds only wrote the bool; treat that as "just arrived".
        func since(_ dateKey: String, _ boolKey: String) -> Date? {
            if let s = date(dateKey) { return s }
            return d.bool(forKey: boolKey) ? now : nil
        }
        func name(_ key: String, fallback: String) -> String {
            let n = d.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
            return n.isEmpty ? fallback : n
        }

        return WidgetSnapshot(
            me: WidgetDog(
                avatarId: d.string(forKey: WidgetStore.Key.myAvatarId) ?? "dog_1",
                name: name(WidgetStore.Key.myName, fallback: ""),
                doghouseSince: since(WidgetStore.Key.myDoghouseSince, WidgetStore.Key.myInDoghouse),
                homeSince: date(WidgetStore.Key.myHomeSince)
            ),
            partner: WidgetDog(
                avatarId: d.string(forKey: WidgetStore.Key.partnerAvatarId) ?? "dog_2",
                name: name(WidgetStore.Key.partnerName, fallback: ""),
                doghouseSince: since(WidgetStore.Key.partnerDoghouseSince, WidgetStore.Key.partnerInDoghouse),
                homeSince: date(WidgetStore.Key.partnerHomeSince)
            ),
            hasPartner: d.object(forKey: WidgetStore.Key.hasPartner) == nil
                ? true : d.bool(forKey: WidgetStore.Key.hasPartner)
        )
    }
}

// MARK: - Doghouse weather

/// Mirrors `DoghouseStage` in the main app: the same eight time thresholds,
/// and the same "it only gets worse" stacking of rain, night and snow.
struct DoghouseWeather {
    /// Seconds served at which the scene moves to the next stage.
    static let thresholds: [TimeInterval] = [
        0, 3600, 10800, 21600, 86400, 259200, 432000, 604800
    ]

    let stage: Int          // 1...8

    init(elapsed: TimeInterval) {
        var s = 1
        for (i, t) in Self.thresholds.enumerated() where elapsed >= t { s = i + 1 }
        stage = s
    }

    /// 0 = just arrived, 1 = full survival mode. Drives every colour.
    var gloom: Double { Double(stage - 1) / 7 }

    /// 0 = dry, 1 = downpour.
    var rainIntensity: Double {
        switch stage {
        case 1, 2: 0
        case 3:    0.3
        case 4:    0.6
        case 5, 6: 0.8
        case 7:    1.0
        default:   0      // snow instead
        }
    }

    var showSnow: Bool { stage >= 8 }
    var showClouds: Bool { stage >= 3 }
    var isNight: Bool { stage >= 6 }
    var showLightning: Bool { stage >= 7 }

    /// 0 = still, 3 = teeth chattering.
    var shiverLevel: Int {
        switch stage {
        case 1, 2, 3: 0
        case 4, 5:    1
        case 6, 7:    2
        default:      3
        }
    }

    /// 0 = calm, 1 = gale. Tilts the rain.
    var windStrength: Double { stage >= 7 ? 1 : stage >= 5 ? 0.4 : 0 }

    /// How the dog feels about it — the one-liner under the counter.
    /// Addressed to the dog by name when we have one.
    func complaint(for name: String) -> String {
        let line: String = switch stage {
        case 1: "it's lonely out here…"
        case 2: "it's getting cold…"
        case 3: "clouds are rolling in…"
        case 4, 5: "it's cold and wet…"
        case 6, 7: "it's freezing…"
        default: "send help…"
        }
        return name.isEmpty ? line.prefix(1).uppercased() + line.dropFirst() : "\(name), \(line)"
    }
}

// MARK: - Duration formatting

enum WidgetDuration {
    /// "45m", "3h", "2d" — the big number next to the icon.
    static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}
