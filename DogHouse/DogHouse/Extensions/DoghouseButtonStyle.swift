//
//  DoghouseButtonStyle.swift
//  DogHouse
//

import SwiftUI

struct DoghouseButtonStyle: ButtonStyle {
    var enableHaptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && enableHaptic {
                    HapticService.shared.lightTap()
                }
            }
    }
}

extension ButtonStyle where Self == DoghouseButtonStyle {
    static var doghouse: DoghouseButtonStyle { DoghouseButtonStyle() }
}
