//
//  AvatarPickerView.swift
//  DogHouse
//

import SwiftUI

struct AvatarPickerView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: String
    @State private var confirmScale: CGFloat = 1.0

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    init(currentAvatarId: String = "dog_1") {
        _selectedId = State(initialValue: currentAvatarId)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Selected avatar preview
                VStack(spacing: 8) {
                    AvatarView(
                        avatar: DogAvatar.avatar(for: selectedId),
                        mood: .happy,
                        size: 120
                    )
                    .scaleEffect(confirmScale)

                    Text(DogAvatar.avatar(for: selectedId).name)
                        .font(.title3.bold())
                }
                .padding(.top, 16)

                // Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DogAvatar.allAvatars) { avatar in
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedId = avatar.id
                            }
                        } label: {
                            VStack(spacing: 4) {
                                AvatarView(
                                    avatar: avatar,
                                    mood: .happy,
                                    size: 72
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedId == avatar.id ? Color.cozyOrange : Color.clear,
                                            lineWidth: 3
                                        )
                                        .frame(width: 78, height: 78)
                                )
                                .scaleEffect(selectedId == avatar.id ? 1.1 : 1.0)

                                Text(avatar.name)
                                    .font(.caption2)
                                    .foregroundStyle(selectedId == avatar.id ? Color.cozyOrange : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Confirm button
                Button {
                    authService.updateAvatar(id: selectedId)
                    dismiss()
                } label: {
                    Text("Confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Choose Your Dog")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AvatarPickerView()
        .environmentObject(AuthService())
}
