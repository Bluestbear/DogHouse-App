//
//  NotificationPermissionView.swift
//  DogHouse
//
//  Pre-permission explainer shown before the system notification prompt.
//  DogHouse is notification-driven — this raises opt-in by explaining why
//  before iOS asks (you only get one shot at the system prompt).
//

import SwiftUI

struct NotificationPermissionView: View {
    @ObservedObject var notificationService: NotificationService
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("🔔")
                .font(.system(size: 72))

            VStack(spacing: 10) {
                Text("DogHouse runs on notifications")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Without them, you won't know when you've been sent to the doghouse — and your partner won't know when you've made it up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            VStack(alignment: .leading, spacing: 14) {
                explainerRow("🐕", "Know instantly when you're in trouble")
                explainerRow("🦴", "Get told when you're forgiven")
                explainerRow("🗳️", "Vote when friends land in the doghouse")
                explainerRow("🐾", "Never miss a belly rub")
            }
            .padding(20)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    isRequesting = true
                    Task {
                        await notificationService.requestPermission()
                        isRequesting = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Enable Notifications")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cozyOrange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isRequesting)

                Button("Maybe later") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .dhPageBackground()
        .interactiveDismissDisabled(isRequesting)
    }

    private func explainerRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
            Text(text)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NotificationPermissionView(notificationService: .shared)
}
