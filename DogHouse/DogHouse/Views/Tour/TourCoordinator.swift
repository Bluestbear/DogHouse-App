//
//  TourCoordinator.swift
//  DogHouse
//
//  The live app tour: a spotlight walkthrough that runs INSIDE the real app,
//  on the real screens, instead of a slideshow before the user gets there.
//
//  Three pieces:
//    • `TourStep`         — the ordered script: which tab, which control, what
//                           to say. Pure data, unit-tested.
//    • `TourCoordinator`  — where we are in the script. Views observe
//                           `currentStep` to switch tabs, scroll, or flip the
//                           scene page so the highlighted control is on screen.
//    • `TourAnchorStore`  — the on-screen frames of the controls a step points
//                           at. Views tag themselves with `.tourAnchor(.x)`;
//                           the overlay reads the frame to cut its spotlight.
//
//  Frames and step state are split into two objects on purpose: frames change
//  on every scroll tick, and only the overlay should re-render for that.
//

import SwiftUI
import Combine
import OSLog

// MARK: - Anchors

/// A control the tour can point at. Views register themselves under one of
/// these with `.tourAnchor(_:)`.
enum TourAnchorID: String, CaseIterable, Sendable {
    case sceneWindow      // the swipeable room window on Home
    case rosesButton      // 🌹 on the partner's scene page
    case roomProgress     // the room level bar under my scene
    case sendButton       // "Send X to the DogHouse"
    case tasksButton      // toolbar: Your Tasks
    case gamesMenu        // toolbar: + menu
    case treatBalance     // Shop: the 🦴 balance capsule
    case addCouple        // Friends: enter a couple's code
    case anniversary      // Profile: anniversary section
}

// MARK: - Steps

/// One stop on the tour. Order in `allCases` is the order shown.
enum TourStep: Int, CaseIterable, Sendable {
    case welcome
    case myRoom
    case partnerRoom
    case roses
    case treats
    case sendButton
    case tasks
    case games
    case shop
    case friends
    case anniversary
    case input
    case widgets

    /// The tab this step lives on. The coordinator's observer switches to it.
    var tab: MainTabView.AppTab {
        switch self {
        case .welcome, .myRoom, .partnerRoom, .roses, .treats, .sendButton, .tasks, .games, .widgets:
            return .home
        case .shop: return .shop
        case .friends: return .friends
        case .anniversary: return .profile
        case .input: return .input
        }
    }

    /// The control to spotlight, or nil for a plain centred card.
    var anchor: TourAnchorID? {
        switch self {
        case .myRoom, .partnerRoom: return .sceneWindow
        case .roses: return .rosesButton
        case .treats: return .roomProgress
        case .sendButton: return .sendButton
        case .tasks: return .tasksButton
        case .games: return .gamesMenu
        case .shop: return .treatBalance
        case .friends: return .addCouple
        case .anniversary: return .anniversary
        case .welcome, .input, .widgets: return nil
        }
    }

    /// Which page of the Home scene window should be showing. nil = leave it.
    var scenePage: Int? {
        switch self {
        case .myRoom, .treats: return 0
        case .partnerRoom, .roses: return 1
        default: return nil
        }
    }

    var isFirst: Bool { self == TourStep.allCases.first }
    var isLast: Bool { self == TourStep.allCases.last }

