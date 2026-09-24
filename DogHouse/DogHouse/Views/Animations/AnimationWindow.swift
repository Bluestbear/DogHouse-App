//
//  AnimationWindow.swift
//  DogHouse
//
//  A window of its own, above the app's, for the full-screen kick and
//  release animations. An overlay on Home plays unseen behind any sheet
//  and on any other tab; this one draws over all of it, so both phones
//  actually see the moment whatever they had open.
//

import SwiftUI
import UIKit
import Combine

@MainActor
final class AnimationWindow {
    static let shared = AnimationWindow()

    private let model = Model()
    private var window: UIWindow?

    private init() {}

    /// Shows `content` above everything. It is handed the closure that takes
    /// it down again, for the animation's `onComplete`.
    func present<Content: View>(@ViewBuilder _ content: (_ dismiss: @escaping () -> Void) -> Content) {
        let id = UUID()
        let view = content { [weak self] in self?.dismiss(id) }
        model.entries.append(Entry(id: id, view: AnyView(view)))
        showWindow()
    }

    private func dismiss(_ id: UUID) {
        model.entries.removeAll { $0.id == id }
        guard model.entries.isEmpty else { return }
        window?.isHidden = true
        window = nil
    }

    private func showWindow() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first else { return }
        let host = UIHostingController(rootView: Stack(model: model))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        // Above sheets and alerts; the animation owns the screen while it plays.
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    // MARK: Content

    private struct Entry: Identifiable {
        let id: UUID
        let view: AnyView
    }

    private final class Model: ObservableObject {
        @Published var entries: [Entry] = []
    }

    /// Later animations sit on top of earlier ones.
    private struct Stack: View {
        @ObservedObject var model: Model

        var body: some View {
            ZStack {
                ForEach(model.entries) { $0.view }
            }
            .ignoresSafeArea()
        }
    }
}
