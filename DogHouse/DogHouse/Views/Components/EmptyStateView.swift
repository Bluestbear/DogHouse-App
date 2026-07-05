//
//  EmptyStateView.swift
//  DogHouse
//
//  Reusable empty state component with icon, title, subtitle, and optional action.
//

import SwiftUI

struct EmptyStateView: View {
    var icon: String
    var title: String
    var subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.cozyOrange.opacity(0.6))

            Text(title)
                .font(.dhHeading)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.dhCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.dhCaptionBold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

#Preview {
    EmptyStateView(
        icon: "person.2.slash",
        title: "No Friends Yet",
        subtitle: "Share your code to connect with friends!",
        actionTitle: "Copy Code"
    ) {
        print("Copy code tapped")
    }
}
