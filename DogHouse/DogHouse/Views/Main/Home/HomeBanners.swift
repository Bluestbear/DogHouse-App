//
//  HomeBanners.swift
//  DogHouse
//
//  The full-width cards that stack above the room scenes on Home.
//

import SwiftUI

// MARK: - Notifications Denied

/// DogHouse is a notification-driven app — being sent to the doghouse is
/// something you find out about by push. Without permission it silently does
/// nothing, so this sits at the top of Home until it's fixed.
struct NotificationsDeniedBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off")
                        .font(.dhBodyBold)
                        .foregroundStyle(.white)
                    Text("DogHouse can't work without them — tap to enable in Settings")
                        .font(.dhCaption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(Color.red.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel("Notifications are disabled. Tap to open Settings and enable them.")
    }
}

// MARK: - Anniversary Race

/// Shown only on the couple's anniversary, until one of them taps it.
struct AnniversaryRaceBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("💍 IT'S YOUR ANNIVERSARY! 💍")
                    .font(.headline)
                Text("Tap FIRST to wish it & win a Whatever-I-Want card!")
                    .font(.caption)
                    .opacity(0.95)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color.cozyOrange, Color(red: 0.9, green: 0.35, blue: 0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: - Photo Dash Result

/// The winning photo from the most recent photo dash, shown to both partners
/// for 24 hours.
struct PhotoDashResultCard: View {
    let dash: Challenge
    let iWon: Bool
    let partnerName: String

    /// Decoded once when the photo arrives, not on every redraw. Turning a
    /// base64 string into a UIImage inside `body` re-ran the decode on every
    /// evaluation of the Home screen.
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("📸").font(.title3)
                Text(iWon ? "You won the Photo Dash! 🎉"
                          : "\(partnerName) won the Photo Dash")
                    .font(.dhBodyBold)
                Spacer()
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(dash.prompt)
                .font(.dhCaption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.freedomGreen.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .task(id: dash.photoData) {
            guard let base64 = dash.photoData else { image = nil; return }
            // Off the main actor: these are camera-sized JPEGs.
            image = await Task.detached(priority: .userInitiated) {
                Data(base64Encoded: base64).flatMap(UIImage.init(data:))
            }.value
        }
    }
}

// MARK: - Grace Meter

/// How many sends the user has left. Recharges one per day.
struct GraceMeterView: View {
    let charges: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(charges > 0 ? Color.cozyOrange : .red)
                Text("Grace")
                    .font(.dhCaptionBold)
                Spacer()
                Text("\(charges) / \(UserProfile.maxGraceCharges)")
                    .font(.dhCaptionBold)
                    .foregroundStyle(charges > 0 ? Color.primary : Color.red)
            }

            // Charge pips
            HStack(spacing: 6) {
                ForEach(0..<UserProfile.maxGraceCharges, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index < charges ? Color.cozyOrange : Color(.systemGray4))
                        .frame(height: 8)
                }
            }
            // The pips encode the count purely through colour.
            .accessibilityHidden(true)

            if charges < UserProfile.maxGraceCharges {
                Text("Recharges 1 per day")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        // Read as one sentence instead of four disconnected fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Grace: \(charges) of \(UserProfile.maxGraceCharges) remaining."
            + (charges < UserProfile.maxGraceCharges ? " Recharges one per day." : "")
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            NotificationsDeniedBanner {}
            AnniversaryRaceBanner {}
            GraceMeterView(charges: 2)
            GraceMeterView(charges: 0)
        }
    }
}
