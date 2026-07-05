//
//  Typography.swift
//  DogHouse
//
//  Consistent text styles across the app using the rounded design system.
//

import SwiftUI

extension Font {
    // MARK: - Display
    /// Large display text for splash/animation screens
    static let dhDisplay = Font.system(size: 32, weight: .black, design: .rounded)
    /// Section title (e.g. "DogHouse" nav title size)
    static let dhTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    /// Smaller heading for cards and sections
    static let dhHeading = Font.system(size: 18, weight: .bold, design: .rounded)

    // MARK: - Body
    /// Primary body text
    static let dhBody = Font.system(size: 16, weight: .regular, design: .rounded)
    /// Bold body variant
    static let dhBodyBold = Font.system(size: 16, weight: .semibold, design: .rounded)

    // MARK: - Supporting
    /// Captions and secondary info
    static let dhCaption = Font.system(size: 13, weight: .regular, design: .rounded)
    /// Bold caption for labels
    static let dhCaptionBold = Font.system(size: 13, weight: .semibold, design: .rounded)
    /// Small badge/tag text
    static let dhBadge = Font.system(size: 10, weight: .black, design: .rounded)

    // MARK: - Monospaced
    /// Timer display
    static let dhTimer = Font.system(size: 28, weight: .bold, design: .monospaced)
    /// Compact timer
    static let dhTimerSmall = Font.system(size: 18, weight: .bold, design: .monospaced)
}
