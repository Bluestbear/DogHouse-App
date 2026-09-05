//
//  AchievementsSheet.swift
//  DogHouse
//
//  The couple's badges, grouped by category, with progress toward the ones
//  still locked.
//

import SwiftUI

struct AchievementsSheet: View {
    @ObservedObject var achievements: AchievementService
    /// The current standing, for progress on locked badges.
    let snapshot: AchievementSnapshot?
    @Environment(\.dismiss) private var dismiss

    private var unlockedCount: Int { achievements.unlockedCount }
    private var total: Int { Achievement.all.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summary
                    ForEach(AchievementCategory.allCases, id: \.self) { category in
                        section(category)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .dhPageBackground()
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 8) {
            HStack {
                Text("🏆").font(.title2)
                Text("\(unlockedCount) of \(total) unlocked")
                    .font(.dhHeading)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(Color.cozyOrange)
                        .frame(width: geo.size.width * CGFloat(unlockedCount) / CGFloat(total))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func section(_ category: AchievementCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue)
                .font(.dhCaptionBold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                let items = Achievement.all.filter { $0.category == category }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, achievement in
                    AchievementRow(
                        achievement: achievement,
                        unlockedAt: achievements.unlockedAt[achievement.id],
                        progress: snapshot.map { achievement.progress(in: $0) } ?? 0
                    )
                    if index < items.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
    }
}

private struct AchievementRow: View {
    let achievement: Achievement
    let unlockedAt: Date?
    let progress: Int

    private var isUnlocked: Bool { unlockedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            Text(achievement.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(isUnlocked ? Color.cozyOrange.opacity(0.18) : Color(.systemGray5))
                .clipShape(Circle())
                .grayscale(isUnlocked ? 0 : 1)
                .opacity(isUnlocked ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title)
                    .font(.dhBodyBold)
                Text(achievement.description)
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isUnlocked, achievement.target > 1 {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray4))
                                Capsule()
                                    .fill(Color.cozyOrange)
                                    .frame(width: geo.size.width * CGFloat(progress) / CGFloat(achievement.target))
                            }
                        }
                        .frame(height: 5)
                        Text("\(progress)/\(achievement.target)")
                            .font(.dhBadge)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if let unlockedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.freedomGreen)
                    Text(unlockedAt, format: .dateTime.day().month())
                        .font(.dhBadge)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(achievement.title). \(achievement.description) "
            + (isUnlocked ? "Unlocked." : "\(progress) of \(achievement.target).")
        )
    }
}

#Preview {
    AchievementsSheet(achievements: AchievementService(), snapshot: nil)
}
