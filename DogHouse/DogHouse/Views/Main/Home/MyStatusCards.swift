//
//  MyStatusCards.swift
//  DogHouse
//
//  The card under the room scenes describing MY own status — either the
//  running "you've been home for" counter, or the full doghouse card with the
//  reason and the ways out.
//

import SwiftUI

// MARK: - Time At Home

/// The live counter shown while a dog is not in the doghouse: mine on my
/// page, my partner's on theirs.
struct TimeAtHomeCard: View {
    /// When the current stay at home began.
    let start: Date
    /// Coarse elapsed time, for the VoiceOver reading — a screen reader
    /// announcing a seconds counter would never stop talking.
    let elapsed: TimeInterval
    /// Whose stay it is, as the sentence's subject: "You've" or "Sam's".
    var who = "You've"

    var body: some View {
        VStack(spacing: 4) {
            Text("\(who) been home for:")
                .font(.dhCaption)
                .foregroundStyle(.secondary)
            ElapsedTimeText(start: start)
                .font(.dhTimer)
                .foregroundStyle(Color.freedomGreen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(who) been home for \(elapsed.formattedDuration)")
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }
}

// MARK: - My Doghouse Card

/// Shown when I'm the one in the doghouse: how long I've been in, what for,
/// and the ways out.
struct MyDoghouseInfoCard: View {
    let event: DoghouseEvent
    let partnerName: String
    let coupleTasks: [CoupleTask]
    let coupleTasksLoaded: Bool
    let onRequestRedemption: () -> Void
    let onShowTasks: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Just the clock: the greeting at the top of Home already says
            // you're in the doghouse, so repeating it here was noise.
            ElapsedTimeText(start: event.startedAt)
                .font(.dhTimer)
                .foregroundStyle(.red)
                // A bare running clock read aloud says nothing about what it
                // counts, and a per-second label would never stop talking —
                // so this reads the coarse duration, as TimeAtHomeCard does.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("In the DogHouse for \(event.duration.formattedDuration)")

            // The reason, as a plain quote. It used to sit in a labelled
            // panel inside the card; the quotation marks carry that on their
            // own and cost no vertical space.
            Text("\u{201C}\(event.reason)\u{201D}")
                .font(.dhSubtitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Reason: \(event.reason)")

            // The ways out. These were four tinted panels stacked inside the
            // card, under their own heading — now plain rows separated by
            // hairlines, and only the ones you can act on.
            VStack(spacing: 0) {
                // Always offered: the sender's suggestion is optional, and
                // without this row a suggestion-less send left the dog no
                // way to say they'd made it up.
                if event.redemptionRequested == true {
                    WayOutRow(
                        symbol: "hourglass", tint: .cozyOrange,
                        title: "Waiting for \(partnerName)",
                        detail: "You said you made it up"
                    )
                } else {
                    WayOutRow(
                        symbol: "checkmark.circle.fill", tint: .freedomGreen,
                        title: "I did it",
                        detail: event.suggestion ?? "Tell \(partnerName) you made it up",
                        accessory: "paperplane.fill", accessoryTint: .freedomGreen,
                        action: onRequestRedemption
                    )
                }
                Divider()
                if coupleTasksLoaded {
                    WayOutRow(
                        symbol: "list.clipboard.fill", tint: .cozyOrange,
                        title: "Do a task", detail: tasksDetail,
                        accessory: "chevron.right",
                        action: onShowTasks
                    )
                    Divider()
                }
                // Last, and the only one that isn't a button: doing nothing
                // is a way out too, it just isn't something you tap.
                WayOutRow(
                    symbol: "clock", tint: .secondary,
                    title: "Sit it out",
                    detail: "\(partnerName) can let you out any time"
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private var tasksDetail: String {
        // Only the tasks this dog can do: the ones the partner asked for,
        // plus the app's. The dog's own requests are the partner's to do.
        let mine = coupleTasks.filter { $0.suggestedBy != event.receiverId }.count
        if coupleTasks.isEmpty { return "None agreed yet — tap to propose some" }
        if mine == 0 { return "See your agreed tasks" }
        return mine == 1 ? "1 you can do" : "\(mine) you can do"
    }
}

/// One way out of the doghouse: a flat row on the card, tappable when there
/// is somewhere to go.
private struct WayOutRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var accessory: String? = nil
    var accessoryTint: Color = .secondary
    var action: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.doghouse)
                .accessibilityLabel("\(title). \(detail)")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dhBodyBold)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let accessory {
                Image(systemName: accessory)
                    .font(.caption)
                    .foregroundStyle(accessoryTint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview("At home") {
    TimeAtHomeCard(start: Date().addingTimeInterval(-9_000), elapsed: 9_000)
}

#Preview("In the doghouse") {
    ScrollView {
        MyDoghouseInfoCard(
            event: DoghouseEvent(
                id: "1",
                senderId: "them",
                receiverId: "me",
                reason: "Left the dishes again",
                suggestion: "Cook dinner",
                startedAt: Date().addingTimeInterval(-4_000),
                endedAt: nil,
                isActive: true
            ),
            partnerName: "Sam",
            coupleTasks: [],
            coupleTasksLoaded: true,
            onRequestRedemption: {},
            onShowTasks: {}
        )
    }
}
