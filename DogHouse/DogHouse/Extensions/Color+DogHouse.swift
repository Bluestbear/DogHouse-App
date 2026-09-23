//
//  Color+DogHouse.swift
//  DogHouse
//
//  Custom colors are defined in Assets.xcassets and auto-generated
//  by Xcode as Color.dogHouseBrown, Color.cozyOrange, etc.
//

import SwiftUI

extension Color {
    /// The dark brown of the avatar's default collar. Solid fill for the
    /// event banners (anniversary race, jailbreak vote). AvatarView keeps its
    /// own literal; the avatar is not to be touched.
    static let collarBrown = Color(red: 0.42, green: 0.24, blue: 0.07)

    /// The app's background on every tab: a warm brown wash, darkest at the
    /// top. Both stops are DogHouseBrown over white — 14% and 8% — so the
    /// page reads as brown paper rather than white. Dark mode uses the same
    /// hue at the other end of the range.
    static var pageGradient: LinearGradient {
        LinearGradient(colors: [.canvasTop, .canvasBottom], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// Puts the page background behind a scrolling container. `List` and
    /// `Form` paint their own grouped background, which would cover it.
    func dhPageBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.pageGradient.ignoresSafeArea())
    }
}
