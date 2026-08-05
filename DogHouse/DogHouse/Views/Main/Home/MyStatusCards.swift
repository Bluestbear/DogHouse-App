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

/// The live counter shown while I'm not in the doghouse.
struct TimeAtHomeCard: View {
    /// When my current stay at home began.
    let start: Date
    /// Coarse elapsed time, for the VoiceOver reading — a screen reader
    /// announcing a seconds counter would never stop talking.
    let elapsed: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            Text("You've been home for:")
                .font(.dhCaption)
                .foregroundStyle(.secondary)
            ElapsedTimeText(start: start)
                .font(.dhTimer)
                .foregroundStyle(Color.freedomGreen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You've been home for \(elapsed.formattedDuration)")
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
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("You've been sent to the DogHouse!")
                    .font(.dhTitle)
                    .multilineTextAlignment(.center)

                ElapsedTimeText(start: event.startedAt)
                    .font(.dhTimer)
                    .foregroundStyle(.red)
            }

            reasonSection

            VStack(alignment: .leading, spacing: 12) {
                Label("How to get out:", systemImage: "lightbulb.fill")
                    .font(.dhCaptionBold)
                    .foregroundStyle(Color.cozyOrange)

                waitItOutRow

                // Redemption: mark the make-it-up suggestion as done
                if let suggestion = event.suggestion {
                    if event.redemptionRequested == true {
                        redemptionPendingRow
                    } else {
                        redemptionButton(suggestion: suggestion)
                    }
                }

                tasksSection
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Reason", systemImage: "text.quote")
                .font(.dhCaptionBold)
                .foregroundStyle(.secondary)
            Text(event.reason)
                .font(.dhBody)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var waitItOutRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wait it out")
                    .font(.dhBodyBold)
                Text("Stay here until \(partnerName) lets you out")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var redemptionPendingRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .foregroundStyle(Color.cozyOrange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Redemption requested")
                    .font(.dhBodyBold)
                Text("Waiting for \(partnerName) to confirm...")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.cozyOrange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func redemptionButton(suggestion: String) -> some View {
        Button(action: onRequestRedemption) {
            HStack(spacing: 10) {
                Text("🦴")
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("I did it!")
                        .font(.dhBodyBold)
                    Text("\"\(suggestion)\" — tell \(partnerName) you made it up")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "paperplane.fill")
                    .font(.caption)
                    .foregroundStyle(Color.freedomGreen)
            }
            .padding(10)
            .background(Color.freedomGreen.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark the make-it-up suggestion as done and notify \(partnerName)")
    }

    @ViewBuilder
    private var tasksSection: some View {
        if coupleTasks.isEmpty && coupleTasksLoaded {
            Button(action: onShowTasks) {
                HStack(spacing: 10) {
                    Image(systemName: "list.clipboard.fill")
                        .foregroundStyle(Color.cozyOrange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Do a Task")
                            .font(.dhBodyBold)
                        Text("No tasks set up yet — tap to propose tasks!")
                            .font(.dhCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color.cozyOrange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        } else if !coupleTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "list.clipboard.fill")
                        .foregroundStyle(Color.cozyOrange)
                        .frame(width: 28)
                    Text("Do a Task")
                        .font(.dhBodyBold)
                    Spacer()
                }

                ForEach(coupleTasks) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.cozyOrange)
                            .frame(width: 6, height: 6)
                        Text(task.title)
                            .font(.dhBody)
                    }
                }
            }
            .padding(10)
            .background(Color.cozyOrange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
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
