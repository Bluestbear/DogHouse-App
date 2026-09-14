//
//  PartnerControls.swift
//  DogHouse
//
//  The bottom half of Home: what I can do to my partner. Either they're in
//  the doghouse and I can let them out, or they're free and I can send them.
//

import SwiftUI

// MARK: - Partner In The Doghouse

/// Their status plus the release button, shown when I'm the one who sent them.
struct PartnerInDoghouseCard: View {
    let event: DoghouseEvent
    let partnerName: String
    let avatarId: String
    let cosmetics: AvatarCosmetics
    /// Coarse "now" — this card only ever shows "sent 2 hours ago".
    let now: Date
    let onRelease: () -> Void

    private var byRedemption: Bool { event.redemptionRequested == true }

    var body: some View {
        VStack(spacing: 12) {
            // Partner's avatar + status
            HStack(spacing: 12) {
                AvatarView(
                    avatar: DogAvatar.avatar(for: avatarId),
                    mood: .sad,
                    size: 56,
                    cosmetics: cosmetics
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partnerName) is in the DogHouse")
                        .font(.dhBodyBold)
                        .foregroundStyle(.red)
                    Text("Sent \(now.timeIntervalSince(event.startedAt).formattedDuration) ago")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Reason
            VStack(alignment: .leading, spacing: 4) {
                Text("Reason: \(event.reason)")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                if let suggestion = event.suggestion {
                    Text("To get out: \(suggestion)")
                        .font(.dhCaption)
                        .foregroundStyle(Color.cozyOrange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Redemption requested — the dog says they made it up
            if byRedemption {
                redemptionClaimRow
            }

            // Release button — confirming a redemption also rewards treats
            Button(action: onRelease) {
                HStack {
                    Image(systemName: "lock.open.fill")
                    Text(byRedemption
                         ? "Confirm & Let \(partnerName) Out 🦴"
                         : "Let \(partnerName) Out 🏠")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.freedomGreen)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Release \(partnerName) from the doghouse")
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private var redemptionClaimRow: some View {
        HStack(spacing: 10) {
            Text("🦴")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(partnerName) says they made it up!")
                    .font(.dhBodyBold)
                if let suggestion = event.suggestion {
                    Text("\"\(suggestion)\"")
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cozyOrange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Why the send button is greyed out: they were just let out and are briefly
/// untouchable.
struct PartnerImmunityBanner: View {
    let partnerName: String
    let immunityEnd: Date
    /// Coarse "now" — the banner reads "expires in 40 minutes".
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(partnerName) has immunity!")
                    .font(.dhCaptionBold)
                Text("Expires in \(immunityEnd.timeIntervalSince(now).formattedDuration)")
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }
}

// MARK: - Send Button

struct SendToDoghouseButton: View {
    let partnerName: String
    /// Immunity blocks the send outright; no grace charges blocks it too, but
    /// for a different reason — VoiceOver should say which.
    let partnerHasImmunity: Bool
    let hasGraceCharges: Bool
    let onTap: () -> Void

    private var isDisabled: Bool { partnerHasImmunity || !hasGraceCharges }

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "house.fill")
                Text("Send \(partnerName) to the DogHouse 🐕")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDisabled ? Color.gray.opacity(0.4) : Color.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isDisabled)
        .accessibilityLabel(isDisabled
            ? partnerHasImmunity
                ? "\(partnerName) has immunity, cannot send to doghouse"
                : "No grace charges remaining"
            : "Send \(partnerName) to the doghouse")
        .padding(.horizontal, 20)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            PartnerImmunityBanner(
                partnerName: "Sam",
                immunityEnd: Date().addingTimeInterval(2_400),
                now: Date()
            )
            SendToDoghouseButton(
                partnerName: "Sam",
                partnerHasImmunity: false,
                hasGraceCharges: true,
                onTap: {}
            )
            SendToDoghouseButton(
                partnerName: "Sam",
                partnerHasImmunity: true,
                hasGraceCharges: true,
                onTap: {}
            )
        }
    }
}
