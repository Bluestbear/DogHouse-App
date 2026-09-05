//
//  Typography.swift
//  DogHouse
//
//  Consistent text styles across the app using the rounded design system.
//

import SwiftUI

//  Every token is built from a semantic text style rather than a fixed point
//  size. `Font.system(size:)` ignores the reader's Dynamic Type setting
//  entirely, so the previous fixed sizes meant text never grew for anyone who
//  had enlarged it — the default sizes below match what those numbers rendered
//  at, so the design is unchanged at the standard setting.

extension Font {
    // MARK: - Display
    /// Large display text for splash/animation screens (~32pt at default)
    static let dhDisplay = Font.system(.largeTitle, design: .rounded).weight(.black)
    /// The greeting at the top of Home — the size the navigation large
    /// title used to be there (~34pt at default)
    static let dhLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Screen title on auth and onboarding screens (~28pt at default)
    static let dhScreenTitle = Font.system(.title, design: .rounded).weight(.bold)
    /// Section title (~22pt at default)
    static let dhTitle = Font.system(.title2, design: .rounded).weight(.bold)
    /// Sub-section title (~20pt at default)
    static let dhSubtitle = Font.system(.title3, design: .rounded).weight(.semibold)
    /// Smaller heading for cards and sections (~17pt at default)
    static let dhHeading = Font.system(.headline, design: .rounded).weight(.bold)

    // MARK: - Body
    /// Primary body text (~16pt at default)
    static let dhBody = Font.system(.callout, design: .rounded)
    /// Bold body variant
    static let dhBodyBold = Font.system(.callout, design: .rounded).weight(.semibold)

    // MARK: - Supporting
    /// Captions and secondary info (~13pt at default)
    static let dhCaption = Font.system(.footnote, design: .rounded)
    /// Bold caption for labels
    static let dhCaptionBold = Font.system(.footnote, design: .rounded).weight(.semibold)
    /// Small badge/tag text (~11pt at default)
    static let dhBadge = Font.system(.caption2, design: .rounded).weight(.black)

    // MARK: - Monospaced
    /// Timer display (~28pt at default)
    static let dhTimer = Font.system(.title, design: .monospaced).weight(.bold)
    /// Compact timer (~17pt at default)
    static let dhTimerSmall = Font.system(.headline, design: .monospaced).weight(.bold)
}
