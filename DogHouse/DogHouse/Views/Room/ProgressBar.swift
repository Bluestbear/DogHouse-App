//
//  ProgressBar.swift
//  DogHouse
//

import SwiftUI

struct RoomProgressBar: View {
    var level: RoomLevel
    var timeSinceRelease: TimeInterval

    private var progress: Double {
        guard let next = level.next else { return 1.0 }
        let currentThreshold = level.timeThreshold
        let nextThreshold = next.timeThreshold
        let range = nextThreshold - currentThreshold
        guard range > 0 else { return 1.0 }
        let elapsed = timeSinceRelease - currentThreshold
        return min(max(elapsed / range, 0), 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Level name
            HStack {
                Text("Lv.\(level.rawValue)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.cozyOrange)
                    .clipShape(Capsule())

                Text(level.name)
                    .font(.subheadline.bold())

                Spacer()

                // Only the top level is the max; luxury starts two levels
                // earlier (VIP Lounge) and showed MAX with levels still to go.
                if level.next == nil {
                    Text("MAX")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color.cozyOrange, Color.freedomGreen],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)

            // Next unlock info
            if let next = level.next, let timeRemaining = level.timeToNextLevel(currentTime: timeSinceRelease) {
                HStack {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Next: \(next.unlockMessage) in \(timeRemaining.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }
}

#Preview {
    VStack(spacing: 16) {
        RoomProgressBar(level: .bareBones, timeSinceRelease: 1800)
        RoomProgressBar(level: .fireplace, timeSinceRelease: 300000)
        RoomProgressBar(level: .luxury, timeSinceRelease: 3000000)
    }
}