    /// One-based position for the "3 of 13" label.
    var ordinal: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    /// Copy for the callout card, with the couple's real names filled in.
    func content(userName: String, partnerName: String) -> TourStepContent {
        switch self {
        case .welcome:
            return TourStepContent(
                emoji: "🐕",
                title: "Welcome, \(userName)!",
                body: "Here's a quick tour of how DogHouse works — it takes about a minute. You can replay it any time from Profile."
            )
        case .myRoom:
            return TourStepContent(
                emoji: "🏠",
                title: "This is your dog at home",
                body: "When things are good, your dog chills in the living room. The longer you stay out of trouble, the cozier it gets."
            )
        case .partnerRoom:
            return TourStepContent(
                emoji: "🐾",
                title: "\(partnerName)'s room",
                body: "Swipe the window to see your partner's dog. Press and hold their dog to send a belly rub — they feel it instantly."
            )
        case .roses:
            return TourStepContent(
                emoji: "🌹",
                title: "Send roses",
                body: "Feeling extra sweet? Tap the rose button on \(partnerName)'s page to send a bouquet for 5 treats. It stays next to their dog for 5 hours."
            )
        case .treats:
            return TourStepContent(
                emoji: "🦴",
                title: "Earn treats at home",
                body: "Every hour you're both at home earns treats — more at higher room levels. If either of you is in the DogHouse, the treats stop, so be good to each other!"
            )
        case .sendButton:
            return TourStepContent(
                emoji: "🚪",
                title: "Messed up? Off to the DogHouse",
                body: "Send \(partnerName) to the DogHouse with a reason and a way to make it up. You get 3 sends, and each one recharges after a day."
            )
        case .tasks:
            return TourStepContent(
                emoji: "📋",
                title: "Your tasks",
                body: "The tasks you both agreed on live here. A dog in the DogHouse can do one to earn their way out — or claim they've made it up and wait for you to confirm."
            )
        case .games:
            return TourStepContent(
                emoji: "🧠",
                title: "Quizzes & cards",
                body: "Start couple quizzes here and see if your answers match. Win a Whatever-I-Want card and your partner can't refuse it. Watch out for surprise Photo Dashes!"
            )
        case .shop:
            return TourStepContent(
                emoji: "🛍️",
                title: "The Shop",
                body: "Spend your treats on hats, glasses and necklaces for your dog — or gift something to \(partnerName)'s dog instead."
            )
        case .friends:
            return TourStepContent(
                emoji: "👥",
                title: "Friend couples",
                body: "Add other couples with their code. Public sendings show up in the feed, and when two dogs are in the DogHouse at once, friends vote on who gets out first."
            )
        case .anniversary:
            return TourStepContent(
                emoji: "💍",
                title: "Your anniversary",
                body: "Set your date here. On the day, the first of you to wish a happy anniversary in the app wins a Whatever-I-Want card — so the race is on!"
            )
        case .input:
            return TourStepContent(
                emoji: "📬",
                title: "Your input matters",
                body: "Got a complaint or an idea? This tab sends your message straight to the developer. Every message gets read."
            )
        case .widgets:
            return TourStepContent(
                emoji: "📱",
                title: "One more thing: widgets",
                body: "Add the DogHouse widget to your Home Screen or Lock Screen to always know who's in the doghouse. Long-press your Home Screen, tap Edit, then Add Widget, then DogHouse."
            )
        }
    }
}

struct TourStepContent: Equatable, Sendable {
    let emoji: String
    let title: String
    let body: String
}

// MARK: - Coordinator

@MainActor
final class TourCoordinator: ObservableObject {
    static let shared = TourCoordinator()

    /// The step being shown, or nil when no tour is running.
    @Published private(set) var currentStep: TourStep?

    /// Bumped each time a tour ends (finished or skipped). MainTabView
    /// observes this to record completion and return to Home.
    @Published private(set) var completionCount = 0

    /// True when the user restarted the tour from Profile rather than being
    /// shown it as a new user. Affects nothing today except logging; kept so
    /// analytics can tell the two apart later.
    private(set) var isReplay = false

    var isActive: Bool { currentStep != nil }

    init() {}

    func start(replay: Bool = false) {
        isReplay = replay
        currentStep = TourStep.allCases.first
    }

    func next() {
        guard let step = currentStep else { return }
        if step.isLast {
            finish()
        } else {
            currentStep = TourStep(rawValue: step.rawValue + 1)
        }
    }

    func back() {
        guard let step = currentStep, !step.isFirst else { return }
        currentStep = TourStep(rawValue: step.rawValue - 1)
    }

    /// End the tour early. Counts as complete — a skipped tour must not
    /// come back on the next launch.
    func skip() {
        finish()
    }

    private func finish() {
        guard currentStep != nil else { return }
        currentStep = nil
        completionCount += 1
    }
}

// MARK: - Anchor Store

/// On-screen frames (window coordinates) of the controls a step can point
/// at. Separate from the coordinator so scroll-driven frame updates only
/// re-render the overlay.
@MainActor
final class TourAnchorStore: ObservableObject {
    static let shared = TourAnchorStore()

    @Published private(set) var frames: [TourAnchorID: CGRect] = [:]

    init() {}

    func register(_ id: TourAnchorID, frame: CGRect) {
        // Sub-pixel jitter from layout passes is not worth a publish.
        if let old = frames[id],
           abs(old.minX - frame.minX) < 0.5, abs(old.minY - frame.minY) < 0.5,
           abs(old.width - frame.width) < 0.5, abs(old.height - frame.height) < 0.5 {
            return
        }
        frames[id] = frame
    }

    func unregister(_ id: TourAnchorID) {
        frames[id] = nil
    }
}

// MARK: - View Modifier

extension View {
    /// Tag a control so the tour can spotlight it. Frames are reported in
    /// window coordinates, which is the space the overlay draws in.
    func tourAnchor(_ id: TourAnchorID) -> some View {
        modifier(TourAnchorModifier(id: id))
    }
}

