//
//  ElapsedTimeText.swift
//  DogHouse
//

import SwiftUI

/// A live "1h 23m 45s" counter.
///
/// The tick is deliberately confined to this view. Driving a seconds counter
/// from a `@State` date on the enclosing screen invalidates that screen's
/// entire body once a second — on Home that meant re-evaluating both room
/// scenes and every card sixty times a minute, including while the user was
/// looking at another tab. `TimelineView` only schedules updates for its own
/// subtree, and SwiftUI stops scheduling it altogether while the view is off
/// screen or the app is in the background.
struct ElapsedTimeText: View {
    /// The moment being counted from.
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            // Clock skew between the device and the server can put `start`
            // slightly in the future; clamp rather than render "-1s".
            Text(max(0, context.date.timeIntervalSince(start)).formattedTimer)
                // Digits of differing width make a running clock jitter.
                .monospacedDigit()
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ElapsedTimeText(start: Date().addingTimeInterval(-42))
        ElapsedTimeText(start: Date().addingTimeInterval(-3_700))
        ElapsedTimeText(start: Date().addingTimeInterval(-90_000))
    }
    .font(.dhTimer)
}