/// Reports the tagged view's frame in WINDOW coordinates.
///
/// SwiftUI's `.global` coordinate space is only "the window" for views in the
/// main hosting hierarchy. Toolbar items are hosted separately inside the
/// navigation bar, and there `.global` means the bar's own hosting view — the
/// tasks button came back at (0, 0) and the spotlight landed in the corner.
/// So the GeometryReader is used purely as a change trigger (it fires on
/// scroll and layout), and the frame itself is read through UIKit, which
/// converts from any hierarchy to the window correctly.
private struct TourAnchorModifier: ViewModifier {
    let id: TourAnchorID

    func body(content: Content) -> some View {
        content.background(
            ZStack {
                // Reports on attach and on layout — the moments a toolbar
                // item first has a window at all.
                WindowFrameProbeView(id: id) { frame in
                    TourAnchorStore.shared.register(id, frame: frame)
                }
                // Reports on scroll, which UIKit's layoutSubviews does not
                // see for a view that merely moved with its scroll view.
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global)) { _, _ in
                            WindowFrameProbeView.reportNow(id)
                        }
                }
            }
            .onDisappear {
                TourAnchorStore.shared.unregister(id)
            }
        )
    }
}

private struct WindowFrameProbeView: UIViewRepresentable {
    let id: TourAnchorID
    let onFrame: (CGRect) -> Void

    /// Live probes by anchor, so the GeometryReader trigger can ask the
    /// UIKit view for a fresh window-space frame.
    @MainActor private static var probes: [TourAnchorID: ProbeView] = [:]

    static func reportNow(_ id: TourAnchorID) {
        probes[id]?.report()
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onFrame = onFrame
        view.anchorID = id
        Self.probes[id] = view
        return view
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) {
        if let id = uiView.anchorID, Self.probes[id] === uiView {
            Self.probes[id] = nil
        }
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onFrame = onFrame
    }

    final class ProbeView: UIView {
        var onFrame: ((CGRect) -> Void)?
        var anchorID: TourAnchorID?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard window != nil else { return }
            onFrame?(convert(bounds, to: nil))
        }
    }
}

// MARK: - Toolbar Lookup

/// Toolbar items are the one place `.tourAnchor` cannot work: SwiftUI never
/// materialises a toolbar item's `.background`, so the probe view is never
/// created, let alone added to a window. The navigation bar's buttons are
/// real UIKit views, though, so the overlay looks those up directly when a
/// toolbar step has nothing registered.
@MainActor
enum ToolbarButtonLocator {
    /// Window-space frames for the trailing toolbar buttons, left to right.
    ///
    /// On iOS 26 the trailing items share one glass platter, and depending on
    /// the OS build the individual buttons may or may not exist as their own
    /// views. Innermost button-sized views win when they do; when only the
    /// platter is found it is split evenly into `count` slots so each step
    /// still points at the right half.
    static func trailingButtonFrames(count: Int) -> [CGRect] {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return [] }

        var bars: [UINavigationBar] = []
        collect(into: &bars, from: window)

        var candidates: [CGRect] = []
        for bar in bars where bar.window != nil && !bar.isHidden && bar.alpha > 0 {
            var views: [UIView] = []
            collect(into: &views, from: bar)
            for view in views where !view.isHidden && view.alpha > 0 {
                let frame = view.convert(view.bounds, to: nil)
                guard frame.width >= 24, frame.width <= 160,
                      frame.height >= 24, frame.height <= 72,
                      frame.minX > window.bounds.midX else { continue }
                candidates.append(frame)
            }
        }

        // Drop containers: anything that fully contains another candidate.
        let leaves = candidates.filter { outer in
            !candidates.contains { inner in inner != outer && outer.contains(inner) }
        }
        var frames: [CGRect] = []
        for frame in leaves.sorted(by: { $0.minX < $1.minX })
        where !frames.contains(where: { $0.intersects(frame) }) {
            frames.append(frame)
        }

        // One group view standing in for several buttons: divide it up.
        if frames.count == 1, count > 1, let group = frames.first {
            let slot = group.width / CGFloat(count)
            return (0..<count).map { i in
                CGRect(x: group.minX + slot * CGFloat(i), y: group.minY, width: slot, height: group.height)
            }
        }
        return frames
    }

    private static func collect<T: UIView>(into out: inout [T], from view: UIView) {
        for sub in view.subviews {
            if let match = sub as? T { out.append(match) }
            collect(into: &out, from: sub)
        }
    }
}
